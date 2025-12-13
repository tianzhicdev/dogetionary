"""
Shared timezone utility functions for consistent timezone handling across the application.

All date/time calculations MUST use these utilities to ensure user timezone is respected.
"""

from datetime import date, datetime
from typing import Optional
import pytz
from utils.database import get_db_connection


def get_user_timezone(user_id: str) -> str:
    """
    Get user's configured timezone from database.

    Args:
        user_id: UUID of the user

    Returns:
        Timezone string (IANA format, e.g., 'America/New_York') or 'UTC' if not set
    """
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("SELECT timezone FROM user_preferences WHERE user_id = %s", (user_id,))
        result = cur.fetchone()
        return result['timezone'] if result and result['timezone'] else 'UTC'
    finally:
        cur.close()
        conn.close()


def get_today_in_timezone(timezone: str) -> date:
    """
    Get today's date in the specified timezone.

    Args:
        timezone: IANA timezone string (e.g., 'America/New_York', 'Asia/Tokyo')

    Returns:
        Today's date in the specified timezone

    Example:
        >>> get_today_in_timezone('UTC')
        datetime.date(2025, 12, 13)
        >>> get_today_in_timezone('Asia/Tokyo')  # 9 hours ahead
        datetime.date(2025, 12, 13)  # or 2025-12-14 if after 3 PM UTC
    """
    tz = pytz.timezone(timezone)
    return datetime.now(tz).date()


def get_now_in_timezone(timezone: str) -> datetime:
    """
    Get current datetime in the specified timezone.

    Args:
        timezone: IANA timezone string

    Returns:
        Current datetime in the specified timezone (timezone-aware)
    """
    tz = pytz.timezone(timezone)
    return datetime.now(tz)


def convert_utc_to_user_date(utc_datetime: datetime, timezone: str) -> date:
    """
    Convert a UTC datetime to a date in the user's timezone.

    Args:
        utc_datetime: UTC datetime (timezone-aware or naive, assumed UTC)
        timezone: User's IANA timezone string

    Returns:
        Date in user's timezone

    Example:
        >>> utc_dt = datetime(2025, 12, 13, 23, 30)  # 11:30 PM UTC
        >>> convert_utc_to_user_date(utc_dt, 'Asia/Tokyo')
        datetime.date(2025, 12, 14)  # Next day in Tokyo (UTC+9)
    """
    if utc_datetime.tzinfo is None:
        utc_datetime = pytz.UTC.localize(utc_datetime)

    user_tz = pytz.timezone(timezone)
    return utc_datetime.astimezone(user_tz).date()


def is_due_in_user_timezone(next_review_date: date, user_id: str) -> bool:
    """
    Check if a review is due based on user's timezone.

    A review is "due" if next_review_date <= today (in user's timezone).

    Args:
        next_review_date: The scheduled review date
        user_id: User's UUID

    Returns:
        True if review is due, False otherwise

    Example:
        User in Tokyo (UTC+9), current UTC time is 2025-12-13 16:00 (1 AM in Tokyo, Dec 14)
        Review scheduled for 2025-12-14:
        - UTC comparison: 2025-12-14 > 2025-12-13 → NOT due (WRONG!)
        - Tokyo comparison: 2025-12-14 <= 2025-12-14 → IS due (CORRECT!)
    """
    timezone = get_user_timezone(user_id)
    today = get_today_in_timezone(timezone)
    return next_review_date <= today


def get_sql_now_in_user_timezone(timezone: str) -> str:
    """
    Get SQL expression for current date/time in user's timezone.

    This returns the SQL expression as a string for use in queries.

    Args:
        timezone: User's IANA timezone string

    Returns:
        SQL expression string to get current time in user timezone

    Example SQL usage:
        WHERE next_review_date <= (NOW() AT TIME ZONE %s)::date
        And pass timezone as parameter
    """
    return f"(NOW() AT TIME ZONE '{timezone}')::date"


def build_due_check_sql() -> tuple[str, str]:
    """
    Build SQL WHERE clause for checking if reviews are due in user timezone.

    Returns:
        Tuple of (sql_fragment, parameter_name)
        - sql_fragment: The SQL WHERE condition with placeholder
        - parameter_name: 'user_timezone' to use in query parameters

    Example usage:
        sql_condition, param_name = build_due_check_sql()
        query = f"SELECT * FROM saved_words WHERE {sql_condition}"
        cur.execute(query, {param_name: user_timezone})
    """
    sql = "next_review_date <= (NOW() AT TIME ZONE %s)::date"
    return sql, "user_timezone"
