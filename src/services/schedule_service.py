"""
Schedule service for test preparation study plans.

This module provides functions to:
- Calculate future review schedules
- Generate study schedules
- Manage timezone-aware date calculations
"""

from datetime import datetime, timedelta
from typing import List, Tuple
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from handlers.admin import get_next_review_date_new
from utils.database import get_db_connection
import pytz
from datetime import date
from typing import Dict, Set


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
        datetime.date(2025, 11, 10)
    """
    tz = pytz.timezone(timezone)
    return datetime.now(tz).date()


def get_test_vocabulary_words(test_type: str) -> Set[str]:
    """
    Get all vocabulary words for a specific test type.

    Args:
        test_type: One of 'TOEFL', 'IELTS', or 'BOTH'

    Returns:
        Set of word strings for the specified test(s)

    Raises:
        ValueError: If test_type is invalid
    """
    if test_type not in ['TOEFL', 'IELTS', 'BOTH']:
        raise ValueError(f"Invalid test_type: {test_type}. Must be 'TOEFL', 'IELTS', or 'BOTH'")

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT DISTINCT word
            FROM test_vocabularies
            WHERE language = 'en'
            AND (
                (%(test_type)s = 'TOEFL' AND is_toefl = TRUE) OR
                (%(test_type)s = 'IELTS' AND is_ielts = TRUE) OR
                (%(test_type)s = 'BOTH' AND (is_toefl = TRUE OR is_ielts = TRUE))
            )
        """, {'test_type': test_type})
        return set(row['word'] for row in cur.fetchall())
    finally:
        cur.close()
        conn.close()


def get_user_saved_words(user_id: str, learning_language: str = 'en') -> Dict[str, Dict]:
    """
    Get all saved words for a user with their metadata.

    Args:
        user_id: UUID of the user
        learning_language: Language being learned (default: 'en')

    Returns:
        Dictionary mapping word -> {id, created_at}

    Example:
        >>> words = get_user_saved_words('user-uuid')
        >>> words['apple']
        {'id': 123, 'created_at': datetime(2025, 1, 1)}
    """
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT id, word, created_at
            FROM saved_words
            WHERE user_id = %s AND learning_language = %s
        """, (user_id, learning_language))

        return {
            row['word']: {
                'id': row['id'],
                'created_at': row['created_at']
            }
            for row in cur.fetchall()
        }
    finally:
        cur.close()
        conn.close()


def get_word_review_history(word_id: int) -> List[Dict]:
    """
    Get complete review history for a specific word.

    Args:
        word_id: ID from saved_words table

    Returns:
        List of review dictionaries with 'reviewed_at' and 'response' keys,
        sorted by review date ascending

    Example:
        >>> reviews = get_word_review_history(123)
        >>> reviews[0]
        {'reviewed_at': datetime(2025, 1, 2), 'response': True}
    """
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT reviewed_at, response
            FROM reviews
            WHERE word_id = %s
            ORDER BY reviewed_at ASC
        """, (word_id,))
        return [
            {'reviewed_at': r['reviewed_at'], 'response': r['response']}
            for r in cur.fetchall()
        ]
    finally:
        cur.close()
        conn.close()


def get_schedule(past_schedule: List[Tuple[datetime, bool]], created_at: datetime) -> List[Tuple[datetime, bool]]:
    """
    Calculate 7 future review dates assuming all future reviews are correct.

    This function uses the existing spaced repetition algorithm (get_next_review_date_new)
    to predict when a word should be reviewed next. It assumes the user will get all
    future reviews correct, which gives an optimistic schedule for planning purposes.

    Args:
        past_schedule: List of (datetime, bool) tuples representing actual review history.
                      Each tuple is (review_date, was_correct).
        created_at: Datetime when the word was first saved/created.

    Returns:
        List of (datetime, True) tuples - 7 predicted future review dates.
        All are marked as True since we assume future success.

    Example:
        >>> created = datetime(2025, 1, 1)
        >>> past = [(datetime(2025, 1, 2), True), (datetime(2025, 1, 5), True)]
        >>> future = get_schedule(past, created)
        >>> len(future)
        7
        >>> future[0][1]  # All marked as True (assumed correct)
        True
    """
    # Convert past_schedule format to what get_next_review_date_new expects
    review_history = [
        {'reviewed_at': dt, 'response': result}
        for dt, result in past_schedule
    ]

    future_schedule = []

    # Generate 7 future review dates
    for i in range(7):
        # Calculate next review date based on current history
        next_date = get_next_review_date_new(review_history, created_at)

        # Add to future schedule (marked as True - assumed correct)
        future_schedule.append((next_date, True))

        # Add this assumed-correct review to history for next iteration
        # This simulates the user getting it right and calculates the next interval
        review_history.append({
            'reviewed_at': next_date,
            'response': True
        })

    return future_schedule


def initiate_schedule(user_id: str, test_type: str, target_end_date: date) -> Dict:
    """
    Generate complete study schedule from today to target_end_date.

    This function:
    1. Calculates how many new words to introduce per day
    2. Gets all test vocabulary words and filters out already-saved ones
    3. Categorizes saved words into test/non-test practice words
    4. Calculates review schedules for all saved words
    5. Distributes new words and practice reviews across days
    6. Saves schedule to database

    Args:
        user_id: UUID of the user
        test_type: 'TOEFL', 'IELTS', or 'BOTH'
        target_end_date: The date user wants to complete preparation by

    Returns:
        Dictionary with schedule metadata:
        {
            'schedule_id': int,
            'days_remaining': int,
            'total_new_words': int,
            'daily_new_words': int,
            'test_practice_words_count': int,
            'non_test_practice_words_count': int
        }

    Raises:
        ValueError: If target_end_date is not in the future
    """
    import json
    from handlers.admin import calculate_retention

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Get today in user's timezone
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        days_remaining = (target_end_date - today).days
        if days_remaining <= 0:
            raise ValueError("target_end_date must be in the future")

        # Get all test vocabulary words
        all_test_words = get_test_vocabulary_words(test_type)

        # Get user's saved words
        saved_words_map = get_user_saved_words(user_id)

        # Categorize saved words into test and non-test
        test_practice_words = set()
        non_test_practice_words = set()

        for word in saved_words_map.keys():
            if word in all_test_words:
                test_practice_words.add(word)
            else:
                non_test_practice_words.add(word)

        # Calculate new words pool (test words NOT yet saved)
        new_words_pool = list(all_test_words - set(saved_words_map.keys()))

        # Calculate daily new words (ceiling division)
        daily_new_words = max(1, (len(new_words_pool) + days_remaining - 1) // days_remaining)

        # Calculate practice schedules for all saved words
        test_practice_schedule = {}
        non_test_practice_schedule = {}

        for word, info in saved_words_map.items():
            # Get review history for this word
            reviews = get_word_review_history(info['id'])
            past_schedule = [(r['reviewed_at'], r['response']) for r in reviews]

            # Get future review dates (up to 7)
            future_reviews = get_schedule(past_schedule, info['created_at'])

            # Determine which schedule to add to
            target_schedule = test_practice_schedule if word in test_practice_words else non_test_practice_schedule

            # Add reviews that fall within our schedule window
            for idx, (review_date, _) in enumerate(future_reviews):
                if today <= review_date.date() <= target_end_date:
                    # Calculate expected retention at review time
                    retention = calculate_retention(reviews, review_date, info['created_at'])

                    if word not in target_schedule:
                        target_schedule[word] = []

                    target_schedule[word].append({
                        'date': review_date.date(),
                        'retention': retention,
                        'review_number': len(reviews) + idx + 1,
                        'word_id': info['id']
                    })

        # Build daily schedule and calculate projected reviews for new words
        schedule = {}
        new_word_index = 0

        for day_offset in range(days_remaining):
            current_date = today + timedelta(days=day_offset)

            # Assign new words for this day
            day_new_words = []
            for _ in range(daily_new_words):
                if new_word_index < len(new_words_pool):
                    word = new_words_pool[new_word_index]
                    day_new_words.append(word)

                    # Calculate projected future reviews for this new word
                    # Treat the day it's introduced as the "created_at" date
                    created_datetime = datetime.combine(current_date, datetime.min.time())
                    future_reviews = get_schedule([], created_datetime)  # Empty past, treat as brand new

                    # Determine which schedule to add to
                    is_test_word = word in all_test_words
                    target_schedule = test_practice_schedule if is_test_word else non_test_practice_schedule

                    # Add future reviews that fall within schedule window
                    if word not in target_schedule:
                        target_schedule[word] = []

                    for idx, (review_datetime, _) in enumerate(future_reviews):
                        review_date = review_datetime.date()
                        if today <= review_date <= target_end_date:
                            # Calculate expected retention (starts high for new words)
                            retention = 0.9 if idx == 0 else max(0.1, 0.9 - (idx * 0.1))

                            target_schedule[word].append({
                                'date': review_date,
                                'retention': retention,
                                'review_number': idx + 1,
                                'word_id': None  # No word_id yet since not saved
                            })

                    new_word_index += 1

            # Find test practice words due this day
            day_test_practice = []
            for word, reviews in test_practice_schedule.items():
                for review_info in reviews:
                    if review_info['date'] == current_date:
                        day_test_practice.append({
                            'word': word,
                            'word_id': review_info['word_id'],
                            'expected_retention': round(review_info['retention'], 2),
                            'review_number': review_info['review_number']
                        })

            # Find non-test practice words due this day
            day_non_test_practice = []
            for word, reviews in non_test_practice_schedule.items():
                for review_info in reviews:
                    if review_info['date'] == current_date:
                        day_non_test_practice.append({
                            'word': word,
                            'word_id': review_info['word_id'],
                            'expected_retention': round(review_info['retention'], 2),
                            'review_number': review_info['review_number']
                        })

            schedule[current_date.isoformat()] = {
                'new_words': day_new_words,
                'test_practice': day_test_practice,
                'non_test_practice': day_non_test_practice
            }

        # Save to database - delete existing schedule first
        cur.execute("DELETE FROM study_schedules WHERE user_id = %s", (user_id,))

        # Insert new schedule
        cur.execute("""
            INSERT INTO study_schedules (user_id, test_type, target_end_date)
            VALUES (%s, %s, %s)
            RETURNING id
        """, (user_id, test_type, target_end_date))

        schedule_id = cur.fetchone()['id']

        # Insert daily entries
        for date_str, entry in schedule.items():
            cur.execute("""
                INSERT INTO daily_schedule_entries
                (schedule_id, scheduled_date, new_words, test_practice_words, non_test_practice_words)
                VALUES (%s, %s, %s::jsonb, %s::jsonb, %s::jsonb)
            """, (
                schedule_id,
                datetime.fromisoformat(date_str).date(),
                json.dumps(entry['new_words']),
                json.dumps(entry['test_practice']),
                json.dumps(entry['non_test_practice'])
            ))

        conn.commit()

        return {
            'schedule_id': schedule_id,
            'days_remaining': days_remaining,
            'total_new_words': len(new_words_pool),
            'daily_new_words': daily_new_words,
            'test_practice_words_count': len(test_practice_words),
            'non_test_practice_words_count': len(non_test_practice_words)
        }

    except Exception as e:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


def refresh_schedule(user_id: str, new_target_end_date: date = None) -> Dict:
    """
    Refresh existing schedule considering current progress.

    This regenerates the schedule from today forward, taking into account:
    - New reviews completed since last generation
    - Words added/removed from saved_words
    - Changed target_end_date (if provided)

    Args:
        user_id: UUID of the user
        new_target_end_date: Optional new target date. If None, keeps existing.

    Returns:
        Same as initiate_schedule(): schedule metadata dict

    Raises:
        ValueError: If no active schedule found or if new date is invalid
    """
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Get existing schedule
        cur.execute("""
            SELECT id, test_type, target_end_date
            FROM study_schedules
            WHERE user_id = %s
        """, (user_id,))

        existing = cur.fetchone()

        if not existing:
            raise ValueError("No active schedule found for user")

        # Use new end date if provided, otherwise keep existing
        target_end_date = new_target_end_date or existing['target_end_date']

        # Regenerate schedule (which accounts for all new reviews, changes, etc.)
        return initiate_schedule(user_id, existing['test_type'], target_end_date)

    finally:
        cur.close()
        conn.close()
