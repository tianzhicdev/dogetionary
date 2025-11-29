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
from services.schedule_service import get_user_timezone, get_today_in_timezone

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
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        # Insert today's date (idempotent due to UNIQUE constraint)
        db_execute("""
            INSERT INTO streak_days (user_id, streak_date)
            VALUES (%s, %s)
            ON CONFLICT (user_id, streak_date) DO NOTHING
        """, (user_id, today), commit=True)

        return True
    except Exception as e:
        logger.error(f"Error creating streak date for user {user_id}: {str(e)}")
        return False


def calculate_streak_days(user_id: str) -> int:
    """
    Calculate the current streak count for a user.
    Works for all users, regardless of schedule status.

    Algorithm:
    - Get today's date in user's timezone
    - Fetch all streak dates for user (sorted DESC)
    - Count consecutive dates backwards from today
    - If today has a record, include it
    - If yesterday has no record, streak resets

    Args:
        user_id: UUID of the user

    Returns:
        Number of consecutive streak days
    """
    try:
        # Get user's timezone
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        # Get all streak dates for user (sorted DESC)
        streak_dates = db_fetch_all("""
            SELECT streak_date
            FROM streak_days
            WHERE user_id = %s
            ORDER BY streak_date DESC
        """, (user_id,))

        if not streak_dates:
            return 0

        # Convert to date objects
        dates = [row['streak_date'] for row in streak_dates]

        # Count consecutive dates backwards from today
        streak = 0
        expected_date = today

        for streak_date in dates:
            if streak_date == expected_date:
                streak += 1
                expected_date = expected_date - timedelta(days=1)
            else:
                # Gap found, stop counting
                break

        return streak

    except Exception as e:
        logger.error(f"Error calculating streak days for user {user_id}: {str(e)}")
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
        logger.error(f"Error in get_streak_days: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500
