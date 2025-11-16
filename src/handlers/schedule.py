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
            "has_schedule": true,
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
            # Get today's schedule
            cur.execute("""
                SELECT dse.new_words, dse.test_practice_words, dse.non_test_practice_words
                FROM daily_schedule_entries dse
                JOIN study_schedules ss ON dse.schedule_id = ss.id
                WHERE ss.user_id = %s AND dse.scheduled_date = %s
            """, (user_id, today))

            result = cur.fetchone()

            if not result:
                return jsonify({
                    "date": today.isoformat(),
                    "has_schedule": False,
                    "message": "No schedule found for today. Create a schedule first."
                }), 200

            new_words = result['new_words']
            test_practice = result['test_practice_words']
            non_test_practice = result['non_test_practice_words']

            return jsonify({
                "date": today.isoformat(),
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
