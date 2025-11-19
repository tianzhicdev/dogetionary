#!/usr/bin/env python3
"""
Calculate the next 7 review dates for a word learned on Day 1
using the current spaced repetition algorithm.
"""

import math
from datetime import datetime, timedelta

# Configuration from src/config/config.py
DECAY_RATE_WEEK_1 = 0.45      # 45% per day
DECAY_RATE_WEEK_2 = 0.18      # 18% per day
DECAY_RATE_WEEK_3_4 = 0.09    # 9% per day
DECAY_RATE_WEEK_5_8 = 0.035   # 3.5% per day
DECAY_RATE_WEEK_9_PLUS = 0.015 # 1.5% per day
RETENTION_THRESHOLD = 0.40     # 40% retention threshold

def get_decay_rate(days_since_start_or_failure):
    """Calculate daily decay rate based on time elapsed"""
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

def calculate_next_review_date(last_review_date, creation_date):
    """
    Calculate when retention drops below 40% threshold.

    Key insight from the algorithm:
    - Retention starts at 100% from last_review_date
    - Decay RATE is determined by days since creation (for all successful reviews)
    - If user had a failure, decay rate would be from last failure

    Args:
        last_review_date: Date of last review (or creation if first review)
        creation_date: Original word creation date

    Returns:
        Tuple of (next_review_date, retention_at_review, days_from_last_review)
    """
    current_date = last_review_date
    retention = 1.0  # Start at 100% after last review
    max_days = 730  # Safety cap at 2 years

    for day in range(1, max_days + 1):
        current_date = last_review_date + timedelta(days=day)
        # For successful reviews, days_since_failure = days since creation
        days_since_creation = (current_date - creation_date).days
        daily_decay_rate = get_decay_rate(days_since_creation)
        retention = retention * math.exp(-daily_decay_rate)

        if retention <= RETENTION_THRESHOLD:
            return current_date, retention, day

    return last_review_date + timedelta(days=max_days), retention, max_days

def main():
    # Word learned on Day 1
    creation_date = datetime(2025, 1, 1)  # Arbitrary start date

    print("=" * 80)
    print("SPACED REPETITION SCHEDULE (All Successful Reviews)")
    print("Word learned on: Day 1 (January 1, 2025)")
    print("Assumption: User answers correctly every time")
    print("=" * 80)
    print()

    last_review_date = creation_date

    for review_num in range(1, 8):
        # Calculate next review based on last review date and creation date
        next_review_date, retention, days_from_last = calculate_next_review_date(
            last_review_date, creation_date
        )
        total_days = (next_review_date - creation_date).days

        # Calculate what decay rate zone we're in
        days_since_creation = total_days
        decay_rate = get_decay_rate(days_since_creation)

        print(f"Review #{review_num}")
        print(f"  Date: {next_review_date.strftime('%B %d, %Y')} (Day {total_days + 1})")
        print(f"  Days from last review: {days_from_last}")
        print(f"  Total days from creation: {total_days}")
        print(f"  Retention at review: {retention * 100:.2f}%")
        print(f"  Current decay rate: {decay_rate * 100:.2f}% per day")
        print()

        # After successful review, retention resets to 100%
        # Next review calculated from this date
        last_review_date = next_review_date

    print("=" * 80)

if __name__ == "__main__":
    main()
