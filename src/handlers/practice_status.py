"""
Practice Status Handler

This module provides the practice status endpoint that returns:
- Number of new words from today's schedule
- Number of due/overdue words
- Number of stale words (not reviewed in 24 hours)
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

logger = logging.getLogger(__name__)


def get_practice_status():
    """
    GET /v3/practice-status?user_id=XXX
    Get practice status for a user including counts and score.

    Response:
        {
            "user_id": "uuid",
            "new_words_count": 5,
            "due_words_count": 12,
            "stale_words_count": 8,
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

        # Get today's date for schedule lookup
        today = datetime.now().strftime('%Y-%m-%d')
        now = datetime.now()
        twenty_four_hours_ago = now - timedelta(hours=24)

        # 1. Get new words count from today's schedule (if schedule tables exist)
        new_words_count = 0
        try:
            schedule_row = db_fetch_one("""
                SELECT dse.new_words
                FROM daily_schedule_entries dse
                JOIN study_schedules ss ON dse.schedule_id = ss.id
                WHERE ss.user_id = %s AND dse.scheduled_date = %s
            """, (user_id, today))

            if schedule_row and schedule_row.get('new_words'):
                new_words = schedule_row['new_words']
                # new_words is JSONB array of word strings
                # Count how many haven't been reviewed today
                if new_words:
                    new_words_count = len(new_words)
                    # Note: The new_words are just word strings, not word_ids
                    # For now, just return the count of new words scheduled
        except Exception as e:
            # Schedule tables may not exist yet, default to 0 new words
            logger.debug(f"Could not query schedule tables: {e}")

        # 2. Get due words count (words where next_review_date <= now, excluding known words)
        due_row = db_fetch_one("""
            SELECT COUNT(*) as cnt
            FROM saved_words sw
            WHERE sw.user_id = %s
              AND (sw.is_known IS NULL OR sw.is_known = FALSE)
              AND EXISTS (
                  SELECT 1 FROM reviews r
                  WHERE r.word_id = sw.id
                    AND r.next_review_date <= %s
              )
        """, (user_id, now))
        due_words_count = due_row['cnt'] if due_row else 0

        # 3. Get stale words count (not reviewed in 24 hours, not due, not new, excluding known)
        stale_row = db_fetch_one("""
            SELECT COUNT(*) as cnt
            FROM saved_words sw
            WHERE sw.user_id = %s
              AND (sw.is_known IS NULL OR sw.is_known = FALSE)
              AND EXISTS (
                  SELECT 1 FROM reviews r
                  WHERE r.word_id = sw.id
              )
              AND NOT EXISTS (
                  SELECT 1 FROM reviews r
                  WHERE r.word_id = sw.id
                    AND r.reviewed_at >= %s
              )
              AND NOT EXISTS (
                  SELECT 1 FROM reviews r
                  WHERE r.word_id = sw.id
                    AND r.next_review_date <= %s
              )
        """, (user_id, twenty_four_hours_ago, now))
        stale_words_count = stale_row['cnt'] if stale_row else 0

        # 4. Get score from reviews
        score_row = db_fetch_one("""
            SELECT COALESCE(SUM(CASE WHEN response THEN 2 ELSE 1 END), 0) as score
            FROM reviews
            WHERE user_id = %s
        """, (user_id,))
        score = score_row['score'] if score_row else 0

        # Determine if there's anything to practice
        has_practice = (new_words_count > 0 or due_words_count > 0 or stale_words_count > 0)

        return jsonify({
            "user_id": user_id,
            "new_words_count": max(0, new_words_count),
            "due_words_count": due_words_count,
            "stale_words_count": stale_words_count,
            "score": score,
            "has_practice": has_practice
        }), 200

    except Exception as e:
        import traceback
        logger.error(f"Error in get_practice_status: {str(e)}\n{traceback.format_exc()}")
        return jsonify({"error": "Internal server error"}), 500
