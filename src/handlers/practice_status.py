"""
Practice Status Handler

This module provides the practice status endpoint that returns:
- Number of new words from today's schedule
- Number of test practice words from today's schedule
- Number of non-test practice words from today's schedule
- Number of not-due-yet words (reviewed before, last review > 24h ago, not due)
- Current score
"""

from flask import jsonify, request
import sys
import os
import uuid
import logging
from datetime import datetime, timedelta

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utils.database import db_fetch_one, db_fetch_all
from services.schedule_service import get_user_timezone, get_today_in_timezone
from handlers.achievements import calculate_user_score

logger = logging.getLogger(__name__)


def get_practice_status():
    """
    GET /v3/practice-status?user_id=XXX
    Get practice status for a user including counts and score.

    Response:
        {
            "user_id": "uuid",
            "new_words_count": 5,
            "test_practice_count": 12,
            "non_test_practice_count": 8,
            "not_due_yet_count": 3,
            "score": 280,
            "has_practice": true
        }
    """
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        # Validate UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400

        # Get today's date in user's timezone for schedule lookup
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        # Get counts from today's schedule (calculated on-the-fly), excluding words already reviewed today
        new_words_count = 0
        test_practice_count = 0
        non_test_practice_count = 0

        try:
            # First, get words already reviewed today
            reviewed_today_row = db_fetch_all("""
                SELECT DISTINCT sw.word
                FROM reviews r
                JOIN saved_words sw ON r.word_id = sw.id
                WHERE r.user_id = %s
                  AND DATE(r.reviewed_at AT TIME ZONE 'UTC' AT TIME ZONE %s) = %s
            """, (user_id, user_tz, today))
            reviewed_today = {row['word'] for row in reviewed_today_row} if reviewed_today_row else set()

            # Calculate non_test_practice_count (always, regardless of test settings)
            # FIXED: Use user timezone instead of UTC for "due" check
            non_test_due_row = db_fetch_all("""
                SELECT sw.word
                FROM saved_words sw
                INNER JOIN (
                    SELECT
                        word_id,
                        next_review_date,
                        ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                    FROM reviews
                ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
                WHERE sw.user_id = %s
                  AND (sw.is_known IS NULL OR sw.is_known = FALSE)
                  AND COALESCE(latest_review.next_review_date, (NOW() AT TIME ZONE %s)::date) <= (NOW() AT TIME ZONE %s)::date
            """, (user_id, user_tz, user_tz))

            if non_test_due_row:
                non_test_due_words = {row['word'] for row in non_test_due_row}
                non_test_practice_count = len(non_test_due_words - reviewed_today)

            # Get user preferences to determine test type and target_end_date
            prefs = db_fetch_one("""
                SELECT
                    toefl_beginner_enabled, toefl_intermediate_enabled, toefl_advanced_enabled,
                    ielts_beginner_enabled, ielts_intermediate_enabled, ielts_advanced_enabled,
                    tianz_enabled, target_end_date
                FROM user_preferences
                WHERE user_id = %s
            """, (user_id,))

            if prefs:
                from handlers.test_vocabulary import get_active_test_type
                test_type = get_active_test_type(prefs)
                target_end_date = prefs.get('target_end_date')

                logger.info(f"Practice status check: user_id={user_id}, test_type={test_type}, target_end_date={target_end_date}, today={today}")

                # If user has test prep enabled, calculate schedule on-the-fly
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

                    if today_entry:
                        # Count words not yet reviewed today (only new_words and test_practice)
                        new_words = today_entry['new_words'] or []
                        test_words = [w.get('word') for w in (today_entry['test_practice'] or [])]

                        new_words_count = len([w for w in new_words if w not in reviewed_today])
                        test_practice_count = len([w for w in test_words if w not in reviewed_today])

        except Exception as e:
            # If schedule calculation fails, default to 0
            logger.debug(f"Could not calculate schedule: {e}")

        # Get not-due-yet count (reviewed before, last review > 24h ago, not due yet)
        # FIXED: Use user timezone for "not due yet" check
        not_due_yet_row = db_fetch_one("""
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
              AND COALESCE(latest_review.next_review_date, (NOW() AT TIME ZONE %s)::date + INTERVAL '1 day') > (NOW() AT TIME ZONE %s)::date
        """, (user_id, user_tz, user_tz))
        not_due_yet_count = not_due_yet_row['cnt'] if not_due_yet_row else 0

        # Get score using utility function
        score = calculate_user_score(user_id)

        # Determine if there's anything to practice
        # Note: not_due_yet_count is excluded because those words are not ready for practice yet
        has_practice = (new_words_count > 0 or test_practice_count > 0 or
                        non_test_practice_count > 0)

        return jsonify({
            "user_id": user_id,
            "new_words_count": max(0, new_words_count),
            "test_practice_count": test_practice_count,
            "non_test_practice_count": non_test_practice_count,
            "not_due_yet_count": not_due_yet_count,
            "score": score,
            "has_practice": has_practice
        }), 200

    except Exception as e:
        import traceback
        logger.error(f"Error in get_practice_status: {str(e, exc_info=True)}\n{traceback.format_exc()}")
        return jsonify({"error": "Internal server error"}), 500
