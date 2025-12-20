"""
Simple Timezone Utilities

Provides basic timezone functionality for date calculations.
Simplified replacement for schedule_service timezone functions.
"""

from datetime import datetime, date
from typing import Tuple
from utils.database import db_fetch_one
import logging

logger = logging.getLogger(__name__)


def get_user_timezone(user_id: str) -> str:
    """
    Get user's timezone from preferences.

    Args:
        user_id: UUID of the user

    Returns:
        Timezone string (e.g., 'America/New_York'), defaults to 'UTC'
    """
    try:
        result = db_fetch_one("""
            SELECT timezone FROM user_preferences WHERE user_id = %s
        """, (user_id,))

        if result and result.get('timezone'):
            return result['timezone']
        return 'UTC'
    except Exception as e:
        logger.error(f"Error fetching user timezone: {e}")
        return 'UTC'


def get_user_today(user_id: str) -> Tuple[str, date]:
    """
    Get today's date in user's timezone.

    Args:
        user_id: UUID of the user

    Returns:
        Tuple of (timezone_string, today_date)
    """
    try:
        user_tz = get_user_timezone(user_id)

        # Get current date in user's timezone using PostgreSQL
        result = db_fetch_one("""
            SELECT (NOW() AT TIME ZONE %s)::date as today
        """, (user_tz,))

        if result:
            return user_tz, result['today']

        # Fallback to UTC if query fails
        return 'UTC', datetime.utcnow().date()

    except Exception as e:
        logger.error(f"Error getting user's today: {e}")
        return 'UTC', datetime.utcnow().date()
