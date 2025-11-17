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
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.schedule_service import initiate_schedule, refresh_schedule, get_user_timezone, get_today_in_timezone
from utils.database import get_db_connection
from handlers.admin import get_next_review_date_new

logger = logging.getLogger(__name__)


def create_schedule():
    """
    POST /v3/schedule/create
    Create a new study schedule for test preparation.

    Request body:
        {
            "user_id": "uuid",
            "test_type": "TOEFL|IELTS|BOTH",
            "target_end_date": "YYYY-MM-DD"
        }

    Response:
        {
            "success": true,
            "schedule": {
                "schedule_id": 123,
                "days_remaining": 60,
                "total_new_words": 3500,
                "daily_new_words": 59,
                "test_practice_words_count": 150,
                "non_test_practice_words_count": 50
            }
        }
    """
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        test_type = data.get('test_type')
        target_end_date = data.get('target_end_date')

        # Validation
        if not all([user_id, test_type, target_end_date]):
            return jsonify({"error": "user_id, test_type, and target_end_date are required"}), 400

        if test_type not in ['TOEFL', 'IELTS', 'BOTH']:
            return jsonify({"error": "test_type must be 'TOEFL', 'IELTS', or 'BOTH'"}), 400

        # Parse date
        try:
            target_date = date.fromisoformat(target_end_date)
        except ValueError:
            return jsonify({"error": "Invalid date format. Use YYYY-MM-DD"}), 400

        # Create schedule
        result = initiate_schedule(user_id, test_type, target_date)

        return jsonify({
            "success": True,
            "schedule": result
        }), 200

    except ValueError as e:
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.error(f"Error creating schedule: {e}")
        return jsonify({"error": "Internal server error"}), 500


def get_today_schedule():
    """
    GET /v3/schedule/today?user_id=XXX
    Get today's schedule for user in their timezone.

    Response:
        {
            "date": "2025-11-10",
            "user_has_schedule": true,  // Whether user has created any schedule (determines tab visibility)
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
    - user_has_schedule: True if user has ever created a schedule (used for UI tab visibility)
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
            # First check if user has any schedule created at all
            cur.execute("""
                SELECT id FROM study_schedules
                WHERE user_id = %s
                LIMIT 1
            """, (user_id,))

            user_has_schedule = cur.fetchone() is not None

            if not user_has_schedule:
                return jsonify({
                    "date": today.isoformat(),
                    "user_has_schedule": False,  # No schedule exists at all
                    "has_schedule": False,  # No schedule for today
                    "message": "No schedule found. Create a schedule first."
                }), 200

            # Get today's schedule entry
            cur.execute("""
                SELECT dse.new_words, dse.test_practice_words, dse.non_test_practice_words
                FROM daily_schedule_entries dse
                JOIN study_schedules ss ON dse.schedule_id = ss.id
                WHERE ss.user_id = %s AND dse.scheduled_date = %s
            """, (user_id, today))

            result = cur.fetchone()

            # User has a schedule, but no entry for today
            if not result:
                return jsonify({
                    "date": today.isoformat(),
                    "user_has_schedule": True,  # User has created a schedule
                    "has_schedule": False,  # But nothing scheduled for today
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

            new_words = result['new_words'] or []
            test_practice = result['test_practice_words'] or []
            non_test_practice = result['non_test_practice_words'] or []

            total_words = len(new_words) + len(test_practice) + len(non_test_practice)
            has_tasks_today = total_words > 0

            return jsonify({
                "date": today.isoformat(),
                "user_has_schedule": True,  # User has created a schedule
                "has_schedule": has_tasks_today,  # Whether today has tasks
                "new_words": new_words,
                "test_practice_words": test_practice,
                "non_test_practice_words": non_test_practice,
                "summary": {
                    "total_new": len(new_words),
                    "total_test_practice": len(test_practice),
                    "total_non_test_practice": len(non_test_practice),
                    "total_words": total_words
                },
                "message": "All tasks completed for today!" if not has_tasks_today else None
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting today's schedule: {e}")
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
        logger.error(f"Error reviewing new word: {e}")
        return jsonify({"error": "Internal server error"}), 500


def get_schedule_range():
    """
    GET /v3/schedule/range?user_id=XXX&days=7&only_new_words=true
    Get schedule for multiple days (default 7 days from today).

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

        if days < 1 or days > 30:
            return jsonify({"error": "days must be between 1 and 30"}), 400

        # Get today in user's timezone
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # Get schedule for the next N days
            cur.execute("""
                SELECT dse.scheduled_date, dse.new_words, dse.test_practice_words, dse.non_test_practice_words
                FROM daily_schedule_entries dse
                JOIN study_schedules ss ON dse.schedule_id = ss.id
                WHERE ss.user_id = %s
                  AND dse.scheduled_date >= %s
                  AND dse.scheduled_date < %s + INTERVAL '%s days'
                ORDER BY dse.scheduled_date ASC
            """, (user_id, today, today, days))

            results = cur.fetchall()

            schedules = []
            for row in results:
                new_words = row['new_words'] or []
                test_practice = row['test_practice_words'] or []
                non_test_practice = row['non_test_practice_words'] or []

                # Filter based on only_new_words parameter
                if only_new_words:
                    # Only include days with new words
                    if len(new_words) > 0:
                        schedules.append({
                            "date": row['scheduled_date'].isoformat(),
                            "has_schedule": True,
                            "new_words": new_words,
                            "test_practice_words": test_practice,
                            "non_test_practice_words": non_test_practice,
                            "summary": {
                                "total_new": len(new_words),
                                "total_test_practice": len(test_practice),
                                "total_non_test_practice": len(non_test_practice),
                                "total_words": len(new_words) + len(test_practice) + len(non_test_practice)
                            }
                        })
                else:
                    # Include all days (even with 0 words)
                    schedules.append({
                        "date": row['scheduled_date'].isoformat(),
                        "has_schedule": True,
                        "new_words": new_words,
                        "test_practice_words": test_practice,
                        "non_test_practice_words": non_test_practice,
                        "summary": {
                            "total_new": len(new_words),
                            "total_test_practice": len(test_practice),
                            "total_non_test_practice": len(non_test_practice),
                            "total_words": len(new_words) + len(test_practice) + len(non_test_practice)
                        }
                    })

            return jsonify({
                "schedules": schedules
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting schedule range: {e}")
        return jsonify({"error": "Internal server error"}), 500


def update_timezone():
    """
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
        logger.error(f"Error updating timezone: {e}")
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
                    SET new_words = %s, updated_at = CURRENT_TIMESTAMP
                    WHERE id = %s
                """, (updated_new_words, schedule_entry['id']))

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
        logger.error(f"Error getting next review word with scheduled new words: {str(e)}")
        return jsonify({"error": f"Failed to get next review word: {str(e)}"}), 500
