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
from handlers.bundle_vocabulary import get_active_test_type, TEST_TYPE_MAPPING
from services.audio_service import get_or_generate_audio_base64

logger = logging.getLogger(__name__)


def get_review_words_batch():
    """
    Get multiple review words with enhanced questions in a single request.

    GET /v3/next-review-words-batch?user_id=xxx&count=10&exclude_words=word1,word2

    Priority System (always returns questions):
    1. DUE: Random due words (next_review <= NOW)
    2. BUNDLE: New words from active bundle (if user has one)
    3. EVERYDAY: New words from everyday_english bundle
    4. RANDOM: Random words from ANY bundle (absolute fallback)

    Returns:
        JSON with array of questions and metadata including full definition.
        Each question has a 'source' field: DUE, BUNDLE, EVERYDAY, or RANDOM
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
            # PRIORITY 1: Get random due words using shared service
            # ============================================================
            from services.due_words_service import build_due_words_base_query

            from_where_clause, params = build_due_words_base_query(
                user_id,
                exclude_words=list(exclude_words) if exclude_words else None
            )

            due_words_query = f"""
                SELECT sw.id as saved_word_id, sw.word, sw.learning_language, sw.native_language
                {from_where_clause}
                ORDER BY RANDOM()
                LIMIT %s
            """

            cur.execute(due_words_query, params + [count])
            due_words = cur.fetchall()

            logger.info(f"Fetched {len(due_words)} due words for user {user_id}")

            for row in due_words:
                all_word_rows.append({
                    'saved_word_id': row['saved_word_id'],
                    'word': row['word'],
                    'learning_language': row['learning_language'],
                    'native_language': row['native_language'],
                    'source_type': 'DUE'
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

                if test_type and test_type in TEST_TYPE_MAPPING:
                    # Get the vocab column for this test type (e.g., 'is_toefl_beginner')
                    vocab_column = TEST_TYPE_MAPPING[test_type][2]

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

                    # Use format() for column name (safe since we validated test_type in TEST_TYPE_MAPPING)
                    new_words_query = f"""
                        SELECT bv.word, up.learning_language, up.native_language
                        FROM bundle_vocabularies bv
                        CROSS JOIN user_preferences up
                        WHERE up.user_id = %s
                        AND bv.{vocab_column} = TRUE
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

                    cur.execute(new_words_query, (user_id, *exclude_params, count - len(all_word_rows)))
                    new_words = cur.fetchall()

                    logger.info(f"Fetched {len(new_words)} new words from active bundle '{test_type}' for user {user_id}")

                    for row in new_words:
                        all_word_rows.append({
                            'saved_word_id': None,  # New words don't have saved_word_id yet
                            'word': row['word'],
                            'learning_language': row['learning_language'],
                            'native_language': row['native_language'],
                            'source_type': 'BUNDLE'
                        })

            # ============================================================
            # PRIORITY 3: If still not enough, get random new words from everyday English
            # ============================================================
            if len(all_word_rows) < count:
                # Add all fetched words to exclusion set
                all_excluded = exclude_words.copy()
                for word_dict in all_word_rows:
                    all_excluded.add(word_dict['word'])

                exclude_clause = ""
                exclude_params = []
                if all_excluded:
                    placeholders = ','.join(['%s'] * len(all_excluded))
                    exclude_clause = f"AND bv.word NOT IN ({placeholders})"
                    exclude_params = list(all_excluded)

                everyday_query = f"""
                    SELECT bv.word, up.learning_language, up.native_language
                    FROM bundle_vocabularies bv
                    CROSS JOIN user_preferences up
                    WHERE up.user_id = %s
                    AND bv.everyday_english = TRUE
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

                cur.execute(everyday_query, (user_id, *exclude_params, count - len(all_word_rows)))
                everyday_words = cur.fetchall()

                logger.info(f"Fetched {len(everyday_words)} fallback words from everyday_english for user {user_id}")

                for row in everyday_words:
                    all_word_rows.append({
                        'saved_word_id': None,  # New words don't have saved_word_id yet
                        'word': row['word'],
                        'learning_language': row['learning_language'],
                        'native_language': row['native_language'],
                        'source_type': 'EVERYDAY'
                    })

            # ============================================================
            # PRIORITY 4: If STILL not enough, get random words from ANY bundle
            # ============================================================
            if len(all_word_rows) < count:
                # Add all fetched words to exclusion set
                all_excluded = exclude_words.copy()
                for word_dict in all_word_rows:
                    all_excluded.add(word_dict['word'])

                exclude_clause = ""
                exclude_params = []
                if all_excluded:
                    placeholders = ','.join(['%s'] * len(all_excluded))
                    exclude_clause = f"AND bv.word NOT IN ({placeholders})"
                    exclude_params = list(all_excluded)

                # Get random words from ANY bundle (any TRUE column)
                random_query = f"""
                    SELECT bv.word, up.learning_language, up.native_language
                    FROM bundle_vocabularies bv
                    CROSS JOIN user_preferences up
                    WHERE up.user_id = %s
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

                cur.execute(random_query, (user_id, *exclude_params, count - len(all_word_rows)))
                random_words = cur.fetchall()

                logger.info(f"Fetched {len(random_words)} random words from any bundle for user {user_id}")

                for row in random_words:
                    all_word_rows.append({
                        'saved_word_id': None,  # New words don't have saved_word_id yet
                        'word': row['word'],
                        'learning_language': row['learning_language'],
                        'native_language': row['native_language'],
                        'source_type': 'RANDOM'
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
