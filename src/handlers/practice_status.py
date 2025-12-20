"""
Practice Status Handler - Simplified Version

Returns simple counts for practice status:
- due_word_count: Words that are due for review (next_review <= NOW)
- new_word_count_past_24h: Words saved in the last 24 hours
- total_word_count: Total saved words
- score: User's current score
"""

from flask import jsonify, request
import sys
import os
import uuid
import logging

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utils.database import db_fetch_one
from handlers.achievements import calculate_user_score

logger = logging.getLogger(__name__)


def get_practice_status():
    """
    GET /v3/practice-status?user_id=XXX
    Get practice status for a user with simple on-the-fly counts.

    Response:
        {
            "user_id": "uuid",
            "due_word_count": 15,
            "new_word_count_past_24h": 3,
            "total_word_count": 87,
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

        # Count due words (next_review_date <= TODAY)
        # Words with reviews that are due, or new words never reviewed
        due_count_row = db_fetch_one("""
            SELECT COUNT(DISTINCT sw.id) as cnt
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
        """, (user_id,))
        due_word_count = due_count_row['cnt'] if due_count_row else 0

        # Count words saved in last 24 hours
        new_count_row = db_fetch_one("""
            SELECT COUNT(*) as cnt
            FROM saved_words
            WHERE user_id = %s
            AND created_at >= NOW() - INTERVAL '24 hours'
        """, (user_id,))
        new_word_count_past_24h = new_count_row['cnt'] if new_count_row else 0

        # Count total saved words
        total_count_row = db_fetch_one("""
            SELECT COUNT(*) as cnt
            FROM saved_words
            WHERE user_id = %s
        """, (user_id,))
        total_word_count = total_count_row['cnt'] if total_count_row else 0

        # Get score using utility function
        score = calculate_user_score(user_id)

        # Determine if there's anything to practice
        has_practice = due_word_count > 0

        logger.info(f"Practice status: user_id={user_id}, due={due_word_count}, new_24h={new_word_count_past_24h}, total={total_word_count}")

        return jsonify({
            "user_id": user_id,
            "due_word_count": due_word_count,
            "new_word_count_past_24h": new_word_count_past_24h,
            "total_word_count": total_word_count,
            "score": score,
            "has_practice": has_practice
        }), 200

    except Exception as e:
        import traceback
        logger.error(f"Error in get_practice_status: {str(e)}\n{traceback.format_exc()}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500
