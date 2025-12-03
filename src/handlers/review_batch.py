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
from utils.database import db_fetch_one, db_fetch_all, get_db_connection
from services.question_generation_service import get_or_generate_question
from services.user_service import get_user_preferences
from services.schedule_service import get_user_timezone, get_today_in_timezone

logger = logging.getLogger(__name__)


def get_or_generate_audio_base64(text: str, language: str) -> str:
    """
    Get or generate audio for text and return as base64 encoded data URI.

    Args:
        text: The text to generate audio for
        language: Language code (e.g., 'en', 'zh')

    Returns:
        Base64 encoded audio data URI (data:audio/mpeg;base64,...)
    """
    try:
        from handlers.words import generate_audio_for_text, store_audio

        conn = get_db_connection()
        cur = conn.cursor()

        # Try to get existing audio from cache
        cur.execute("""
            SELECT audio_data
            FROM audio
            WHERE text_content = %s AND language = %s
        """, (text, language))

        result = cur.fetchone()

        if result:
            # Found cached audio
            cur.close()
            conn.close()
            audio_base64 = base64.b64encode(result['audio_data']).decode('utf-8')
            logger.info(f"Retrieved cached audio for text: '{text[:50]}...'")
            return f"data:audio/mpeg;base64,{audio_base64}"

        # Audio doesn't exist, generate it
        cur.close()
        conn.close()

        logger.info(f"Generating audio for text: '{text[:50]}...' in {language}")
        audio_data = generate_audio_for_text(text)

        # Store in database for future use
        store_audio(text, language, audio_data)

        # Return as base64 data URI
        audio_base64 = base64.b64encode(audio_data).decode('utf-8')
        return f"data:audio/mpeg;base64,{audio_base64}"

    except Exception as e:
        logger.error(f"Error getting/generating audio: {e}", exc_info=True)
        # Return empty string on error
        return ""


def fetch_and_cache_definition(word: str, learning_lang: str, native_lang: str) -> Optional[Dict]:
    """
    Fetch definition for a word using LLM and cache it in the database.
    """
    try:
        from services.definition_service import generate_definition_with_llm

        definition_data = generate_definition_with_llm(
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
    Get multiple review words with enhanced questions in a single request.

    GET /v3/next-review-words-batch?user_id=xxx&count=10&exclude_words=word1,word2

    Priority Order (fetched and returned in this order, sorted alphabetically within each category):
    1. new - New words from today's schedule (daily_schedule_entries.new_words)
    2. test_practice - Test practice words from today's schedule (daily_schedule_entries.test_practice_words)
    3. non_test_practice - Non-test practice words from today's schedule (daily_schedule_entries.non_test_practice_words)
    4. not_due_yet - Saved words with reviews, last review > 24h ago, not due yet

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

        # Get today's date in user's timezone
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            words_fetched = set()

            # Get words already reviewed today (to exclude from schedule)
            # We check reviews table for any word reviewed today in user's timezone
            cur.execute("""
                SELECT DISTINCT sw.word
                FROM reviews r
                JOIN saved_words sw ON r.word_id = sw.id
                WHERE r.user_id = %s
                  AND DATE(r.reviewed_at AT TIME ZONE 'UTC' AT TIME ZONE %s) = %s
            """, (user_id, user_tz, today))
            reviewed_today = {row['word'] for row in cur.fetchall()}
            logger.info(f"Words already reviewed today: {len(reviewed_today)}")

            # Add reviewed words to exclusion set
            exclude_words = exclude_words | reviewed_today

            # Calculate today's schedule on-the-fly
            today_entry = None
            try:
                # Get user preferences to determine test type and target_end_date
                cur.execute("""
                    SELECT
                        toefl_beginner_enabled, toefl_intermediate_enabled, toefl_advanced_enabled,
                        ielts_beginner_enabled, ielts_intermediate_enabled, ielts_advanced_enabled,
                        tianz_enabled, target_end_date
                    FROM user_preferences
                    WHERE user_id = %s
                """, (user_id,))
                prefs = cur.fetchone()

                if prefs:
                    from handlers.test_vocabulary import get_active_test_type
                    test_type = get_active_test_type(prefs)
                    target_end_date = prefs.get('target_end_date')

                    # If user has test prep enabled, calculate schedule
                    if test_type and target_end_date and target_end_date > today:
                        from services.schedule_service import fetch_schedule_data, calc_schedule, get_schedule

                        # Fetch all data needed for calculation
                        schedule_data = fetch_schedule_data(user_id, test_type, user_tz, today)

                        # Calculate the full schedule
                        schedule_result = calc_schedule(
                            today=today,
                            target_end_date=target_end_date,
                            all_test_words=schedule_data['all_test_words'],
                            saved_words_with_reviews=schedule_data['saved_words_with_reviews'],
                            words_saved_today=schedule_data['words_saved_today'],
                            words_reviewed_today=schedule_data['words_reviewed_today'],
                            get_schedule_fn=get_schedule,
                            all_saved_words=schedule_data['all_saved_words']
                        )

                        # Extract today's entry from calculated schedule
                        today_key = today.isoformat()
                        today_entry = schedule_result['daily_schedules'].get(today_key)
            except Exception as e:
                logger.warning(f"Could not calculate schedule: {e}")
                today_entry = None

            # ============================================================
            # PRIORITY 1: New words from today's schedule
            # ============================================================
            new_words_list = []
            if today_entry and today_entry.get('new_words'):
                all_excluded = exclude_words | words_fetched
                available = [w for w in today_entry['new_words'] if w not in all_excluded]
                # Sort alphabetically
                available = sorted(available, key=lambda w: w.lower())

                for word in available[:count - len(words_fetched)]:
                    # DO NOT insert into saved_words here - that happens in submit_review
                    # saved_word_id is null for new words
                    new_words_list.append({
                        'saved_word_id': None,
                        'word': word,
                        'learning_language': learning_lang,
                        'native_language': native_lang,
                        'source_type': 'new'
                    })
                    words_fetched.add(word)

            # ============================================================
            # PRIORITY 2: Test practice words from today's schedule
            # ============================================================
            test_practice_list = []
            if len(words_fetched) < count and today_entry and today_entry.get('test_practice'):
                all_excluded = exclude_words | words_fetched
                # Extract word strings from practice dicts
                available = [w.get('word') for w in today_entry['test_practice'] if w.get('word') not in all_excluded]
                # Sort alphabetically
                available = sorted(available, key=lambda w: w.lower())

                for word in available[:count - len(words_fetched)]:
                    # Get saved_word_id from saved_words (should exist for practice words)
                    cur.execute("""
                        SELECT id FROM saved_words
                        WHERE user_id = %s AND word = %s AND learning_language = %s AND native_language = %s
                    """, (user_id, word, learning_lang, native_lang))
                    word_info = cur.fetchone()

                    # saved_word_id may be null if word was somehow not saved yet
                    test_practice_list.append({
                        'saved_word_id': word_info['id'] if word_info else None,
                        'word': word,
                        'learning_language': learning_lang,
                        'native_language': native_lang,
                        'source_type': 'test_practice'
                    })
                    words_fetched.add(word)

            # ============================================================
            # PRIORITY 3: Non-test practice words from today's schedule
            # ============================================================
            non_test_practice_list = []
            if len(words_fetched) < count and today_entry and today_entry.get('non_test_practice'):
                all_excluded = exclude_words | words_fetched
                # Extract word strings from practice dicts
                available = [w.get('word') for w in today_entry['non_test_practice'] if w.get('word') not in all_excluded]
                # Sort alphabetically
                available = sorted(available, key=lambda w: w.lower())

                for word in available[:count - len(words_fetched)]:
                    # Get saved_word_id from saved_words (should exist for practice words)
                    cur.execute("""
                        SELECT id FROM saved_words
                        WHERE user_id = %s AND word = %s AND learning_language = %s AND native_language = %s
                    """, (user_id, word, learning_lang, native_lang))
                    word_info = cur.fetchone()

                    # saved_word_id may be null if word was somehow not saved yet
                    non_test_practice_list.append({
                        'saved_word_id': word_info['id'] if word_info else None,
                        'word': word,
                        'learning_language': learning_lang,
                        'native_language': native_lang,
                        'source_type': 'non_test_practice'
                    })
                    words_fetched.add(word)

            # ============================================================
            # PRIORITY 4: Not-due-yet words (reviewed before, last review > 24h ago, not due)
            # ============================================================
            not_due_yet_list = []
            if len(words_fetched) < count:
                all_excluded = exclude_words | words_fetched
                exclude_clause = ""
                exclude_params = []
                if all_excluded:
                    placeholders = ','.join(['%s'] * len(all_excluded))
                    exclude_clause = f"AND sw.word NOT IN ({placeholders})"
                    exclude_params = list(all_excluded)

                not_due_yet_query = f"""
                    SELECT
                        sw.id as saved_word_id,
                        sw.word,
                        sw.learning_language,
                        sw.native_language
                    FROM saved_words sw
                    INNER JOIN (
                        SELECT
                            word_id,
                            next_review_date,
                            reviewed_at as last_reviewed_at,
                            ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                        FROM reviews
                    ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
                    WHERE sw.user_id = %s
                      AND (sw.is_known IS NULL OR sw.is_known = FALSE)
                      AND latest_review.last_reviewed_at <= NOW() - INTERVAL '24 hours'
                      AND COALESCE(latest_review.next_review_date, NOW() + INTERVAL '1 day') > NOW()
                      {exclude_clause}
                    ORDER BY sw.word ASC
                    LIMIT %s
                """

                cur.execute(not_due_yet_query, (user_id, *exclude_params, count - len(words_fetched)))
                rows = cur.fetchall()

                for row in rows:
                    not_due_yet_list.append({
                        'saved_word_id': row['saved_word_id'],
                        'word': row['word'],
                        'learning_language': row['learning_language'],
                        'native_language': row['native_language'],
                        'source_type': 'not_due_yet'
                    })
                    words_fetched.add(row['word'])

            # ============================================================
            # Combine all words in priority order (already sorted alphabetically within each category)
            # ============================================================
            all_word_rows = new_words_list + test_practice_list + non_test_practice_list + not_due_yet_list

            # Calculate total available
            total_available = len(all_word_rows)  # Start with words we're returning

            # Count remaining schedule words (excluding words we already fetched)
            if today_entry:
                all_excluded = exclude_words | words_fetched
                # Count remaining new words
                remaining_new = [w for w in (today_entry.get('new_words') or []) if w not in all_excluded]
                # Count remaining test practice
                remaining_test = [w for w in (today_entry.get('test_practice') or []) if w.get('word') not in all_excluded]
                # Count remaining non-test practice
                remaining_non_test = [w for w in (today_entry.get('non_test_practice') or []) if w.get('word') not in all_excluded]

                total_available += len(remaining_new) + len(remaining_test) + len(remaining_non_test)

            # Count not-due-yet words (excluding ones we already fetched)
            all_excluded = exclude_words | words_fetched
            exclude_clause = ""
            exclude_params = []
            if all_excluded:
                placeholders = ','.join(['%s'] * len(all_excluded))
                exclude_clause = f"AND sw.word NOT IN ({placeholders})"
                exclude_params = list(all_excluded)

            cur.execute(f"""
                SELECT COUNT(*) as cnt
                FROM saved_words sw
                INNER JOIN (
                    SELECT
                        word_id,
                        next_review_date,
                        reviewed_at as last_reviewed_at,
                        ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                    FROM reviews
                ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
                WHERE sw.user_id = %s
                  AND (sw.is_known IS NULL OR sw.is_known = FALSE)
                  AND latest_review.last_reviewed_at <= NOW() - INTERVAL '24 hours'
                  AND COALESCE(latest_review.next_review_date, NOW() + INTERVAL '1 day') > NOW()
                  {exclude_clause}
            """, (user_id, *exclude_params))
            not_due_yet_remaining = cur.fetchone()
            if not_due_yet_remaining:
                total_available += not_due_yet_remaining['cnt']

            # Generate questions for each word with position
            questions = []
            for position, row in enumerate(all_word_rows):
                word = row['word']
                saved_word_id = row['saved_word_id']  # May be None for new words
                word_learning_lang = row.get('learning_language', learning_lang)
                word_native_lang = row.get('native_language', native_lang)
                source_type = row.get('source_type', 'unknown')

                # Fetch definition
                cur.execute("""
                    SELECT definition_data
                    FROM definitions
                    WHERE word = %s
                      AND learning_language = %s
                      AND native_language = %s
                """, (word, word_learning_lang, word_native_lang))

                definition_result = cur.fetchone()
                definition_data = definition_result['definition_data'] if definition_result else None

                # Fetch definition if missing
                question_type = None
                if definition_data is None:
                    logger.info(f"Word '{word}' has no definition, fetching...")
                    definition_data = fetch_and_cache_definition(word, word_learning_lang, word_native_lang)

                    if definition_data is None:
                        logger.warning(f"Could not fetch definition for '{word}', skipping")
                        continue  # Skip words without definitions

                # Generate question
                question = get_or_generate_question(
                    word=word,
                    definition=definition_data,
                    learning_lang=word_learning_lang,
                    native_lang=word_native_lang,
                    question_type=question_type
                )

                # For pronounce_sentence questions, generate audio for the sentence
                if question.get('question_type') == 'pronounce_sentence' and question.get('sentence'):
                    audio_url = get_or_generate_audio_base64(question['sentence'], word_learning_lang)
                    question['audio_url'] = audio_url
                    # Add evaluation threshold if not already present
                    if 'evaluation_threshold' not in question:
                        question['evaluation_threshold'] = 0.7

                questions.append({
                    "word": word,
                    "saved_word_id": saved_word_id,  # null for new words, integer for saved words
                    "source": source_type,
                    "position": position,
                    "learning_language": word_learning_lang,
                    "native_language": word_native_lang,
                    "question": question,
                    "definition": definition_data
                })

            return jsonify({
                "questions": questions,
                "total_available": total_available,
                "has_more": total_available > len(questions)
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting batch review words: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500
