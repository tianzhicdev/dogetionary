"""
Batch Review Handler

Provides endpoint for fetching multiple review questions at once for performance.
This allows iOS to maintain a local queue and provide instant question transitions.
"""

from flask import jsonify, request
import logging
import json
import base64
from typing import Dict, Any, Optional, List
from utils.database import db_fetch_one, get_db_connection
from services.question_generation_service import get_or_generate_question
from services.user_service import get_user_preferences
from handlers.bundle_vocabulary import get_active_test_type
from services.audio_service import get_or_generate_audio_base64

logger = logging.getLogger(__name__)


def fetch_and_cache_definition(word: str, learning_lang: str, native_lang: str) -> Optional[Dict]:
    """
    Get definition for a word - checks cache first, then fetches from LLM if needed.

    Args:
        word: The word to get definition for
        learning_lang: Learning language code
        native_lang: Native language code

    Returns:
        Definition data dictionary or None if failed
    """
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # Check cache first
        cur.execute("""
            SELECT definition_data
            FROM definitions
            WHERE word = %s
              AND learning_language = %s
              AND native_language = %s
        """, (word, learning_lang, native_lang))

        cached_result = cur.fetchone()
        cur.close()
        conn.close()

        if cached_result:
            logger.info(f"Found cached definition for '{word}'")
            return cached_result['definition_data']

        # Cache miss - fetch from LLM
        logger.info(f"Cache miss for '{word}', fetching from LLM...")
        from services.definition_service import get_or_generate_definition

        definition_data = get_or_generate_definition(
            word=word,
            learning_lang=learning_lang,
            native_lang=native_lang
        )

        if definition_data:
            logger.info(f"Successfully fetched definition for '{word}'")
            return definition_data
        else:
            logger.warning(f"Failed to fetch definition for '{word}'")
            return None

    except Exception as e:
        logger.error(f"Error fetching definition for '{word}': {e}", exc_info=True)
        return None


def get_review_words_batch():
    """
    Get multiple review words with enhanced questions in a single request - SIMPLIFIED VERSION.

    GET /v3/next-review-words-batch?user_id=xxx&count=10&exclude_words=word1,word2

    Simple Priority:
    1. Random due words (next_review <= NOW) - prioritize these
    2. If not enough due words, random new words from active bundle

    Returns:
        JSON with array of questions and metadata including full definition
    """
    try:
        user_id = request.args.get('user_id')
        count = request.args.get('count', '10')
        exclude_words_param = request.args.get('exclude_words', '')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        try:
            count = int(count)
            count = min(max(count, 1), 20)  # Clamp between 1 and 20
        except ValueError:
            count = 10

        # Parse exclude_words
        exclude_words = set()
        if exclude_words_param:
            exclude_words = set(w.strip() for w in exclude_words_param.split(',') if w.strip())

        # Get user preferences
        learning_lang, native_lang, _, _ = get_user_preferences(user_id)

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            all_word_rows = []  # List of word dictionaries to process

            # ============================================================
            # PRIORITY 1: Get random due words (next_review <= NOW)
            # ============================================================
            exclude_clause = ""
            exclude_params = []
            if exclude_words:
                placeholders = ','.join(['%s'] * len(exclude_words))
                exclude_clause = f"AND sw.word NOT IN ({placeholders})"
                exclude_params = list(exclude_words)

            due_words_query = f"""
                SELECT sw.id as saved_word_id, sw.word, sw.learning_language, sw.native_language
                FROM saved_words sw
                LEFT JOIN (
                    SELECT word_id, next_review_date,
                           ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                    FROM reviews
                ) r ON sw.id = r.word_id AND r.rn = 1
                WHERE sw.user_id = %s
                AND (sw.is_known IS NULL OR sw.is_known = FALSE)
                AND (
                    r.next_review_date IS NULL OR  -- Never reviewed
                    r.next_review_date <= CURRENT_DATE  -- Due today or earlier
                )
                {exclude_clause}
                ORDER BY RANDOM()
                LIMIT %s
            """

            cur.execute(due_words_query, (user_id, *exclude_params, count))
            due_words = cur.fetchall()

            for row in due_words:
                all_word_rows.append({
                    'saved_word_id': row['saved_word_id'],
                    'word': row['word'],
                    'learning_language': row['learning_language'],
                    'native_language': row['native_language'],
                    'source_type': 'due'
                })

            # ============================================================
            # PRIORITY 2: If not enough due words, get random new words from active bundle
            # ============================================================
            if len(all_word_rows) < count:
                # Get user preferences to check for active test type
                prefs_row = db_fetch_one("""
                    SELECT * FROM user_preferences WHERE user_id = %s
                """, (user_id,))

                test_type = get_active_test_type(prefs_row) if prefs_row else None

                if test_type:
                    # Add fetched words to exclusion set
                    all_excluded = exclude_words.copy()
                    for word_dict in all_word_rows:
                        all_excluded.add(word_dict['word'])

                    exclude_clause = ""
                    exclude_params = []
                    if all_excluded:
                        placeholders = ','.join(['%s'] * len(all_excluded))
                        exclude_clause = f"AND bv.word NOT IN ({placeholders})"
                        exclude_params = list(all_excluded)

                    new_words_query = f"""
                        SELECT bv.word, up.learning_language, up.native_language
                        FROM bundle_vocabularies bv
                        CROSS JOIN user_preferences up
                        WHERE up.user_id = %s
                        AND bv.bundle_name = %s
                        AND bv.language = up.learning_language
                        {exclude_clause}
                        AND NOT EXISTS (
                            SELECT 1 FROM saved_words sw
                            WHERE sw.user_id = up.user_id
                            AND sw.word = bv.word
                            AND sw.learning_language = bv.language
                        )
                        ORDER BY RANDOM()
                        LIMIT %s
                    """

                    cur.execute(new_words_query, (user_id, test_type, *exclude_params, count - len(all_word_rows)))
                    new_words = cur.fetchall()

                    for row in new_words:
                        all_word_rows.append({
                            'saved_word_id': None,  # New words don't have saved_word_id yet
                            'word': row['word'],
                            'learning_language': row['learning_language'],
                            'native_language': row['native_language'],
                            'source_type': 'new'
                        })

            # Generate questions for each word with position
            questions = []
            for position, row in enumerate(all_word_rows):
                word = row['word']
                saved_word_id = row['saved_word_id']  # May be None for new words
                word_learning_lang = row.get('learning_language', learning_lang)
                word_native_lang = row.get('native_language', native_lang)
                source_type = row.get('source_type', 'unknown')

                # Get complete question data (definition + question + audio)
                result = get_or_generate_question(
                    word=word,
                    learning_lang=word_learning_lang,
                    native_lang=word_native_lang,
                    question_type=None
                )

                if result is None:
                    logger.warning(f"Could not generate question for '{word}', skipping")
                    continue  # Skip words that failed

                # Extract data from result
                question = result['question']
                definition_data = result['definition_data']
                audio_refs = result['audio_references']

                questions.append({
                    "word": word,
                    "saved_word_id": saved_word_id,  # null for new words, integer for saved words
                    "source": source_type,
                    "position": position,
                    "learning_language": word_learning_lang,
                    "native_language": word_native_lang,
                    "question": question,
                    "definition": {
                        "word": word,
                        "learning_language": word_learning_lang,
                        "native_language": word_native_lang,
                        "definition_data": definition_data,
                        "audio_references": audio_refs,
                        "audio_generation_status": "complete"  # Assume complete for cached definitions
                    }
                })

            return jsonify({
                "questions": questions,
                "total_available": 0,  # Deprecated, always 0
                "has_more": True  # Always true to avoid expensive counting queries
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting batch review words: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500
