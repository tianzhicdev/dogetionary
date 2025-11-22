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

        # Get counts from today's schedule, excluding words already reviewed today
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

            # Get today's schedule with actual word lists
            schedule_row = db_fetch_one("""
                SELECT
                    dse.new_words,
                    dse.test_practice_words,
                    dse.non_test_practice_words
                FROM daily_schedule_entries dse
                JOIN study_schedules ss ON dse.schedule_id = ss.id
                WHERE ss.user_id = %s AND dse.scheduled_date = %s
            """, (user_id, today))

            if schedule_row:
                # Count words not yet reviewed today
                new_words = schedule_row['new_words'] or []
                test_words = schedule_row['test_practice_words'] or []
                non_test_words = schedule_row['non_test_practice_words'] or []

                new_words_count = len([w for w in new_words if w not in reviewed_today])
                test_practice_count = len([w for w in test_words if w not in reviewed_today])
                non_test_practice_count = len([w for w in non_test_words if w not in reviewed_today])
        except Exception as e:
            # Schedule tables may not exist yet, default to 0
            logger.debug(f"Could not query schedule tables: {e}")

        # Get not-due-yet count (reviewed before, last review > 24h ago, not due yet)
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
              AND COALESCE(latest_review.next_review_date, NOW() + INTERVAL '1 day') > NOW()
        """, (user_id,))
        not_due_yet_count = not_due_yet_row['cnt'] if not_due_yet_row else 0

        # Get score from reviews
        score_row = db_fetch_one("""
            SELECT COALESCE(SUM(CASE WHEN response THEN 2 ELSE 1 END), 0) as score
            FROM reviews
            WHERE user_id = %s
        """, (user_id,))
        score = score_row['score'] if score_row else 0

        # Determine if there's anything to practice
        has_practice = (new_words_count > 0 or test_practice_count > 0 or
                        non_test_practice_count > 0 or not_due_yet_count > 0)

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
        logger.error(f"Error in get_practice_status: {str(e)}\n{traceback.format_exc()}")
        return jsonify({"error": "Internal server error"}), 500
