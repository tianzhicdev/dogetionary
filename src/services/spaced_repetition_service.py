"""
Spaced Repetition Service - Centralized spaced repetition algorithm

This service contains all spaced repetition logic for calculating retention
and scheduling reviews based on the exponential decay forgetting curve model.
"""

import math
from datetime import datetime, timedelta
from config.config import (
    DECAY_RATE_WEEK_1, DECAY_RATE_WEEK_2, DECAY_RATE_WEEK_3_4,
    DECAY_RATE_WEEK_5_8, DECAY_RATE_WEEK_9_PLUS, RETENTION_THRESHOLD
)


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


def calculate_retention(review_history, target_date, created_at):
    """
    Calculate memory retention at a specific date using the new decay algorithm.

    Rules:
    - Every review sets retention to 100% regardless of success/failure
    - Failure resets decay rate to 12.5% per day (restart from week 1)
    - Success continues current decay schedule
    - Retention follows exponential decay: retention = e^(-rate * days)
    """
    # Ensure we have datetime objects - convert if needed
    if not hasattr(target_date, 'hour'):
        target_date = datetime.combine(target_date, datetime.max.time())
    if not hasattr(created_at, 'hour'):
        created_at = datetime.combine(created_at, datetime.min.time())

    # If target date is before word creation, no retention
    if target_date < created_at:
        return 0.0

    # If target date is on the same day as creation, start at 100%
    if target_date.date() == created_at.date():
        return 1.0

    # If no reviews yet, start at 100% and decay from creation date
    if not review_history:
        days_since_creation = (target_date - created_at).days

        if days_since_creation == 0:
            return 1.0  # 100% on creation day

        # Calculate retention by applying decay cumulatively day by day
        retention = 1.0  # Start at 100% on creation day

        for day in range(1, days_since_creation + 1):
            current_day_date = created_at + timedelta(days=day)
            # Calculate days since creation for this day's decay rate
            days_since_start = (current_day_date - created_at).days
            daily_decay_rate = get_decay_rate(days_since_start)

            # Apply daily decay: retention = retention * e^(-daily_rate)
            retention = retention * math.exp(-daily_decay_rate)

        return max(0.0, min(1.0, retention))

    # Sort reviews by date
    sorted_reviews = sorted(review_history, key=lambda x: x['reviewed_at'])

    # Find the most recent review before or at target_date
    last_review = None
    last_failure_date = created_at  # Track when decay rate should reset

    for review in sorted_reviews:
        review_date = review['reviewed_at']

        # Ensure review_date is datetime for comparison
        if not hasattr(review_date, 'hour'):
            review_date = datetime.combine(review_date, datetime.min.time())

        if review_date <= target_date:
            last_review = review
            last_review['reviewed_at'] = review_date  # Update with datetime
            # If this review was a failure, reset the decay rate reference point
            if not review['response']:
                last_failure_date = review_date
        else:
            break

    # Calculate retention from the most recent review or creation
    if last_review:
        # Start from last review (always 100% immediately after any review)
        last_review_date = last_review['reviewed_at']
        days_since_review = (target_date - last_review_date).days

        # If same day as review, return 100%
        if target_date.date() == last_review_date.date():
            return 1.0

        # Calculate retention by applying decay cumulatively day by day
        retention = 1.0  # Start at 100% after review

        for day in range(1, days_since_review + 1):
            current_day_date = last_review_date + timedelta(days=day)
            # Calculate days since last failure for this day's decay rate
            days_since_failure = (current_day_date - last_failure_date).days
            daily_decay_rate = get_decay_rate(days_since_failure)

            # Apply daily decay: retention = retention * e^(-daily_rate)
            retention = retention * math.exp(-daily_decay_rate)

        return max(0.0, min(1.0, retention))
    else:
        # No reviews before target date, decay from creation
        days_since_creation = (target_date - created_at).days

        # If same day as creation, start at 100%
        if target_date.date() == created_at.date():
            return 1.0

        # Calculate retention by applying decay cumulatively day by day
        retention = 1.0  # Start at 100% on creation day

        for day in range(1, days_since_creation + 1):
            current_day_date = created_at + timedelta(days=day)
            # Calculate days since creation for this day's decay rate
            days_since_start = (current_day_date - created_at).days
            daily_decay_rate = get_decay_rate(days_since_start)

            # Apply daily decay: retention = retention * e^(-daily_rate)
            retention = retention * math.exp(-daily_decay_rate)

        return max(0.0, min(1.0, retention))


def get_next_review_date_new(review_history, created_at):
    """
    Calculate when retention drops below 40% threshold using cumulative decay algorithm
    that matches calculate_retention function.
    """
    # Ensure created_at is datetime
    if not hasattr(created_at, 'hour'):
        created_at = datetime.combine(created_at, datetime.min.time())

    # Start from last review or creation date
    if review_history:
        sorted_reviews = sorted(review_history, key=lambda x: x['reviewed_at'])
        last_review = sorted_reviews[-1]
        start_date = last_review['reviewed_at']

        # Ensure start_date is datetime
        if not hasattr(start_date, 'hour'):
            start_date = datetime.combine(start_date, datetime.min.time())

        # Find last failure for decay rate reference point
        last_failure_date = created_at
        for review in sorted_reviews:
            review_date = review['reviewed_at']
            if not hasattr(review_date, 'hour'):
                review_date = datetime.combine(review_date, datetime.min.time())
            if not review['response']:
                last_failure_date = review_date
    else:
        start_date = created_at
        last_failure_date = created_at

    # Simulate retention decay day by day using same logic as calculate_retention
    current_date = start_date
    retention = 1.0  # Start at 100% after last review/creation
    max_days = 730  # Safety cap at 2 years

    for day in range(1, max_days + 1):
        current_date = start_date + timedelta(days=day)

        # Calculate days since last failure for decay rate determination
        days_since_failure = (current_date - last_failure_date).days
        daily_decay_rate = get_decay_rate(days_since_failure)

        # Apply daily decay: retention = retention * e^(-daily_rate)
        retention = retention * math.exp(-daily_decay_rate)

        # Check if retention dropped below the configured threshold
        if retention <= RETENTION_THRESHOLD:
            return current_date

    # If retention never drops below 40% in 2 years, return max date
    return start_date + timedelta(days=max_days)
