"""
Admin Question Generation Handler

Provides endpoint for batch pre-generating review questions to populate cache.
This eliminates LLM delays during user review sessions.
"""

from flask import jsonify, request
import logging
import time
from typing import Dict, List, Optional
from utils.database import db_fetch_all, db_fetch_one
from services.question_generation_service import get_or_generate_question, QUESTION_TYPE_WEIGHTS

logger = logging.getLogger(__name__)

# All supported question types
ALL_QUESTION_TYPES = list(QUESTION_TYPE_WEIGHTS.keys())


def batch_generate_questions():
    """
    POST /v3/admin/questions/batch-generate

    Pre-generate ALL question types for a word list to populate cache.
    This makes review sessions instant by eliminating LLM calls.

    Request JSON:
    {
        "source": "tianz_test",  // or "toefl", "ielts", "toefl_beginner", etc.
        "words": ["apple", "banana"],  // optional: specific words (overrides source)
        "learning_language": "en",  // required
        "native_language": "zh",    // required
        "question_types": ["mc_definition", "video_mc"],  // optional: defaults to all
        "max_words": 100,  // optional: limit for testing
        "skip_existing": true  // optional: skip if all question types already cached
    }

    Returns:
    {
        "total_words": 615,
        "total_questions_generated": 3075,
        "cache_hits": 120,
        "new_generations": 2955,
        "skipped_words": 10,
        "errors": 5,
        "duration_seconds": 180
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

        if not learning_lang or not native_lang:
            return jsonify({"error": "learning_language and native_language are required"}), 400

        # Optional fields
        source = data.get('source')  # 'tianz_test', 'toefl', 'ielts', etc.
        specific_words = data.get('words', [])
        question_types = data.get('question_types', ALL_QUESTION_TYPES)
        max_words = data.get('max_words')
        skip_existing = data.get('skip_existing', False)

        # Validate question types
        invalid_types = [qt for qt in question_types if qt not in ALL_QUESTION_TYPES]
        if invalid_types:
            return jsonify({"error": f"Invalid question types: {invalid_types}"}), 400

        # Get word list
        if specific_words:
            words = specific_words[:max_words] if max_words else specific_words
            logger.info(f"Using {len(words)} words from request payload")
        elif source:
            words = get_words_from_source(source, learning_lang, max_words)
            if not words:
                return jsonify({"error": f"No words found for source: {source}"}), 400
            logger.info(f"Loaded {len(words)} words from source: {source}")
        else:
            return jsonify({"error": "Either 'source' or 'words' must be provided"}), 400

        # Statistics
        stats = {
            'total_words': len(words),
            'total_questions_attempted': 0,
            'cache_hits': 0,
            'new_generations': 0,
            'skipped_words': 0,
            'errors': 0,
            'error_details': []
        }

        # Generate questions for each word
        for i, word in enumerate(words, 1):
            try:
                # Get definition
                definition = db_fetch_one("""
                    SELECT definition_data
                    FROM definitions
                    WHERE word = %s
                    AND learning_language = %s
                    AND native_language = %s
                """, (word, learning_lang, native_lang))

                if not definition or not definition.get('definition_data'):
                    logger.warning(f"[{i}/{len(words)}] No definition for '{word}', skipping")
                    stats['skipped_words'] += 1
                    continue

                definition_data = definition['definition_data']

                # Check if all question types already cached (if skip_existing=true)
                if skip_existing:
                    cached_types = db_fetch_all("""
                        SELECT question_type
                        FROM review_questions
                        WHERE word = %s
                        AND learning_language = %s
                        AND native_language = %s
                        AND question_type = ANY(%s)
                    """, (word, learning_lang, native_lang, question_types))

                    cached_type_set = {row['question_type'] for row in cached_types}
                    if cached_type_set == set(question_types):
                        logger.info(f"[{i}/{len(words)}] '{word}': all types cached, skipping")
                        stats['cache_hits'] += len(question_types)
                        stats['total_questions_attempted'] += len(question_types)
                        continue

                # Generate each question type
                for question_type in question_types:
                    stats['total_questions_attempted'] += 1

                    # Check cache before generating
                    existing = db_fetch_one("""
                        SELECT id FROM review_questions
                        WHERE word = %s
                        AND learning_language = %s
                        AND native_language = %s
                        AND question_type = %s
                    """, (word, learning_lang, native_lang, question_type))

                    if existing:
                        stats['cache_hits'] += 1
                        logger.debug(f"  [{question_type}] cached")
                    else:
                        # Generate and cache (this function handles caching internally)
                        question = get_or_generate_question(
                            word=word,
                            definition=definition_data,
                            learning_lang=learning_lang,
                            native_lang=native_lang,
                            question_type=question_type
                        )
                        stats['new_generations'] += 1
                        logger.debug(f"  [{question_type}] generated")

                if i % 10 == 0:
                    logger.info(f"Progress: {i}/{len(words)} words, "
                               f"{stats['new_generations']} new, "
                               f"{stats['cache_hits']} cached")

            except Exception as e:
                stats['errors'] += 1
                error_msg = f"Error processing '{word}': {str(e)}"
                stats['error_details'].append(error_msg)
                logger.error(error_msg, exc_info=True)
                continue

        duration = time.time() - start_time
        stats['duration_seconds'] = round(duration, 2)
        stats['questions_per_second'] = round(stats['total_questions_attempted'] / duration, 2) if duration > 0 else 0

        logger.info(f"Batch generation complete: {stats}")

        return jsonify({
            "message": "Batch question generation complete",
            "statistics": stats
        }), 200

    except Exception as e:
        logger.error(f"Error in batch_generate_questions: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


def get_words_from_source(source: str, learning_lang: str, max_words: Optional[int] = None) -> List[str]:
    """
    Get word list from test_vocabularies table based on source.

    Args:
        source: 'tianz_test', 'toefl', 'ielts', 'toefl_beginner', etc.
        learning_lang: Language of words
        max_words: Optional limit

    Returns:
        List of words
    """
    # Map source to column name
    source_column_map = {
        'tianz_test': 'is_tianz',
        'tianz': 'is_tianz',
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

    limit_clause = f"LIMIT {max_words}" if max_words else ""

    words = db_fetch_all(f"""
        SELECT word
        FROM test_vocabularies
        WHERE {column} = true
        AND language = %s
        ORDER BY word
        {limit_clause}
    """, (learning_lang,))

    return [row['word'] for row in words]
