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

from services.spaced_repetition_service import get_next_review_date_new
from utils.database import get_db_connection
import pytz
from datetime import date
from typing import Dict, Set, Callable, List as ListType
import logging

logger = logging.getLogger(__name__)


def fetch_schedule_data(user_id: str, test_type: str, user_tz: str, today: date) -> Dict:
    """
    Fetch all data needed for calc_schedule() from database.

    This is a helper function that extracts the data-fetching logic
    from initiate_schedule() so it can be reused by on-the-fly schedule APIs.

    Args:
        user_id: UUID of the user
        test_type: Test type (from user preferences)
        user_tz: User's timezone string
        today: Today's date in user's timezone

    Returns:
        Dict with all data needed for calc_schedule():
        {
            'all_test_words': Set[str],
            'saved_words_with_reviews': Dict[str, Dict],
            'words_saved_today': Set[str],
            'words_reviewed_today': Set[str],
            'all_saved_words': Set[str]
        }
    """
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Get all test vocabulary words
        all_test_words = get_test_vocabulary_words(test_type)

        # Get ALL user's saved words for practice scheduling
        saved_words_map = get_user_saved_words(
            user_id,
            exclude_date=None,
            timezone=user_tz,
            exclude_only_test_words=False,
            test_type=test_type
        )

        # Also fetch ALL saved words (including known ones) for new_words_pool exclusion
        cur.execute("""
            SELECT word FROM saved_words
            WHERE user_id = %s AND learning_language = 'en'
        """, (user_id,))
        all_saved_words = {row['word'] for row in cur.fetchall()}

        # Build saved_words_with_reviews
        saved_words_with_reviews = {}
        for word, info in saved_words_map.items():
            reviews = get_word_review_history(info['id'], exclude_date=None, timezone=user_tz)
            saved_words_with_reviews[word] = {
                'id': info['id'],
                'created_at': info['created_at'],
                'reviews': reviews,
                'is_known': info['is_known']
            }

        # Get words saved/reviewed today
        words_saved_today = get_words_saved_on_date(user_id, today, user_tz)
        words_reviewed_today = get_words_reviewed_on_date(user_id, today, user_tz)

        return {
            'all_test_words': all_test_words,
            'saved_words_with_reviews': saved_words_with_reviews,
            'words_saved_today': words_saved_today,
            'words_reviewed_today': words_reviewed_today,
            'all_saved_words': all_saved_words
        }

    finally:
        cur.close()
        conn.close()



def calc_schedule_v2(    today: date,
    target_end_date: date,
    all_test_words: Set[str],
    saved_words_with_reviews: Dict[str, Dict],  # word -> {id, created_at, reviews: List[{reviewed_at, response}], is_known: bool}
) -> Dict:
    
    schedule = {}
    days_remaining = (target_end_date - today).days

    #     first we calc today's words
    # -- new words: first x of (test-words - words-saved-before-today)

    words_saved_before_today = set() # get it from saved_words_with_reviews




    new_words_pool = sorted(all_test_words - saved_words_with_reviews.keys())
    daily_new_words = max(1, (len(new_words_pool) + days_remaining - 1) // days_remaining)

    today_new_words = sorted(all_test_words - words_saved_before_today)[:daily_new_words]


    # then we calc tmr and further
    # -- first x of (words - today's new words - all-saved-words-including-today's)

    new_words_for_tmr_and_beyond = sorted(all_test_words - today_new_words - saved_words_with_reviews.keys())



    # -- practice words: (words saved/reviewed including today) 

    # -- words saved/reviewed including today + today's new words




    return {
        'daily_schedules': schedule,
        'metadata': {
            'days_remaining': days_remaining,
            'total_new_words': len(new_words_pool),
            'daily_new_words': daily_new_words,
            'test_practice_words_count': len(test_practice_words),
            'non_test_practice_words_count': len(non_test_practice_words)
        }
    }

def calc_schedule(
    today: date,
    target_end_date: date,
    all_test_words: Set[str],
    saved_words_with_reviews: Dict[str, Dict],  # word -> {id, created_at, reviews: List[{reviewed_at, response}], is_known: bool}
    words_saved_today: Set[str],
    words_reviewed_today: Set[str],
    get_schedule_fn: Callable,  # Function(past_schedule, created_at) -> future_reviews
    all_saved_words: Set[str] = None,  # ALL saved words including known ones
) -> Dict:
    


    """

    first we calc today's words
    -- new words: first x of (test-words - words-saved-before-today)
    -- practice words: (words saved/reviewed including today) 

    then we calc tmr and further

    -- first x of (words - today's new words - all-saved-words-including-today's)
    -- words saved/reviewed including today + today's new words

    Pure function to calculate study schedule distribution.

    This function has NO side effects and does NOT access the database.
    All inputs must be provided as parameters.

    IMPORTANT: saved_words_with_reviews should NOT include words marked as is_known=TRUE.
    Known words are excluded from practice scheduling at the data-fetching layer.
    However, all_saved_words SHOULD include known words to exclude them from new_words_pool.

    Args:
        today: Start date for schedule (date object)
        target_end_date: End date for schedule (date object)
        all_test_words: Set of all test vocabulary words for the user's test type
        saved_words_with_reviews: Map of word -> {
            'id': int,
            'created_at': datetime,
            'reviews': List[{'reviewed_at': datetime, 'response': str}],
            'is_known': bool (should always be False in this dict)
        }
        words_saved_today: Set of words saved on 'today' (in user's timezone)
        words_reviewed_today: Set of words reviewed on 'today' (in user's timezone)
        get_schedule_fn: Function to calculate future review dates
                         Signature: (past_schedule: List[(datetime, str)], created_at: datetime)
                                   -> List[(datetime, str)]
        all_saved_words: Set of ALL saved word names (including known words) to exclude from new_words_pool.
                        If None, defaults to saved_words_with_reviews.keys()

    Returns:
        {
            'daily_schedules': {
                'YYYY-MM-DD': {
                    'new_words': [str],
                    'test_practice': [{'word': str, 'word_id': int|None, 'review_number': int}],
                    'non_test_practice': [{'word': str, 'word_id': int, 'review_number': int}]
                }
            },
            'metadata': {
                'days_remaining': int,
                'total_new_words': int,
                'daily_new_words': int,
                'test_practice_words_count': int,
                'non_test_practice_words_count': int
            }
        }

    Raises:
        ValueError: If target_end_date is not in the future
    """
    # Validation
    days_remaining = (target_end_date - today).days
    if days_remaining <= 0:
        raise ValueError("target_end_date must be in the future")

    # If all_saved_words not provided, use saved_words_with_reviews keys (backward compatibility)
    if all_saved_words is None:
        all_saved_words = set(saved_words_with_reviews.keys())

    # Categorize saved words into test and non-test
    test_practice_words = set()
    non_test_practice_words = set()

    for word in saved_words_with_reviews.keys():
        if word in all_test_words:
            test_practice_words.add(word)
        else:
            non_test_practice_words.add(word)

    # Calculate new words pool (test words NOT yet saved, including known words)
    # Use all_saved_words to exclude BOTH unknown AND known saved words
    new_words_pool = sorted(all_test_words - all_saved_words | (words_saved_today.intersection(all_test_words)))

    # Get words done today (saved OR reviewed) - these should be excluded from tomorrow onwards
    words_done_today = (words_saved_today | words_reviewed_today) & all_test_words  # Only test words

    # Calculate daily new words (ceiling division)
    daily_new_words = max(1, (len(new_words_pool) + days_remaining - 1) // days_remaining)

    # Calculate practice schedules for all saved words
    test_practice_schedule = {}
    non_test_practice_schedule = {}

    for word, info in saved_words_with_reviews.items():
        # Convert reviews to the format expected by get_schedule_fn
        past_schedule = [(r['reviewed_at'], r['response']) for r in info['reviews']]

        # Get future review dates (up to 7)
        future_reviews = get_schedule_fn(past_schedule, info['created_at'])

        # Determine which schedule to add to
        target_schedule = test_practice_schedule if word in test_practice_words else non_test_practice_schedule

        # Add reviews that fall within our schedule window
        # IMPORTANT: Overdue reviews (review_date < today) are scheduled for TODAY
        # to ensure they appear in today's practice queue
        for idx, (review_date, _) in enumerate(future_reviews):
            review_date_only = review_date.date()

            # Skip reviews that are beyond the target_end_date
            if review_date_only > target_end_date:
                continue

            # Treat overdue reviews as due today
            scheduled_date = review_date_only if review_date_only >= today else today

            if word not in target_schedule:
                target_schedule[word] = []

            target_schedule[word].append({
                'date': scheduled_date,
                'review_number': len(info['reviews']) + idx + 1,
                'word_id': info['id']
            })

    # Build daily schedule and calculate projected reviews for new words
    schedule = {}
    new_word_index = 0
    today_allocated_words = set()  # Track words allocated to today for exclusion from tomorrow onwards

    for day_offset in range(days_remaining):
        current_date = today + timedelta(days=day_offset)
        is_today = (day_offset == 0)

        # Assign new words for this day
        day_new_words = []
        words_to_allocate = daily_new_words

        while len(day_new_words) < words_to_allocate and new_word_index < len(new_words_pool):
            word = new_words_pool[new_word_index]
            new_word_index += 1

            # For tomorrow onwards, skip words that were:
            # 1. Allocated to today's schedule, OR
            # 2. Saved/reviewed today (even if not in schedule)
            # This prevents today's words from reappearing in future days
            # even if the user regenerates the schedule with a different duration
            # NOTE: For TODAY itself, we don't exclude words_done_today because
            # they should appear in today's new_words list
            if not is_today and (word in today_allocated_words or word in words_done_today):
                continue

            day_new_words.append(word)

            # Track today's allocations for exclusion from future days
            if is_today:
                today_allocated_words.add(word)

            # Calculate projected future reviews for this new word
            # Treat the day it's introduced as the "created_at" date
            created_datetime = datetime.combine(current_date, datetime.min.time())
            future_reviews = get_schedule_fn([], created_datetime)  # Empty past, treat as brand new

            # Determine which schedule to add to
            is_test_word = word in all_test_words
            target_schedule = test_practice_schedule if is_test_word else non_test_practice_schedule

            # Add future reviews that fall within schedule window
            if word not in target_schedule:
                target_schedule[word] = []

            for idx, (review_datetime, _) in enumerate(future_reviews):
                review_date = review_datetime.date()

                # Skip reviews beyond target_end_date
                if review_date > target_end_date:
                    continue

                # Treat overdue reviews as due today (consistency with saved words)
                scheduled_date = review_date if review_date >= today else today

                target_schedule[word].append({
                    'date': scheduled_date,
                    'review_number': idx + 1,
                    'word_id': None  # No word_id yet since not saved
                })

        # Find test practice words due this day
        day_test_practice = []
        for word, reviews in test_practice_schedule.items():
            for review_info in reviews:
                if review_info['date'] == current_date:
                    day_test_practice.append({
                        'word': word,
                        'word_id': review_info['word_id'],
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
                        'review_number': review_info['review_number']
                    })

        schedule[current_date.isoformat()] = {
            'new_words': day_new_words,
            'test_practice': day_test_practice,
            'non_test_practice': day_non_test_practice
        }

    return {
        'daily_schedules': schedule,
        'metadata': {
            'days_remaining': days_remaining,
            'total_new_words': len(new_words_pool),
            'daily_new_words': daily_new_words,
            'test_practice_words_count': len(test_practice_words),
            'non_test_practice_words_count': len(non_test_practice_words)
        }
    }


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


def get_words_reviewed_on_date(user_id: str, target_date: date, timezone: str) -> Set[str]:
    """
    Get all words reviewed on a specific date in user's timezone.

    Converts review timestamps from UTC to user timezone before comparing dates.

    Args:
        user_id: UUID of the user
        target_date: The date to check (in user's timezone)
        timezone: User's IANA timezone string

    Returns:
        Set of word strings reviewed on that date
    """
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT DISTINCT sw.word
            FROM reviews r
            JOIN saved_words sw ON r.word_id = sw.id
            WHERE r.user_id = %s
              AND DATE(r.reviewed_at AT TIME ZONE 'UTC' AT TIME ZONE %s) = %s
        """, (user_id, timezone, target_date))
        return {row['word'] for row in cur.fetchall()}
    finally:
        cur.close()
        conn.close()


def get_words_saved_on_date(user_id: str, target_date: date, timezone: str, learning_language: str = 'en') -> Set[str]:
    """
    Get all words saved on a specific date in user's timezone.

    Converts created_at timestamps from UTC to user timezone before comparing dates.

    Args:
        user_id: UUID of the user
        target_date: The date to check (in user's timezone)
        timezone: User's IANA timezone string
        learning_language: Language being learned (default: 'en')

    Returns:
        Set of word strings saved on that date
    """
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute("""
            SELECT DISTINCT word
            FROM saved_words
            WHERE user_id = %s
              AND learning_language = %s
              AND DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE %s) = %s
        """, (user_id, learning_language, timezone, target_date))
        return {row['word'] for row in cur.fetchall()}
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
        test_type: One of the level-based types:
                   - 'TOEFL_BEGINNER', 'TOEFL_INTERMEDIATE', 'TOEFL_ADVANCED'
                   - 'IELTS_BEGINNER', 'IELTS_INTERMEDIATE', 'IELTS_ADVANCED'
                   - 'TIANZ'
                   - Legacy: 'TOEFL', 'IELTS', 'BOTH'

    Returns:
        Set of word strings for the specified test(s)

    Raises:
        ValueError: If test_type is invalid
    """
    # Column mapping for level-based test types
    VOCAB_COLUMN_MAPPING = {
        'TOEFL_BEGINNER': 'is_toefl_beginner',
        'TOEFL_INTERMEDIATE': 'is_toefl_intermediate',
        'TOEFL_ADVANCED': 'is_toefl_advanced',
        'IELTS_BEGINNER': 'is_ielts_beginner',
        'IELTS_INTERMEDIATE': 'is_ielts_intermediate',
        'IELTS_ADVANCED': 'is_ielts_advanced',
        'TIANZ': 'is_tianz',
        # Legacy mappings
        'TOEFL': 'is_toefl_advanced',
        'IELTS': 'is_ielts_advanced',
    }

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        if test_type == 'BOTH':
            # Legacy: both TOEFL and IELTS advanced
            cur.execute("""
                SELECT DISTINCT word
                FROM test_vocabularies
                WHERE language = 'en'
                AND (is_toefl_advanced = TRUE OR is_ielts_advanced = TRUE)
            """)
        elif test_type in VOCAB_COLUMN_MAPPING:
            # Level-based or simple test type
            vocab_column = VOCAB_COLUMN_MAPPING[test_type]
            cur.execute(f"""
                SELECT DISTINCT word
                FROM test_vocabularies
                WHERE language = 'en'
                AND {vocab_column} = TRUE
            """)
        else:
            valid_types = ', '.join(VOCAB_COLUMN_MAPPING.keys()) + ', BOTH'
            raise ValueError(f"Invalid test_type: {test_type}. Must be one of: {valid_types}")

        return set(row['word'] for row in cur.fetchall())
    finally:
        cur.close()
        conn.close()


def get_user_saved_words(user_id: str, learning_language: str = 'en',
                         exclude_date: date = None, timezone: str = None,
                         exclude_only_test_words: bool = False, test_type: str = None) -> Dict[str, Dict]:
    """
    Get all saved words for a user with their metadata.

    IMPORTANT: Words marked as is_known=TRUE are EXCLUDED from results.
    Known words should not appear in practice schedules or new word allocations.

    Args:
        user_id: UUID of the user
        learning_language: Language being learned (default: 'en')
        exclude_date: Optional date to exclude words saved on this date (in user's timezone)
        timezone: Required if exclude_date is provided - user's IANA timezone string
        exclude_only_test_words: If True, only exclude test vocabulary words saved on exclude_date
                                 (non-test words saved on that date will still be included)
        test_type: Required if exclude_only_test_words is True - 'TOEFL', 'IELTS', 'TIANZ', or 'BOTH'

    Returns:
        Dictionary mapping word -> {id, created_at, is_known}

    Example:
        >>> words = get_user_saved_words('user-uuid')
        >>> words['apple']
        {'id': 123, 'created_at': datetime(2025, 1, 1), 'is_known': False}
    """
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        if exclude_date and timezone:
            if exclude_only_test_words and test_type:
                # Only exclude TEST words saved on the specified date
                # Non-test words saved today are still included (they won't appear in new_words)
                # ALWAYS exclude words marked as is_known=TRUE
                cur.execute("""
                    SELECT sw.id, sw.word, sw.created_at, sw.is_known
                    FROM saved_words sw
                    LEFT JOIN test_vocabularies tv ON sw.word = tv.word
                    WHERE sw.user_id = %s
                      AND sw.learning_language = %s
                      AND sw.is_known = FALSE
                      AND (
                          -- Include if: NOT saved today, OR not a test word for user's test type
                          DATE(sw.created_at AT TIME ZONE 'UTC' AT TIME ZONE %s) != %s
                          OR NOT COALESCE(
                              (%s = 'TOEFL' AND tv.is_toefl = TRUE)
                              OR (%s = 'IELTS' AND tv.is_ielts = TRUE)
                              OR (%s = 'TIANZ' AND tv.is_tianz = TRUE)
                              OR (%s = 'BOTH' AND (tv.is_toefl = TRUE OR tv.is_ielts = TRUE)),
                              FALSE
                          )
                      )
                """, (user_id, learning_language, timezone, exclude_date, test_type, test_type, test_type, test_type))
            else:
                # Exclude ALL words saved on the specified date in user's timezone
                # ALWAYS exclude words marked as is_known=TRUE
                cur.execute("""
                    SELECT id, word, created_at, is_known
                    FROM saved_words
                    WHERE user_id = %s
                      AND learning_language = %s
                      AND is_known = FALSE
                      AND DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE %s) != %s
                """, (user_id, learning_language, timezone, exclude_date))
        else:
            # ALWAYS exclude words marked as is_known=TRUE
            cur.execute("""
                SELECT id, word, created_at, is_known
                FROM saved_words
                WHERE user_id = %s
                  AND learning_language = %s
                  AND is_known = FALSE
            """, (user_id, learning_language))

        return {
            row['word']: {
                'id': row['id'],
                'created_at': row['created_at'],
                'is_known': row['is_known']
            }
            for row in cur.fetchall()
        }
    finally:
        cur.close()
        conn.close()


def get_word_review_history(word_id: int, exclude_date: date = None, timezone: str = None) -> List[Dict]:
    """
    Get complete review history for a specific word.

    Args:
        word_id: ID from saved_words table
        exclude_date: Optional date to exclude reviews from this date (in user's timezone)
        timezone: Required if exclude_date is provided - user's IANA timezone string

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
        if exclude_date and timezone:
            cur.execute("""
                SELECT reviewed_at, response
                FROM reviews
                WHERE word_id = %s
                  AND DATE(reviewed_at AT TIME ZONE 'UTC' AT TIME ZONE %s) != %s
                ORDER BY reviewed_at ASC
            """, (word_id, timezone, exclude_date))
        else:
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
    1. Fetches all required data from database
    2. Calls calc_schedule() to generate the schedule
    3. Saves the schedule to database

    Args:
        user_id: UUID of the user
        test_type: 'TOEFL', 'IELTS', 'TIANZ', or 'BOTH'
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

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Step 1: Fetch all required data from database
        # Get today in user's timezone
        user_tz = get_user_timezone(user_id)
        today = get_today_in_timezone(user_tz)

        # Get all test vocabulary words
        all_test_words = get_test_vocabulary_words(test_type)

        # Get ALL user's saved words for practice scheduling
        # We don't exclude any words here - practice scheduling needs all saved words with their review history
        # The exclusion of words saved/reviewed today happens in calc_schedule for new_words allocation
        # NOTE: This excludes words with is_known=TRUE
        saved_words_map = get_user_saved_words(
            user_id,
            exclude_date=None,  # Don't exclude anything for practice scheduling
            timezone=user_tz,
            exclude_only_test_words=False,  # Include all saved words
            test_type=test_type
        )

        # Also fetch ALL saved words (including known ones) for new_words_pool exclusion
        cur.execute("""
            SELECT word FROM saved_words
            WHERE user_id = %s AND learning_language = 'en'
        """, (user_id,))
        all_saved_words = {row['word'] for row in cur.fetchall()}

        # Build saved_words_with_reviews by fetching review history for each saved word
        # Note: saved_words_map already excludes words with is_known=TRUE
        saved_words_with_reviews = {}
        for word, info in saved_words_map.items():
            # Get review history for this word, INCLUDING today's reviews
            # If a review happened at 9am and schedule is generated at 10am,
            # that review should count towards calculating the next review date
            reviews = get_word_review_history(info['id'], exclude_date=None, timezone=user_tz)

            saved_words_with_reviews[word] = {
                'id': info['id'],
                'created_at': info['created_at'],
                'reviews': reviews,
                'is_known': info['is_known']  # Should always be False since we filter at DB level
            }

        # Get words saved/reviewed today - these should be excluded from tomorrow onwards
        words_saved_today = get_words_saved_on_date(user_id, today, user_tz)
        words_reviewed_today = get_words_reviewed_on_date(user_id, today, user_tz)

        # Step 2: Call calc_schedule() to generate the schedule
        schedule_result = calc_schedule(
            today=today,
            target_end_date=target_end_date,
            all_test_words=all_test_words,
            saved_words_with_reviews=saved_words_with_reviews,
            words_saved_today=words_saved_today,
            words_reviewed_today=words_reviewed_today,
            get_schedule_fn=get_schedule,
            all_saved_words=all_saved_words  # Include known words to exclude from new_words_pool
        )

        # Step 3: Save the schedule to database
        # Delete existing schedule first
        cur.execute("DELETE FROM study_schedules WHERE user_id = %s", (user_id,))

        # Insert new schedule
        cur.execute("""
            INSERT INTO study_schedules (user_id, test_type, target_end_date)
            VALUES (%s, %s, %s)
            RETURNING id
        """, (user_id, test_type, target_end_date))

        schedule_id = cur.fetchone()['id']

        # Insert daily entries
        for date_str, entry in schedule_result['daily_schedules'].items():
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

        # Return metadata with schedule_id added
        return {
            'schedule_id': schedule_id,
            'days_remaining': schedule_result['metadata']['days_remaining'],
            'total_new_words': schedule_result['metadata']['total_new_words'],
            'daily_new_words': schedule_result['metadata']['daily_new_words'],
            'test_practice_words_count': schedule_result['metadata']['test_practice_words_count'],
            'non_test_practice_words_count': schedule_result['metadata']['non_test_practice_words_count']
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
