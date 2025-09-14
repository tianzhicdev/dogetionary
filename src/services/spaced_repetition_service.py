import math
from datetime import datetime, timedelta
from config.config import (
    DECAY_RATE_WEEK_1, DECAY_RATE_WEEK_2, DECAY_RATE_WEEK_3_4,
    DECAY_RATE_WEEK_5_8, DECAY_RATE_WEEK_9_PLUS, RETENTION_THRESHOLD
)
from utils.database import get_db_connection

def calculate_spaced_repetition(reviews_data, current_review_time=None):
    """
    DEPRECATED: Simple calculation for backward compatibility - SQL handles the logic now

    This function is deprecated and should not be used for new code.
    Use get_next_review_date_new from app.py instead.
    This function is maintained only for get_word_review_data compatibility.
    """
    if not reviews_data:
        return 0, 1, datetime.now() + timedelta(days=1), None

    reviews_data.sort(key=lambda r: r['reviewed_at'])
    review_count = len(reviews_data)
    last_reviewed_at = reviews_data[-1]['reviewed_at']
    current_time = current_review_time or datetime.now()

    # Simple interval calculation for API compatibility
    # Actual logic is now in SQL
    consecutive_correct = 0
    for review in reversed(reviews_data):
        if review['response']:
            consecutive_correct += 1
        else:
            break

    if not reviews_data[-1]['response']:
        interval_days = 1
    elif consecutive_correct == 1:
        interval_days = 5  # Updated to match new logic
    elif consecutive_correct >= 2 and len(reviews_data) >= 2:
        # Calculate based on time difference like SQL does
        previous_review_time = reviews_data[-2]['reviewed_at']
        time_diff_days = (last_reviewed_at - previous_review_time).total_seconds() / 86400
        interval_days = max(1, int(2.5 * time_diff_days))
    else:
        interval_days = 1

    next_review_date = current_time + timedelta(days=interval_days)
    return review_count, interval_days, next_review_date, last_reviewed_at

def get_decay_rate(days_since_start_or_failure):
    """
    Calculate daily decay rate based on time elapsed since start or last failure.
    Uses configurable constants for easy tuning.
    """
    if days_since_start_or_failure < 7:
        return DECAY_RATE_WEEK_1
    elif days_since_start_or_failure < 14:
        return DECAY_RATE_WEEK_2
    elif days_since_start_or_failure < 28:
        return DECAY_RATE_WEEK_3_4
    elif days_since_start_or_failure < 56:
        return DECAY_RATE_WEEK_5_8
    elif days_since_start_or_failure < 112:
        return DECAY_RATE_WEEK_9_PLUS
    else:
        # Continue halving for longer periods
        period = 112
        rate = DECAY_RATE_WEEK_9_PLUS
        while days_since_start_or_failure >= period * 2:
            period *= 2
            rate /= 2
        return rate