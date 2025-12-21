"""
Streak Days Handler

This module provides functions to:
- Track daily completion streaks
- Calculate consecutive streak days
"""

from flask import jsonify, request
from datetime import datetime, timedelta, date
import sys
import os
import uuid
import logging

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utils.database import get_db_connection, db_execute, db_fetch_all, db_fetch_one
from utils.timezone import get_user_today
from middleware.logging import log_error

logger = logging.getLogger(__name__)


def create_streak_date(user_id: str) -> bool:
    """
    Create a streak date record for today (idempotent).
    Works for all users, regardless of schedule status.

    Args:
        user_id: UUID of the user

    Returns:
        True if record was created/already exists, False on error
    """
    try:
        # Get user's timezone
        user_tz, today = get_user_today(user_id)

        # Insert today's date (idempotent due to UNIQUE constraint)
        db_execute("""
            INSERT INTO streak_days (user_id, streak_date)
            VALUES (%s, %s)
            ON CONFLICT (user_id, streak_date) DO NOTHING
        """, (user_id, today), commit=True)

        return True
    except Exception as e:
        log_error(logger, "Error creating streak date", user_id=user_id)
        return False


def calculate_streak_days(user_id: str) -> int:
    """
    Calculate the current streak count based on review activity.

    Algorithm:
    - If latest review > 24h ago → streak = 0
    - Otherwise: count consecutive days with reviews (no gap > 24h)
    - Uses reviews table directly (any review counts)

    Args:
        user_id: UUID of the user

    Returns:
        Number of consecutive streak days
    """
    try:
        # Get user's timezone
        user_tz, today = get_user_today(user_id)

        # Get all unique review dates for user (sorted DESC)
        review_dates = db_fetch_all("""
            SELECT DATE(reviewed_at AT TIME ZONE 'UTC' AT TIME ZONE %s) as review_date
            FROM reviews
            WHERE user_id = %s
            GROUP BY DATE(reviewed_at AT TIME ZONE 'UTC' AT TIME ZONE %s)
            ORDER BY review_date DESC
        """, (user_tz, user_id, user_tz))

        if not review_dates:
            return 0

        # Convert to date objects
        dates = [row['review_date'] for row in review_dates]
        latest_review_date = dates[0]

        # Check if latest review is within 24h (today or yesterday)
        days_since_latest = (today - latest_review_date).days
        if days_since_latest > 1:  # More than 24h gap
            return 0

        # Count consecutive days backwards from today
        streak = 0
        expected_date = today

        for review_date in dates:
            if review_date == expected_date:
                streak += 1
                expected_date = expected_date - timedelta(days=1)
            else:
                # Gap found, stop counting
                break

        return streak

    except Exception as e:
        log_error(logger, "Error calculating streak days", user_id=user_id)
        return 0


def get_streak_days():
    """
    GET /v3/get-streak-days?user_id=XXX
    Get the current streak count for a user.

    Response:
        {
            "user_id": "uuid",
            "streak_days": 5
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

        streak = calculate_streak_days(user_id)

        return jsonify({
            "user_id": user_id,
            "streak_days": streak
        }), 200

    except Exception as e:
        log_error(logger, "Error in get_streak_days", user_id=request.args.get('user_id'))
        return jsonify({"error": "Internal server error"}), 500
