"""
Schedule API handlers for test preparation study plans.

Provides REST API endpoints for:
- Creating study schedules
- Getting today's schedule
- Reviewing new words
- Managing user timezone settings
"""

from flask import jsonify, request
from datetime import datetime, date
import logging
import json
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.schedule_service import initiate_schedule, refresh_schedule, get_user_timezone, get_today_in_timezone, get_words_reviewed_on_date
from utils.database import get_db_connection
from services.spaced_repetition_service import get_next_review_date_new
from handlers.test_vocabulary import TEST_TYPE_MAPPING

logger = logging.getLogger(__name__)


def filter_known_words_from_practice(practice_words, user_id, conn):
    """
    Filter out known words from a practice words list.

    Args:
        practice_words: List of practice word dicts with word_id
        user_id: User UUID
        conn: Database connection

    Returns:
        Filtered list of practice words (excluding known words)
    """
    if not practice_words:
        return []

    # Get word IDs from practice words
    word_ids = [pw.get('word_id') for pw in practice_words if pw.get('word_id')]
    if not word_ids:
        return practice_words

    # Query to find which words are known
    cur = conn.cursor()
    cur.execute("""
        SELECT id FROM saved_words
        WHERE user_id = %s AND id = ANY(%s) AND is_known = TRUE
    """, (user_id, word_ids))
    known_ids = {row['id'] for row in cur.fetchall()}
    cur.close()

    # Filter out known words
    return [pw for pw in practice_words if pw.get('word_id') not in known_ids]


def get_today_schedule():
    """
    GET /v3/schedule/today?user_id=XXX
    Get today's schedule for user in their timezone.

    NOW CALCULATES SCHEDULE ON-THE-FLY from user preferences instead of reading from database.

    Response:
        {
            "date": "2025-11-10",
            "user_has_schedule": true,  // Whether user has test prep enabled with target_end_date
            "has_schedule": true,  // Whether today has tasks scheduled
            "new_words": ["abandon", "abbreviate", ...],
            "test_practice_words": [
                {
                    "word": "apple",
                    "word_id": 123,
                    "expected_retention": 0.35,
                    "review_number": 3
                }
            ],
            "non_test_practice_words": [...],
            "summary": {
                "total_new": 10,
                "total_test_practice": 5,
                "total_non_test_practice": 2,
                "total_words": 17
            }
        }

    NOTE: Two separate flags for clarity:
    - user_has_schedule: True if user has test prep enabled with target_end_date set
    - has_schedule: True if today specifically has tasks (used for displaying today's content)
    """
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        # Get today in user's timezone
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # Get user preferences including test settings and target_end_date
            cur.execute("""
                SELECT
                    toefl_enabled, ielts_enabled, tianz_enabled,
                    toefl_beginner_enabled, toefl_intermediate_enabled, toefl_advanced_enabled,
                    ielts_beginner_enabled, ielts_intermediate_enabled, ielts_advanced_enabled,
                    user_name, target_end_date
                FROM user_preferences
                WHERE user_id = %s
            """, (user_id,))

            prefs = cur.fetchone()

            if not prefs:
                return jsonify({
                    "date": today.isoformat(),
                    "user_has_schedule": False,
                    "has_schedule": False,
                    "test_type": None,
                    "user_name": None,
                    "message": "User preferences not found."
                }), 200

            # Check if any test prep is enabled
            test_prep_enabled = (
                prefs.get('toefl_enabled') or prefs.get('ielts_enabled') or prefs.get('tianz_enabled') or
                prefs.get('toefl_beginner_enabled') or prefs.get('toefl_intermediate_enabled') or prefs.get('toefl_advanced_enabled') or
                prefs.get('ielts_beginner_enabled') or prefs.get('ielts_intermediate_enabled') or prefs.get('ielts_advanced_enabled')
            )

            target_end_date = prefs.get('target_end_date')
            user_name = prefs.get('user_name')

            # Determine test_type from enabled flags
            from handlers.test_vocabulary import get_active_test_type
            test_type = get_active_test_type(prefs)

            # User has schedule if test prep is enabled AND target_end_date is set
            user_has_schedule = test_prep_enabled and target_end_date is not None

            if not user_has_schedule:
                return jsonify({
                    "date": today.isoformat(),
                    "user_has_schedule": False,
                    "has_schedule": False,
                    "test_type": test_type,
                    "user_name": user_name,
                    "message": "No schedule configured. Set target_end_date in preferences."
                }), 200

            # Validate target_end_date is in the future
            if target_end_date <= today:
                return jsonify({
                    "date": today.isoformat(),
                    "user_has_schedule": False,
                    "has_schedule": False,
                    "test_type": test_type,
                    "user_name": user_name,
                    "message": "Target end date has passed. Please update your preferences."
                }), 200

            # Calculate schedule on-the-fly
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

            if not today_entry:
                return jsonify({
                    "date": today.isoformat(),
                    "user_has_schedule": True,
                    "has_schedule": False,
                    "test_type": test_type,
                    "user_name": user_name,
                    "new_words": [],
                    "test_practice_words": [],
                    "non_test_practice_words": [],
                    "summary": {
                        "total_new": 0,
                        "total_test_practice": 0,
                        "total_non_test_practice": 0,
                        "total_words": 0
                    },
                    "message": "No tasks scheduled for today."
                }), 200

            # Get words already reviewed today (to mark as completed)
            reviewed_today = get_words_reviewed_on_date(user_id, today, user_tz)

            new_words = today_entry['new_words'] or []
            test_practice = today_entry['test_practice'] or []
            non_test_practice = today_entry['non_test_practice'] or []

            # Filter out known words from practice lists
            test_practice = filter_known_words_from_practice(test_practice, user_id, conn)
            non_test_practice = filter_known_words_from_practice(non_test_practice, user_id, conn)

            # Separate completed and remaining words
            new_words_completed = [w for w in new_words if w in reviewed_today]
            new_words_remaining = [w for w in new_words if w not in reviewed_today]

            # For practice words (which are dicts with 'word' key)
            test_practice_completed = [w for w in test_practice if w.get('word') in reviewed_today]
            test_practice_remaining = [w for w in test_practice if w.get('word') not in reviewed_today]

            non_test_practice_completed = [w for w in non_test_practice if w.get('word') in reviewed_today]
            non_test_practice_remaining = [w for w in non_test_practice if w.get('word') not in reviewed_today]

            total_remaining = len(new_words_remaining) + len(test_practice_remaining) + len(non_test_practice_remaining)
            total_completed = len(new_words_completed) + len(test_practice_completed) + len(non_test_practice_completed)
            total_words = total_remaining + total_completed
            has_tasks_today = total_words > 0

            return jsonify({
                "date": today.isoformat(),
                "user_has_schedule": True,  # User has created a schedule
                "has_schedule": has_tasks_today,  # Whether today has tasks
                "test_type": test_type,
                "user_name": user_name,
                "new_words": new_words_remaining,
                "new_words_completed": new_words_completed,
                "test_practice_words": test_practice_remaining,
                "test_practice_words_completed": test_practice_completed,
                "non_test_practice_words": non_test_practice_remaining,
                "non_test_practice_words_completed": non_test_practice_completed,
                "summary": {
                    "total_new": len(new_words),
                    "total_new_remaining": len(new_words_remaining),
                    "total_new_completed": len(new_words_completed),
                    "total_test_practice": len(test_practice),
                    "total_test_practice_remaining": len(test_practice_remaining),
                    "total_test_practice_completed": len(test_practice_completed),
                    "total_non_test_practice": len(non_test_practice),
                    "total_non_test_practice_remaining": len(non_test_practice_remaining),
                    "total_non_test_practice_completed": len(non_test_practice_completed),
                    "total_words": total_words,
                    "total_remaining": total_remaining,
                    "total_completed": total_completed
                },
                "message": "All tasks completed for today!" if total_remaining == 0 and total_words > 0 else None
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting today's schedule: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500


def review_new_word():
    """
    POST /v3/review_new_word
    User reviews a new word from schedule for the first time.
    This adds the word to saved_words AND records the first review.

    Request body:
        {
            "user_id": "uuid",
            "word": "abandon",
            "response": true/false,
            "learning_language": "en",  // optional, default "en"
            "native_language": "zh"     // optional, default "zh"
        }

    Response:
        {
            "success": true,
            "word_id": 123,
            "next_review_date": "2025-11-15T10:00:00"
        }
    """
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        word = data.get('word')
        response = data.get('response')
        learning_language = data.get('learning_language', 'en')
        native_language = data.get('native_language', 'zh')

        # Validation
        if not all([user_id, word]) or response is None:
            return jsonify({"error": "user_id, word, and response are required"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # Add word to saved_words (or get existing)
            cur.execute("""
                INSERT INTO saved_words (user_id, word, learning_language, native_language)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (user_id, word, learning_language, native_language)
                DO UPDATE SET created_at = saved_words.created_at
                RETURNING id, created_at
            """, (user_id, word, learning_language, native_language))

            word_info = cur.fetchone()
            word_id = word_info['id']
            created_at = word_info['created_at']

            # Record the first review
            cur.execute("""
                INSERT INTO reviews (user_id, word_id, response, reviewed_at)
                VALUES (%s, %s, %s, CURRENT_TIMESTAMP)
                RETURNING reviewed_at
            """, (user_id, word_id, response))

            reviewed_at = cur.fetchone()['reviewed_at']

            # Calculate next review date
            next_review_date = get_next_review_date_new(
                [{'reviewed_at': reviewed_at, 'response': response}],
                created_at
            )

            conn.commit()

            return jsonify({
                "success": True,
                "word_id": word_id,
                "next_review_date": next_review_date.isoformat()
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error reviewing new word: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500


def get_schedule_range():
    """
    GET /v3/schedule/range?user_id=XXX&days=7&only_new_words=true
    Get schedule for multiple days (default 7 days from today).

    NOW CALCULATES SCHEDULE ON-THE-FLY from user preferences instead of reading from database.

    Query Parameters:
        - user_id: UUID of the user
        - days: Number of days to fetch (default 7, max 30)
        - only_new_words: If true, only return days with new words (default false)

    Response:
        {
            "schedules": [
                {
                    "date": "2025-11-10",
                    "has_schedule": true,
                    "new_words": ["abandon", "abbreviate"],
                    "test_practice_words": [{...}],
                    "non_test_practice_words": [{...}],
                    "summary": {...}
                },
                ...
            ]
        }
    """
    try:
        user_id = request.args.get('user_id')
        days = int(request.args.get('days', 7))  # Default 7 days
        only_new_words = request.args.get('only_new_words', 'false').lower() == 'true'

        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        if days < 1 or days > 60:
            return jsonify({"error": "days must be between 1 and 60"}), 400

        # Get today in user's timezone
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # Get user preferences including test settings and target_end_date
            cur.execute("""
                SELECT
                    toefl_enabled, ielts_enabled, tianz_enabled,
                    toefl_beginner_enabled, toefl_intermediate_enabled, toefl_advanced_enabled,
                    ielts_beginner_enabled, ielts_intermediate_enabled, ielts_advanced_enabled,
                    user_name, target_end_date
                FROM user_preferences
                WHERE user_id = %s
            """, (user_id,))

            prefs = cur.fetchone()

            if not prefs:
                return jsonify({
                    "schedules": [],
                    "test_type": None,
                    "user_name": None
                }), 200

            # Check if any test prep is enabled
            test_prep_enabled = (
                prefs.get('toefl_enabled') or prefs.get('ielts_enabled') or prefs.get('tianz_enabled') or
                prefs.get('toefl_beginner_enabled') or prefs.get('toefl_intermediate_enabled') or prefs.get('toefl_advanced_enabled') or
                prefs.get('ielts_beginner_enabled') or prefs.get('ielts_intermediate_enabled') or prefs.get('ielts_advanced_enabled')
            )

            target_end_date = prefs.get('target_end_date')
            user_name = prefs.get('user_name')

            # Determine test_type from enabled flags
            from handlers.test_vocabulary import get_active_test_type
            test_type = get_active_test_type(prefs)

            logger.info(f"Schedule range check: user_id={user_id}, test_prep_enabled={test_prep_enabled}, target_end_date={target_end_date}, test_type={test_type}")

            # If test prep is disabled or no target_end_date, return empty schedules
            if not test_prep_enabled or not target_end_date:
                return jsonify({
                    "schedules": [],
                    "test_type": test_type,
                    "user_name": user_name
                }), 200

            # Validate target_end_date is in the future
            if target_end_date <= today:
                return jsonify({
                    "schedules": [],
                    "test_type": test_type,
                    "user_name": user_name
                }), 200

            # Calculate schedule on-the-fly
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

            # Get words reviewed today (for marking completed on today's entry)
            reviewed_today = get_words_reviewed_on_date(user_id, today, user_tz)

            # Process calculated schedule for requested date range
            schedules = []
            from datetime import timedelta

            for day_offset in range(days):
                current_date = today + timedelta(days=day_offset)
                current_date_key = current_date.isoformat()
                is_today = (current_date == today)

                # Get entry for this date from calculated schedule
                day_entry = schedule_result['daily_schedules'].get(current_date_key)

                if not day_entry:
                    # No schedule for this date
                    continue

                new_words = day_entry['new_words'] or []
                test_practice = day_entry['test_practice'] or []
                non_test_practice = day_entry['non_test_practice'] or []

                # Filter out known words from practice lists
                test_practice = filter_known_words_from_practice(test_practice, user_id, conn)
                non_test_practice = filter_known_words_from_practice(non_test_practice, user_id, conn)

                # For today, separate completed and remaining words
                if is_today:
                    new_words_completed = [w for w in new_words if w in reviewed_today]
                    new_words_remaining = [w for w in new_words if w not in reviewed_today]

                    test_practice_completed = [w for w in test_practice if w.get('word') in reviewed_today]
                    test_practice_remaining = [w for w in test_practice if w.get('word') not in reviewed_today]

                    non_test_practice_completed = [w for w in non_test_practice if w.get('word') in reviewed_today]
                    non_test_practice_remaining = [w for w in non_test_practice if w.get('word') not in reviewed_today]

                    total_remaining = len(new_words_remaining) + len(test_practice_remaining) + len(non_test_practice_remaining)
                    total_completed = len(new_words_completed) + len(test_practice_completed) + len(non_test_practice_completed)
                else:
                    # Future days - no completed words
                    new_words_remaining = new_words
                    new_words_completed = []
                    test_practice_remaining = test_practice
                    test_practice_completed = []
                    non_test_practice_remaining = non_test_practice
                    non_test_practice_completed = []
                    total_remaining = len(new_words) + len(test_practice) + len(non_test_practice)
                    total_completed = 0

                total_words = len(new_words) + len(test_practice) + len(non_test_practice)

                # Build schedule entry
                schedule_entry = {
                    "date": current_date.isoformat(),
                    "has_schedule": True,
                    "test_type": test_type,
                    "new_words": new_words_remaining,
                    "new_words_completed": new_words_completed,
                    "test_practice_words": test_practice_remaining,
                    "test_practice_words_completed": test_practice_completed,
                    "non_test_practice_words": non_test_practice_remaining,
                    "non_test_practice_words_completed": non_test_practice_completed,
                    "summary": {
                        "total_new": len(new_words),
                        "total_new_remaining": len(new_words_remaining),
                        "total_new_completed": len(new_words_completed),
                        "total_test_practice": len(test_practice),
                        "total_test_practice_remaining": len(test_practice_remaining),
                        "total_test_practice_completed": len(test_practice_completed),
                        "total_non_test_practice": len(non_test_practice),
                        "total_non_test_practice_remaining": len(non_test_practice_remaining),
                        "total_non_test_practice_completed": len(non_test_practice_completed),
                        "total_words": total_words,
                        "total_remaining": total_remaining,
                        "total_completed": total_completed
                    }
                }

                # Filter based on only_new_words parameter
                if only_new_words:
                    # Only include days with new words (remaining or completed)
                    if len(new_words) > 0:
                        schedules.append(schedule_entry)
                else:
                    # Include all days
                    schedules.append(schedule_entry)

            return jsonify({
                "schedules": schedules,
                "test_type": test_type,
                "user_name": user_name
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting schedule range: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500


def update_timezone():
    """
    DEPRECATED: Use POST /v3/users/{user_id}/preferences with timezone parameter instead.
    This endpoint will be removed in a future version.

    PUT /v3/user/timezone
    Update user's timezone setting.

    Request body:
        {
            "user_id": "uuid",
            "timezone": "America/New_York"  // IANA timezone string
        }

    Response:
        {
            "success": true,
            "timezone": "America/New_York"
        }
    """
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        timezone = data.get('timezone')

        if not all([user_id, timezone]):
            return jsonify({"error": "user_id and timezone are required"}), 400

        # Validate timezone
        import pytz
        try:
            pytz.timezone(timezone)
        except pytz.exceptions.UnknownTimeZoneError:
            return jsonify({"error": "Invalid timezone. Use IANA timezone format (e.g., 'America/New_York')"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            cur.execute("""
                UPDATE user_preferences
                SET timezone = %s, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = %s
                RETURNING timezone
            """, (timezone, user_id))

            result = cur.fetchone()

            if not result:
                return jsonify({"error": "User not found"}), 404

            conn.commit()

            return jsonify({
                "success": True,
                "timezone": result['timezone']
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error updating timezone: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500


def get_next_review_word_with_scheduled_new_words():
    """
    GET /v3/next-review-word-with-scheduled-new-words?user_id=XXX

    Get next word for review, prioritizing scheduled new words and overdue words.

    Priority Order:
    1. Scheduled new words for today (is_new_word=true)
    2. Overdue words (next_review_date <= NOW, not reviewed in past 24h)
    3. Nothing (empty response = "today's tasks complete")

    Note: Does NOT return words that are not due yet, even if they haven't been
    reviewed in 24 hours. This ensures users see "today's tasks complete" when
    they finish all overdue and new words.

    Response:
        {
            "user_id": "uuid",
            "saved_words": [{
                "id": 123,
                "word": "abandon",
                "learning_language": "en",
                "native_language": "zh",
                "is_new_word": true  // true if from schedule, false if overdue
            }],
            "count": 1,
            "new_words_remaining_today": 5  // count of remaining new words from schedule
        }
    """
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        # Get user preferences for language settings
        from services.user_service import get_user_preferences
        learning_lang, native_lang, _, _ = get_user_preferences(user_id)

        # Get today's date in user's timezone
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # Check for scheduled new words today
            cur.execute("""
                SELECT dse.id, dse.new_words, dse.schedule_id
                FROM daily_schedule_entries dse
                JOIN study_schedules ss ON dse.schedule_id = ss.id
                WHERE ss.user_id = %s AND dse.scheduled_date = %s
            """, (user_id, today))

            schedule_entry = cur.fetchone()

            # If there are scheduled new words, return one
            if schedule_entry and schedule_entry['new_words'] and len(schedule_entry['new_words']) > 0:
                new_words = schedule_entry['new_words']
                word_to_learn = new_words[0]  # Get first new word

                # Add word to saved_words (or get existing)
                cur.execute("""
                    INSERT INTO saved_words (user_id, word, learning_language, native_language)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT (user_id, word, learning_language, native_language)
                    DO UPDATE SET created_at = saved_words.created_at
                    RETURNING id
                """, (user_id, word_to_learn, learning_lang, native_lang))

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

                logger.info(f"Returning scheduled new word '{word_to_learn}' for user {user_id}")

                return jsonify({
                    "user_id": user_id,
                    "saved_words": [{
                        "id": word_id,
                        "word": word_to_learn,
                        "learning_language": learning_lang,
                        "native_language": native_lang,
                        "is_new_word": True
                    }],
                    "count": 1,
                    "new_words_remaining_today": len(updated_new_words)
                })

            # No scheduled new words, fall back to OVERDUE words only
            # Only return words that are actually DUE (next_review_date <= NOW)
            # This ensures we complete "today's tasks" when all due words are done
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

            word = cur.fetchone()

            if not word:
                return jsonify({
                    "user_id": user_id,
                    "saved_words": [],
                    "count": 0,
                    "new_words_remaining_today": 0
                })

            return jsonify({
                "user_id": user_id,
                "saved_words": [{
                    "id": word['id'],
                    "word": word['word'],
                    "learning_language": word['learning_language'],
                    "native_language": word['native_language'],
                    "is_new_word": False
                }],
                "count": 1,
                "new_words_remaining_today": 0
            })

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting next review word with scheduled new words: {str(e)}", exc_info=True)
        return jsonify({"error": f"Failed to get next review word: {str(e)}"}), 500


def get_test_progress(): # chen vetted
    """
    GET /v3/schedule/test-progress?user_id=XXX
    Get user's test preparation progress.

    Response:
        {
            "has_schedule": true,
            "test_type": "TOEFL" | "IELTS" | "TIANZ" | "BOTH",
            "total_words": 3500,
            "saved_words": 150,
            "progress": 0.043  // saved_words / total_words
        }
    """
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # Check if user has test prep enabled (V3 format with 7 levels)
            cur.execute("""
                SELECT
                    toefl_beginner_enabled, toefl_intermediate_enabled, toefl_advanced_enabled,
                    ielts_beginner_enabled, ielts_intermediate_enabled, ielts_advanced_enabled,
                    tianz_enabled
                FROM user_preferences
                WHERE user_id = %s
            """, (user_id,))

            prefs = cur.fetchone()

            if not prefs:
                return jsonify({"error": "User not found"}), 404

            # Check which specific test level is enabled (should only be one)
            # Determine the enabled level and its corresponding vocab column
            enabled_level = None
            vocab_column = None
            test_type = None

            if prefs['toefl_beginner_enabled']:
                enabled_level = 'TOEFL_BEGINNER'
                vocab_column = 'is_toefl_beginner'
                test_type = 'TOEFL BEGINNER'
            elif prefs['toefl_intermediate_enabled']:
                enabled_level = 'TOEFL_INTERMEDIATE'
                vocab_column = 'is_toefl_intermediate'
                test_type = 'TOEFL INTERMEDIATE'
            elif prefs['toefl_advanced_enabled']:
                enabled_level = 'TOEFL_ADVANCED'
                vocab_column = 'is_toefl_advanced'
                test_type = 'TOEFL ADVANCED'
            elif prefs['ielts_beginner_enabled']:
                enabled_level = 'IELTS_BEGINNER'
                vocab_column = 'is_ielts_beginner'
                test_type = 'IELTS'
            elif prefs['ielts_intermediate_enabled']:
                enabled_level = 'IELTS_INTERMEDIATE'
                vocab_column = 'is_ielts_intermediate'
                test_type = 'IELTS INTERMEDIATE'
            elif prefs['ielts_advanced_enabled']:
                enabled_level = 'IELTS_ADVANCED'
                vocab_column = 'is_ielts_advanced'
                test_type = 'IELTS ADVANCED'
            elif prefs['tianz_enabled']:
                enabled_level = 'TIANZ'
                vocab_column = 'is_tianz'
                test_type = 'TIANZ'

            # If no test level is enabled, return empty progress
            if not enabled_level:
                return jsonify({
                    "has_schedule": False,
                    "test_type": None,
                    "total_words": 0,
                    "saved_words": 0,
                    "progress": 0.0,
                    "streak_days": 0
                }), 200

            # Get total words in enabled test level using the specific vocab column
            cur.execute(f"""
                SELECT COUNT(DISTINCT word) as total
                FROM test_vocabularies
                WHERE {vocab_column} = TRUE
            """)

            total_result = cur.fetchone()
            total_words = total_result['total'] if total_result else 0

            # Get count of saved words that are in the enabled test level
            cur.execute(f"""
                SELECT COUNT(DISTINCT sw.word) as saved
                FROM saved_words sw
                INNER JOIN test_vocabularies tv ON sw.word = tv.word AND sw.learning_language = tv.language
                WHERE sw.user_id = %s
                    AND tv.{vocab_column} = TRUE
            """, (user_id,))

            saved_result = cur.fetchone()
            saved_words = saved_result['saved'] if saved_result else 0

            # Calculate progress
            progress = saved_words / total_words if total_words > 0 else 0.0

            # Get streak days
            from handlers.streaks import calculate_streak_days
            streak_days = calculate_streak_days(user_id)

            return jsonify({
                "has_schedule": True,
                "test_type": test_type,
                "total_words": total_words,
                "saved_words": saved_words,
                "progress": round(progress, 4),
                "streak_days": streak_days
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting test progress: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500
