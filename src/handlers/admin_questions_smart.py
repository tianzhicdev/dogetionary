"""
Smart Admin Question Generation Handler

Provides intelligent batch pre-generation that only processes incomplete words.
Automatically generates missing definitions and all required question types.
"""

from flask import jsonify, request
import logging
import time
from typing import Dict, List, Optional, Tuple
from utils.database import db_fetch_all, db_fetch_one
from services.question_generation_service import get_or_generate_question, QUESTION_TYPE_WEIGHTS
from services.definition_service import get_or_generate_definition

logger = logging.getLogger(__name__)

# All supported question types
ALL_QUESTION_TYPES = list(QUESTION_TYPE_WEIGHTS.keys())


def smart_batch_generate_questions():
    """
    POST /v3/admin/questions/smart-batch-generate

    Intelligently selects and processes only incomplete words.
    Generates missing definitions and all question types in a single call.

    Request JSON:
    {
        "source": "demo_bundle",          // or "toefl", "ielts", etc.
        "num_words": 10,                  // number of incomplete words to process
        "learning_language": "en",        // required
        "native_language": "zh",          // required
        "strategy": "missing_any"         // optional: "missing_any", "missing_definition", "missing_questions"
    }

    Returns:
    {
        "statistics": {
            "words_requested": 10,
            "words_processed": 10,
            "definitions_cached": 7,
            "definitions_created": 3,
            "questions_cached": 35,
            "questions_generated": 15,
            "errors": 0,
            "duration_seconds": 45.2
        },
        "next_incomplete_count": 605,
        "progress_percentage": 1.6
    }
    """
    start_time = time.time()

    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No JSON data provided"}), 400

        # Required fields
        learning_lang = data.get('learning_language')
        native_lang = data.get('native_language')
        source = data.get('source')
        num_words = data.get('num_words', 10)

        if not learning_lang or not native_lang or not source:
            return jsonify({
                "error": "learning_language, native_language, and source are required"
            }), 400

        # Optional fields
        strategy = data.get('strategy', 'missing_any')

        # Validate strategy
        valid_strategies = ['missing_any', 'missing_definition', 'missing_questions', 'missing_video_questions']
        if strategy not in valid_strategies:
            return jsonify({
                "error": f"Invalid strategy. Must be one of: {', '.join(valid_strategies)}"
            }), 400

        # Find incomplete words
        logger.info(f"Finding {num_words} incomplete words from {source} using strategy '{strategy}'")
        incomplete_words = find_incomplete_words(
            source=source,
            num_words=num_words,
            learning_lang=learning_lang,
            native_lang=native_lang,
            strategy=strategy
        )

        if not incomplete_words:
            # Check if all words are complete
            total_words = get_total_words_count(source, learning_lang)
            return jsonify({
                "message": "All words are complete!",
                "statistics": {
                    "words_requested": num_words,
                    "words_processed": 0,
                    "definitions_cached": 0,
                    "definitions_created": 0,
                    "questions_cached": 0,
                    "questions_generated": 0,
                    "errors": 0,
                    "duration_seconds": 0
                },
                "next_incomplete_count": 0,
                "progress_percentage": 100.0,
                "total_words": total_words
            }), 200

        # Statistics
        stats = {
            'words_requested': num_words,
            'words_processed': 0,
            'definitions_cached': 0,
            'definitions_created': 0,
            'questions_cached': 0,
            'questions_generated': 0,
            'by_question_type': {qt: {'cached': 0, 'generated': 0} for qt in ALL_QUESTION_TYPES},
            'errors': 0,
            'error_details': []
        }

        # Process each incomplete word
        for i, word_info in enumerate(incomplete_words, 1):
            word = word_info['word']
            has_definition = word_info['has_definition']
            has_video = word_info['has_video']

            try:
                logger.info(f"[{i}/{len(incomplete_words)}] Processing '{word}' "
                           f"(def={has_definition}, video={has_video})")

                # Step 1: Get or generate definition
                if not has_definition:
                    definition_data = get_or_generate_definition(word, learning_lang, native_lang)
                    if not definition_data:
                        logger.error(f"Failed to generate definition for '{word}'", exc_info=True)
                        stats['errors'] += 1
                        stats['error_details'].append(f"Definition generation failed for '{word}'")
                        continue
                    stats['definitions_created'] += 1
                    logger.info(f"  ✓ Created definition")
                else:
                    definition = db_fetch_one("""
                        SELECT definition_data
                        FROM definitions
                        WHERE word = %s
                        AND learning_language = %s
                        AND native_language = %s
                    """, (word, learning_lang, native_lang))
                    definition_data = definition['definition_data']
                    stats['definitions_cached'] += 1
                    logger.debug(f"  ✓ Using cached definition")

                # Step 2: Determine which question types to generate
                question_types_to_generate = determine_question_types(
                    word=word,
                    learning_lang=learning_lang,
                    native_lang=native_lang,
                    has_video=has_video
                )

                # Step 3: Generate missing questions
                for question_type in question_types_to_generate:
                    try:
                        # Check if already cached
                        existing = db_fetch_one("""
                            SELECT id FROM review_questions
                            WHERE word = %s
                            AND learning_language = %s
                            AND native_language = %s
                            AND question_type = %s
                        """, (word, learning_lang, native_lang, question_type))

                        if existing:
                            stats['questions_cached'] += 1
                            stats['by_question_type'][question_type]['cached'] += 1
                            logger.debug(f"  [{question_type}] cached")
                        else:
                            # Generate new question
                            question = get_or_generate_question(
                                word=word,
                                definition=definition_data,
                                learning_lang=learning_lang,
                                native_lang=native_lang,
                                question_type=question_type
                            )
                            stats['questions_generated'] += 1
                            stats['by_question_type'][question_type]['generated'] += 1
                            logger.info(f"  [{question_type}] ✓ generated")

                    except Exception as e:
                        stats['errors'] += 1
                        error_msg = f"Question generation failed for '{word}' ({question_type}): {str(e)}"
                        stats['error_details'].append(error_msg)
                        logger.error(error_msg, exc_info=True)
                        continue

                stats['words_processed'] += 1

                # Progress update every 5 words
                if i % 5 == 0:
                    logger.info(f"Progress: {i}/{len(incomplete_words)} words, "
                               f"{stats['questions_generated']} new questions")

            except Exception as e:
                stats['errors'] += 1
                error_msg = f"Error processing '{word}': {str(e)}"
                stats['error_details'].append(error_msg)
                logger.error(error_msg, exc_info=True)
                continue

        # Calculate next incomplete count
        next_incomplete = count_incomplete_words(source, learning_lang, native_lang, strategy)
        total_words = get_total_words_count(source, learning_lang)
        progress = ((total_words - next_incomplete) / total_words * 100) if total_words > 0 else 0

        duration = time.time() - start_time
        stats['duration_seconds'] = round(duration, 2)
        stats['avg_seconds_per_word'] = round(duration / stats['words_processed'], 2) if stats['words_processed'] > 0 else 0

        logger.info(f"Smart batch complete: {stats['words_processed']} words, "
                   f"{stats['questions_generated']} new questions, "
                   f"{next_incomplete} remaining")

        return jsonify({
            "message": "Smart batch generation complete",
            "statistics": stats,
            "next_incomplete_count": next_incomplete,
            "progress_percentage": round(progress, 2),
            "total_words": total_words
        }), 200

    except Exception as e:
        logger.error(f"Error in smart_batch_generate_questions: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


def find_incomplete_words(
    source: str,
    num_words: int,
    learning_lang: str,
    native_lang: str,
    strategy: str = 'missing_any'
) -> List[Dict]:
    """
    Find words that need definitions or questions generated.

    Args:
        source: Test vocabulary source ('demo_bundle', 'toefl', etc.)
        num_words: Number of incomplete words to return
        learning_lang: Language being learned
        native_lang: User's native language
        strategy: Selection strategy

    Returns:
        List of dicts with keys: word, has_definition, question_count, has_video, priority
    """
    # Map source to column name
    source_column_map = {
        'demo_bundle': 'is_demo',
        'demo': 'is_demo',
        'toefl': 'is_toefl',
        'ielts': 'is_ielts',
        'toefl_beginner': 'is_toefl_beginner',
        'toefl_intermediate': 'is_toefl_intermediate',
        'toefl_advanced': 'is_toefl_advanced',
        'ielts_beginner': 'is_ielts_beginner',
        'ielts_intermediate': 'is_ielts_intermediate',
        'ielts_advanced': 'is_ielts_advanced',
    }

    column = source_column_map.get(source)
    if not column:
        logger.error(f"Unknown source: {source}", exc_info=True)
        return []

    # Build WHERE clause based on strategy
    if strategy == 'missing_definition':
        strategy_filter = "NOT ws.has_definition"
    elif strategy == 'missing_questions':
        strategy_filter = "ws.has_definition AND ws.question_count < 5"
    elif strategy == 'missing_video_questions':
        strategy_filter = """
            ws.has_video AND NOT EXISTS (
                SELECT 1 FROM review_questions rq
                WHERE rq.word = ws.word
                AND rq.learning_language = ws.language
                AND rq.native_language = %s
                AND rq.question_type = 'video_mc'
            )
        """
    else:  # missing_any (default)
        strategy_filter = "NOT ws.has_definition OR ws.question_count < 5"

    query = f"""
        WITH word_status AS (
            SELECT
                tv.word,
                tv.language,
                EXISTS (
                    SELECT 1 FROM definitions d
                    WHERE d.word = tv.word
                    AND d.learning_language = tv.language
                    AND d.native_language = %s
                ) AS has_definition,
                (
                    SELECT COUNT(DISTINCT question_type)
                    FROM review_questions rq
                    WHERE rq.word = tv.word
                    AND rq.learning_language = tv.language
                    AND rq.native_language = %s
                ) AS question_count,
                EXISTS (
                    SELECT 1 FROM word_to_video w2v
                    WHERE w2v.word = tv.word
                    AND w2v.learning_language = tv.language
                ) AS has_video
            FROM bundle_vocabularies tv
            WHERE tv.{column} = true
            AND tv.language = %s
        )
        SELECT
            word,
            has_definition,
            question_count,
            has_video,
            CASE
                WHEN NOT has_definition THEN 1000
                WHEN question_count = 0 THEN 900
                WHEN question_count < 5 THEN 500 + (5 - question_count) * 100
                ELSE 0
            END AS priority
        FROM word_status ws
        WHERE {strategy_filter}
        ORDER BY priority DESC, word ASC
        LIMIT %s
    """

    params = (native_lang, native_lang, learning_lang, num_words)
    words = db_fetch_all(query, params)

    return words


def determine_question_types(word: str, learning_lang: str, native_lang: str, has_video: bool) -> List[str]:
    """
    Determine which question types should be generated for a word.

    Args:
        word: The word
        learning_lang: Language being learned
        native_lang: User's native language
        has_video: Whether word has video mapping

    Returns:
        List of question types that should exist for this word
    """
    if has_video:
        # Word has video: use all 5 question types
        return ALL_QUESTION_TYPES
    else:
        # No video: use 4 non-video types + extra mc_definition
        return ['mc_definition', 'mc_word', 'fill_blank', 'pronounce_sentence', 'mc_definition']


def count_incomplete_words(source: str, learning_lang: str, native_lang: str, strategy: str) -> int:
    """
    Count how many incomplete words remain.

    Args:
        source: Test vocabulary source
        learning_lang: Language being learned
        native_lang: User's native language
        strategy: Selection strategy

    Returns:
        Number of incomplete words
    """
    # Reuse find_incomplete_words but with high limit to get count
    incomplete = find_incomplete_words(
        source=source,
        num_words=999999,  # Large number to get all incomplete
        learning_lang=learning_lang,
        native_lang=native_lang,
        strategy=strategy
    )
    return len(incomplete)


def get_total_words_count(source: str, learning_lang: str) -> int:
    """
    Get total number of words in the source.

    Args:
        source: Test vocabulary source
        learning_lang: Language being learned

    Returns:
        Total word count
    """
    source_column_map = {
        'demo_bundle': 'is_demo',
        'demo': 'is_demo',
        'toefl': 'is_toefl',
        'ielts': 'is_ielts',
        'toefl_beginner': 'is_toefl_beginner',
        'toefl_intermediate': 'is_toefl_intermediate',
        'toefl_advanced': 'is_toefl_advanced',
        'ielts_beginner': 'is_ielts_beginner',
        'ielts_intermediate': 'is_ielts_intermediate',
        'ielts_advanced': 'is_ielts_advanced',
    }

    column = source_column_map.get(source)
    if not column:
        return 0

    result = db_fetch_one(f"""
        SELECT COUNT(*) as count
        FROM bundle_vocabularies
        WHERE {column} = true
        AND language = %s
    """, (learning_lang,))

    return result['count'] if result else 0
