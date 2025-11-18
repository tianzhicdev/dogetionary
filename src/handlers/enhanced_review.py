"""
Enhanced Review Handlers

Provides API endpoints for enhanced review system with diverse question types.
"""

from flask import jsonify, request
import logging
import json
from typing import Dict, Any, Optional
from utils.database import db_fetch_one, get_db_connection
from services.question_generation_service import get_or_generate_question
from services.user_service import get_user_preferences
from services.schedule_service import get_user_timezone, get_today_in_timezone

logger = logging.getLogger(__name__)


def fetch_and_cache_definition(word: str, learning_lang: str, native_lang: str) -> Optional[Dict]:
    """
    Fetch definition for a word using LLM and cache it in the database.
    Uses the shared V3 definition generation logic.
    Returns the definition_data or None if fetch fails.
    """
    try:
        # Import here to avoid circular imports
        from services.definition_service import generate_definition_with_llm

        # Generate definition using shared V3 utility (no build_prompt_fn needed)
        definition_data = generate_definition_with_llm(
            word=word,
            learning_lang=learning_lang,
            native_lang=native_lang
        )

        if definition_data:
            logger.info(f"Successfully fetched and cached V3 definition for '{word}' (score: {definition_data.get('valid_word_score', 'N/A')})")
            return definition_data
        else:
            logger.warning(f"Failed to fetch definition for '{word}'")
            return None

    except Exception as e:
        logger.error(f"Error fetching definition for '{word}': {e}", exc_info=True)
        return None


def get_next_review_enhanced():
    """
    Get next review word with an enhanced question (multiple choice, fill-blank, etc.)

    GET /v3/review_next_enhanced?user_id=xxx

    Priority Order (same as /v3/next-review-word-with-scheduled-new-words):
    1. Scheduled new words for today (is_new_word=true)
    2. Overdue words (next_review_date <= NOW, not reviewed in past 24h)
    3. Nothing (empty response = "today's tasks complete")

    Returns:
        JSON with word data, enhanced question, and full definition for display after answer
    """
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        # Get user preferences for language settings
        learning_lang, native_lang, _, _ = get_user_preferences(user_id)

        # Get today's date in user's timezone
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # PRIORITY 1: Check for scheduled new words today
            cur.execute("""
                SELECT dse.id, dse.new_words, dse.schedule_id
                FROM daily_schedule_entries dse
                JOIN study_schedules ss ON dse.schedule_id = ss.id
                WHERE ss.user_id = %s AND dse.scheduled_date = %s
            """, (user_id, today))

            schedule_entry = cur.fetchone()

            word_id = None
            word = None
            is_new_word = False
            new_words_remaining = 0

            # If there are scheduled new words, use the first one
            if schedule_entry and schedule_entry['new_words'] and len(schedule_entry['new_words']) > 0:
                new_words = schedule_entry['new_words']
                word = new_words[0]  # Get first new word
                is_new_word = True

                # Add word to saved_words (or get existing)
                cur.execute("""
                    INSERT INTO saved_words (user_id, word, learning_language, native_language)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (user_id, word, learning_language, native_language)
                    DO UPDATE SET created_at = saved_words.created_at
                    RETURNING id
                """, (user_id, word, learning_lang, native_lang))

                word_info = cur.fetchone()
                word_id = word_info['id']

                # Remove word from schedule's new_words list
                updated_new_words = new_words[1:]  # Remove first element
                cur.execute("""
                    UPDATE daily_schedule_entries
                    SET new_words = %s::jsonb, updated_at = CURRENT_TIMESTAMP
                    WHERE id = %s
                """, (json.dumps(updated_new_words), schedule_entry['id']))

                conn.commit()
                new_words_remaining = len(updated_new_words)

                logger.info(f"Returning scheduled new word '{word}' for user {user_id}")

            # PRIORITY 2: No scheduled new words, fall back to OVERDUE words only
            if not word:
                cur.execute("""
                    SELECT
                        sw.id,
                        sw.word,
                        sw.learning_language,
                        sw.native_language,
                        COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') as next_review_date
                    FROM saved_words sw
                    LEFT JOIN (
                        SELECT
                            word_id,
                            next_review_date,
                            reviewed_at as last_reviewed_at,
                            ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                        FROM reviews
                    ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
                    WHERE sw.user_id = %s
                    -- Exclude words reviewed in the past 24 hours
                    AND (latest_review.last_reviewed_at IS NULL OR latest_review.last_reviewed_at <= NOW() - INTERVAL '24 hours')
                    -- ONLY include words that are actually DUE (overdue or due now)
                    AND COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= NOW()
                    ORDER BY COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') ASC
                    LIMIT 1
                """, (user_id,))

                word_data = cur.fetchone()

                if not word_data:
                    # No words due for review
                    return jsonify({
                        "user_id": user_id,
                        "saved_words": [],
                        "count": 0,
                        "new_words_remaining_today": 0,
                        "message": "No words due for review"
                    }), 200

                word_id = word_data['id']
                word = word_data['word']
                learning_lang = word_data['learning_language']
                native_lang = word_data['native_language']

            # Fetch definition_data for the word
            cur.execute("""
                SELECT definition_data
                FROM definitions
                WHERE word = %s
                  AND learning_language = %s
                  AND native_language = %s
            """, (word, learning_lang, native_lang))

            definition_result = cur.fetchone()
            definition_data = definition_result['definition_data'] if definition_result else None

            # If word doesn't have definition_data, fetch it lazily
            question_type = None  # Random selection by default
            if definition_data is None:
                logger.info(f"Word '{word}' has no definition_data, fetching from LLM...")
                definition_data = fetch_and_cache_definition(word, learning_lang, native_lang)

                # If fetch still fails, fall back to recognition question
                if definition_data is None:
                    logger.warning(f"Failed to fetch definition for '{word}', forcing recognition question")
                    question_type = 'recognition'
                else:
                    logger.info(f"Successfully fetched definition for '{word}', will generate enhanced question")

            # Generate or retrieve enhanced question
            question = get_or_generate_question(
                word=word,
                definition=definition_data,
                learning_lang=learning_lang,
                native_lang=native_lang,
                question_type=question_type
            )

            # Return response
            return jsonify({
                "user_id": user_id,
                "word_id": word_id,
                "word": word,
                "learning_language": learning_lang,
                "native_language": native_lang,
                "is_new_word": is_new_word,
                "new_words_remaining_today": new_words_remaining,
                "question": question,
                "definition": definition_data  # For display after answer
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting enhanced review word: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500
