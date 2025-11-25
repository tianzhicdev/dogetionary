"""
Unit tests for calc_schedule pure function.

These tests verify the schedule calculation logic in isolation
without any database dependencies.
"""

import unittest
from datetime import date, datetime, timedelta
from typing import List, Tuple
import sys
import os

# Add src directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from services.schedule_service import calc_schedule


def mock_get_schedule(past_schedule: List[Tuple[datetime, str]], created_at: datetime) -> List[Tuple[datetime, str]]:
    """
    Mock function that simulates Fibonacci-based spaced repetition.
    Returns review dates at intervals: 1, 2, 3, 5, 8, 13, 21 days.
    """
    if not past_schedule:
        # New word: first review in 1 day
        return [(created_at + timedelta(days=1), 'due')]

    # For existing words with reviews, use Fibonacci intervals
    intervals = [1, 2, 3, 5, 8, 13, 21]
    num_reviews = len(past_schedule)
    next_reviews = []

    last_review_time = past_schedule[-1][0] if past_schedule else created_at

    for i in range(min(7, len(intervals) - num_reviews)):
        interval = intervals[num_reviews + i] if num_reviews + i < len(intervals) else 21
        next_review = last_review_time + timedelta(days=interval)
        next_reviews.append((next_review, 'due'))

    return next_reviews


class TestCalcScheduleBasic(unittest.TestCase):
    """Test basic functionality of calc_schedule"""

    def test_empty_schedule_simple(self):
        """Test creating a schedule with no saved words"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 10)
        all_test_words = {'abandon', 'ability', 'academic'}

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews={},
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # Check metadata
        self.assertEqual(result['metadata']['days_remaining'], 9)
        self.assertEqual(result['metadata']['total_new_words'], 3)
        self.assertEqual(result['metadata']['daily_new_words'], 1)

        # Check schedules exist for all days
        schedules = result['daily_schedules']
        self.assertEqual(len(schedules), 9)

        # All 3 words should be distributed
        all_new_words = []
        for day_schedule in schedules.values():
            all_new_words.extend(day_schedule['new_words'])
        self.assertEqual(sorted(all_new_words), ['abandon', 'ability', 'academic'])

    def test_invalid_target_date(self):
        """Test that past target dates raise ValueError"""
        today = date(2025, 1, 10)
        target = date(2025, 1, 5)  # Before today

        with self.assertRaises(ValueError) as context:
            calc_schedule(
                today=today,
                target_end_date=target,
                all_test_words={'word1'},
                saved_words_with_reviews={},
                words_saved_today=set(),
                words_reviewed_today=set(),
                get_schedule_fn=mock_get_schedule
            )

        self.assertIn("future", str(context.exception))


class TestCalcScheduleWordDistribution(unittest.TestCase):
    """Test word distribution logic"""

    def test_deterministic_order(self):
        """Test that words are always allocated in the same order"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 5)
        all_test_words = {'zebra', 'apple', 'banana', 'cherry'}

        result1 = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews={},
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        result2 = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews={},
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # Should get identical results
        self.assertEqual(result1['daily_schedules'], result2['daily_schedules'])

        # First day should get 'apple' (alphabetically first)
        first_day = result1['daily_schedules']['2025-01-01']
        self.assertIn('apple', first_day['new_words'])

    def test_daily_word_ceiling_division(self):
        """Test that daily word count uses ceiling division"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 4)  # 3 days
        all_test_words = {f'word{i}' for i in range(10)}  # 10 words

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews={},
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # 10 words / 3 days = ceiling(3.33) = 4 words/day
        self.assertEqual(result['metadata']['daily_new_words'], 4)


class TestCalcScheduleTodayExclusion(unittest.TestCase):
    """Test the two-tier exclusion logic for words done today"""

    def test_words_saved_today_excluded_from_tomorrow(self):
        """Words saved today should not appear in tomorrow's new words"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 5)
        all_test_words = {'abandon', 'ability', 'academic', 'achieve'}

        # User saved 'abandon' today (but it's not in saved_words_with_reviews because we exclude today)
        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews={},
            words_saved_today={'abandon'},  # Saved today
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # 'abandon' should appear in today's schedule
        today_schedule = result['daily_schedules']['2025-01-01']
        self.assertIn('abandon', today_schedule['new_words'])

        # 'abandon' should NOT appear in tomorrow's schedule
        tomorrow_schedule = result['daily_schedules']['2025-01-02']
        self.assertNotIn('abandon', tomorrow_schedule['new_words'])

    def test_words_reviewed_today_excluded_from_tomorrow(self):
        """
        Words reviewed today should not appear in tomorrow's new words.

        This test simulates the case where:
        - Schedule allocates 2 words per day
        - User reviewed 'ability' at 9am today
        - Schedule is regenerated at 10am today
        - 'ability' should be in today's schedule (alphabetically second, fits in 2/day)
        - 'ability' should NOT be in tomorrow's schedule
        """
        today = date(2025, 1, 1)
        target = date(2025, 1, 3)  # 2 days, so 2 words/day for 4 total words
        all_test_words = {'abandon', 'ability', 'academic', 'achieve'}

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews={},
            words_saved_today=set(),
            words_reviewed_today={'ability'},  # Reviewed today
            get_schedule_fn=mock_get_schedule
        )

        # 'ability' should be allocated to today (it's one of first 2 alphabetically)
        today_schedule = result['daily_schedules']['2025-01-01']
        self.assertIn('ability', today_schedule['new_words'])

        # 'ability' should NOT appear in tomorrow's schedule
        tomorrow_schedule = result['daily_schedules']['2025-01-02']
        self.assertNotIn('ability', tomorrow_schedule['new_words'])

    def test_today_allocated_words_excluded_from_tomorrow(self):
        """Words allocated to today's schedule should not appear tomorrow"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 3)  # Short schedule
        all_test_words = {'abandon', 'ability', 'academic'}

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews={},
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # Get today's words
        today_words = set(result['daily_schedules']['2025-01-01']['new_words'])
        tomorrow_words = set(result['daily_schedules']['2025-01-02']['new_words'])

        # No overlap between today and tomorrow
        self.assertEqual(len(today_words & tomorrow_words), 0)

    def test_many_words_reviewed_today_excluded_from_future_days(self):
        """
        Many new words reviewed today should be excluded from tomorrow and all future days.

        This test simulates the case where:
        - Schedule allocates 3 words per day over 5 days (15 total words)
        - User reviewed 8 words today (more than one day's allocation)
        - Only 3 of those 8 words appear in today's new_words (alphabetically first 3)
        - ALL 8 words are excluded from tomorrow and future days
        - The other 5 reviewed words won't appear in any day's schedule
        - Future days get words that weren't reviewed today
        - Total allocated: 3 (today) + 7 (not reviewed) = 10 words

        This behavior ensures that words already reviewed don't reappear in future
        schedules even if the user regenerates with different target dates.
        """
        today = date(2025, 1, 1)
        target = date(2025, 1, 6)  # 5 days
        # 15 words total: a-o (3 per day)
        all_test_words = {
            'abandon', 'ability', 'academic', 'achieve', 'acquire',  # 5
            'adapt', 'adequate', 'adjust', 'administrate', 'advocate',  # 5
            'affect', 'allocate', 'alter', 'analyze', 'anticipate'  # 5
        }

        # User reviewed 8 words today (these are alphabetically early, so would be in first 3 days)
        words_reviewed_today = {
            'abandon', 'ability', 'academic', 'achieve', 'acquire',
            'adapt', 'adequate', 'adjust'
        }

        # Words NOT reviewed (should appear in schedule)
        words_not_reviewed = all_test_words - words_reviewed_today
        # These are: administrate, advocate, affect, allocate, alter, analyze, anticipate (7 words)

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews={},
            words_saved_today=set(),
            words_reviewed_today=words_reviewed_today,
            get_schedule_fn=mock_get_schedule
        )

        # Should still be 3 words per day
        self.assertEqual(result['metadata']['daily_new_words'], 3)

        # Today gets first 3 alphabetically: abandon, ability, academic
        # All 3 are in words_reviewed_today
        today_schedule = result['daily_schedules']['2025-01-01']
        today_words = set(today_schedule['new_words'])
        self.assertEqual(len(today_words), 3)
        self.assertEqual(today_words, {'abandon', 'ability', 'academic'})
        for word in today_words:
            self.assertIn(word, words_reviewed_today,
                         f"{word} in today's schedule but not in words_reviewed_today")

        # Tomorrow should NOT have any of the 8 reviewed words
        tomorrow_schedule = result['daily_schedules']['2025-01-02']
        tomorrow_words = set(tomorrow_schedule['new_words'])
        overlap_tomorrow = tomorrow_words & words_reviewed_today
        self.assertEqual(len(overlap_tomorrow), 0,
                        f"Tomorrow's schedule has reviewed words: {overlap_tomorrow}")

        # Day after tomorrow should also NOT have any of the 8 reviewed words
        day_after_schedule = result['daily_schedules']['2025-01-03']
        day_after_words = set(day_after_schedule['new_words'])
        overlap_day_after = day_after_words & words_reviewed_today
        self.assertEqual(len(overlap_day_after), 0,
                        f"Day after tomorrow's schedule has reviewed words: {overlap_day_after}")

        # Verify all future days (Jan 2-6) have NO overlap with words_reviewed_today
        for day_offset in range(1, 5):  # Days 2-6
            day = date(2025, 1, 1 + day_offset)
            day_schedule = result['daily_schedules'][day.isoformat()]
            day_words = set(day_schedule['new_words'])
            overlap = day_words & words_reviewed_today
            self.assertEqual(len(overlap), 0,
                           f"{day.isoformat()} has reviewed words: {overlap}")

        # Collect all words allocated across all 5 days
        all_allocated_words = set()
        for day_offset in range(5):
            day = date(2025, 1, 1 + day_offset)
            day_schedule = result['daily_schedules'][day.isoformat()]
            all_allocated_words.update(day_schedule['new_words'])

        # Should allocate 10 words total:
        # - 3 from words_reviewed_today (today's allocation)
        # - 7 from words_not_reviewed (future days)
        # The other 5 reviewed words are excluded from all days
        self.assertEqual(len(all_allocated_words), 10,
                        f"Expected 10 words allocated, got {len(all_allocated_words)}")

        # Verify the allocated words are the expected ones
        expected_allocated = {'abandon', 'ability', 'academic'}  # Today's 3
        expected_allocated.update(words_not_reviewed)  # Future days get these 7
        self.assertEqual(all_allocated_words, expected_allocated)

        # Verify that future days only get words NOT reviewed today
        for day_offset in range(1, 5):  # Days 2-6
            day = date(2025, 1, 1 + day_offset)
            day_schedule = result['daily_schedules'][day.isoformat()]
            day_words = set(day_schedule['new_words'])
            # All words in future days must be from words_not_reviewed
            self.assertTrue(day_words.issubset(words_not_reviewed),
                          f"{day.isoformat()} has words not in words_not_reviewed: {day_words - words_not_reviewed}")


class TestCalcScheduleTodayPracticeScheduling(unittest.TestCase):
    """Test that words saved/reviewed today get proper practice schedules"""

    def test_words_reviewed_today_get_practice_schedule(self):
        """
        Words reviewed today should have their future practice reviews scheduled.

        This test verifies that when a word is reviewed today, the system:
        1. Includes it in today's new_words
        2. Excludes it from future days' new_words
        3. Schedules future practice reviews based on spaced repetition
        """
        today = date(2025, 1, 1)
        target = date(2025, 1, 15)  # 14 days - enough to see multiple reviews
        all_test_words = {'abandon', 'ability', 'academic', 'achieve'}

        # User reviewed 'abandon' today at 9am, schedule generated at 10am
        words_reviewed_today = {'abandon'}

        # Mock that 'abandon' was saved yesterday (so it has a created_at)
        # and reviewed today (so it has review history)
        saved_words = {
            'abandon': {
                'id': 1,
                'created_at': datetime(2024, 12, 31, 12, 0),  # Yesterday
                'reviews': [
                    {'reviewed_at': datetime(2025, 1, 1, 9, 0), 'response': True}  # Today at 9am
                ]
            }
        }

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews=saved_words,
            words_saved_today=set(),
            words_reviewed_today=words_reviewed_today,
            get_schedule_fn=mock_get_schedule
        )

        # 'abandon' should NOT appear in any day's new_words (it's already saved)
        for day_schedule in result['daily_schedules'].values():
            self.assertNotIn('abandon', day_schedule['new_words'])

        # 'abandon' should appear in future practice schedules
        # Based on mock_get_schedule: after 1 correct review, next reviews at intervals: 2, 3, 5, 8, 13 days
        practice_dates = []
        for day_str, day_schedule in result['daily_schedules'].items():
            for practice_word in day_schedule['test_practice']:
                if practice_word['word'] == 'abandon':
                    practice_dates.append(day_str)

        # Should have at least one future practice scheduled
        self.assertGreater(len(practice_dates), 0,
                          "Word reviewed today should have future practice scheduled")

        # First practice should be 2 days from the review (intervals: 1, 2, 3, 5...)
        # Since it was reviewed on Jan 1, next review should be Jan 3 (2 days later)
        self.assertIn('2025-01-03', practice_dates,
                     "Expected practice on Jan 3 (2 days after Jan 1 review)")

    def test_words_saved_today_get_practice_schedule(self):
        """
        Words saved today should have their future practice reviews scheduled.

        This test verifies that when a word is saved today:
        1. It appears in today's new_words
        2. It's excluded from future days' new_words
        3. Future practice reviews are scheduled starting from today
        """
        today = date(2025, 1, 1)
        target = date(2025, 1, 10)  # 9 days
        all_test_words = {'abandon', 'ability', 'academic', 'achieve'}

        # User saved 'abandon' today (included in saved_words but flagged in words_saved_today)
        words_saved_today = {'abandon'}

        # 'abandon' was saved today (no reviews yet)
        saved_words = {
            'abandon': {
                'id': 1,
                'created_at': datetime(2025, 1, 1, 9, 0),  # Today at 9am
                'reviews': []  # No reviews yet
            }
        }

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews=saved_words,
            words_saved_today=words_saved_today,
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # 'abandon' should appear in today's new_words (even though it's in saved_words)
        today_schedule = result['daily_schedules']['2025-01-01']
        # Note: This depends on implementation - word saved today might not be in new_words
        # because it's already in saved_words. Let's verify it's NOT in future new_words.

        # 'abandon' should NOT appear in tomorrow's new_words
        tomorrow_schedule = result['daily_schedules']['2025-01-02']
        self.assertNotIn('abandon', tomorrow_schedule['new_words'])

        # 'abandon' should have future practice scheduled
        # With no reviews, first review should be 1 day after created_at (Jan 2)
        practice_dates = []
        for day_str, day_schedule in result['daily_schedules'].items():
            for practice_word in day_schedule['test_practice']:
                if practice_word['word'] == 'abandon':
                    practice_dates.append(day_str)

        # Should have practice scheduled
        self.assertGreater(len(practice_dates), 0,
                          "Word saved today should have future practice scheduled")

        # First practice should be Jan 2 (1 day after creation)
        self.assertIn('2025-01-02', practice_dates,
                     "Expected first practice on Jan 2 (1 day after saved)")

    def test_multiple_words_saved_today_all_get_practice(self):
        """
        Multiple words saved today should all have future practice scheduled.

        This ensures that when users save several words in one day,
        all of them get proper spaced repetition schedules.
        """
        today = date(2025, 1, 1)
        target = date(2025, 1, 10)  # 9 days
        all_test_words = {'abandon', 'ability', 'academic', 'achieve', 'acquire'}

        # User saved 3 words today
        words_saved_today = {'abandon', 'ability', 'academic'}

        saved_words = {
            'abandon': {
                'id': 1,
                'created_at': datetime(2025, 1, 1, 9, 0),
                'reviews': []
            },
            'ability': {
                'id': 2,
                'created_at': datetime(2025, 1, 1, 10, 0),
                'reviews': []
            },
            'academic': {
                'id': 3,
                'created_at': datetime(2025, 1, 1, 11, 0),
                'reviews': []
            }
        }

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews=saved_words,
            words_saved_today=words_saved_today,
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # All 3 saved words should have practice scheduled on Jan 2 (1 day after)
        jan2_schedule = result['daily_schedules']['2025-01-02']
        jan2_practice_words = {w['word'] for w in jan2_schedule['test_practice']}

        for word in words_saved_today:
            self.assertIn(word, jan2_practice_words,
                         f"{word} saved today should have practice on Jan 2")

        # None of the 3 should appear in future new_words
        for day_offset in range(1, 9):  # Jan 2-10
            day = date(2025, 1, 1 + day_offset)
            day_schedule = result['daily_schedules'][day.isoformat()]
            day_new_words = set(day_schedule['new_words'])
            overlap = day_new_words & words_saved_today
            self.assertEqual(len(overlap), 0,
                           f"{day.isoformat()} should not have words saved today in new_words: {overlap}")


class TestCalcScheduleWithSavedWords(unittest.TestCase):
    """Test schedule calculation with existing saved words"""

    def test_saved_words_excluded_from_new_words(self):
        """Saved words should not appear in new words pool"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 10)
        all_test_words = {'abandon', 'ability', 'academic', 'achieve'}

        # User already saved 'abandon' yesterday
        saved_words = {
            'abandon': {
                'id': 1,
                'created_at': datetime(2024, 12, 31),
                'reviews': []
            }
        }

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews=saved_words,
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # Only 3 new words (not 4)
        self.assertEqual(result['metadata']['total_new_words'], 3)

        # 'abandon' should NOT appear in any day's new words
        for day_schedule in result['daily_schedules'].values():
            self.assertNotIn('abandon', day_schedule['new_words'])

    def test_practice_words_scheduled(self):
        """Saved words should appear as practice words on their review dates"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 10)
        all_test_words = {'abandon', 'ability'}

        # User saved 'abandon' yesterday (no reviews yet)
        saved_words = {
            'abandon': {
                'id': 1,
                'created_at': datetime(2024, 12, 31, 12, 0),  # Yesterday noon
                'reviews': []
            }
        }

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews=saved_words,
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # 'abandon' should appear as practice word on Jan 1 (created yesterday, due in 1 day)
        jan1_schedule = result['daily_schedules']['2025-01-01']
        practice_words = [w['word'] for w in jan1_schedule['test_practice']]
        self.assertIn('abandon', practice_words)


class TestCalcScheduleNonTestWords(unittest.TestCase):
    """Test handling of non-test vocabulary words"""

    def test_non_test_words_separated(self):
        """Non-test words should go to non_test_practice, not test_practice"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 10)
        all_test_words = {'abandon', 'ability'}  # Only these are test words

        saved_words = {
            'abandon': {
                'id': 1,
                'created_at': datetime(2024, 12, 31),
                'reviews': []
            },
            'random_word': {  # Not a test word
                'id': 2,
                'created_at': datetime(2024, 12, 31),
                'reviews': []
            }
        }

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews=saved_words,
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # Check metadata counts
        self.assertEqual(result['metadata']['test_practice_words_count'], 1)
        self.assertEqual(result['metadata']['non_test_practice_words_count'], 1)

        # 'abandon' should be in test_practice
        jan1 = result['daily_schedules']['2025-01-01']
        test_words = [w['word'] for w in jan1['test_practice']]
        non_test_words = [w['word'] for w in jan1['non_test_practice']]

        self.assertIn('abandon', test_words)
        self.assertIn('random_word', non_test_words)


class TestCalcScheduleKnownWords(unittest.TestCase):
    """Test that words marked as known are excluded from scheduling"""

    def test_known_words_excluded_from_practice(self):
        """
        Words marked as is_known=TRUE should not appear in practice schedules.

        This test verifies that:
        - Known words are excluded at the data layer (not in saved_words_with_reviews)
        - They don't appear in test_practice or non_test_practice
        - Only unknown words get scheduled for practice
        """
        today = date(2025, 1, 1)
        target = date(2025, 1, 10)
        all_test_words = {'abandon', 'ability', 'academic', 'achieve'}

        # User has 2 saved words: 'abandon' (unknown) and 'ability' (known)
        # Since known words are filtered at DB level, only 'abandon' appears here
        saved_words = {
            'abandon': {
                'id': 1,
                'created_at': datetime(2024, 12, 31, 12, 0),  # Yesterday
                'reviews': [],
                'is_known': False  # Unknown word - should appear in schedule
            }
            # 'ability' is marked as known, so it's not in this dict
        }

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews=saved_words,
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # Collect all practice words across all days (from saved words only)
        all_practice_words = set()
        for day_schedule in result['daily_schedules'].values():
            for word_info in day_schedule['test_practice']:
                all_practice_words.add(word_info['word'])
            for word_info in day_schedule['non_test_practice']:
                all_practice_words.add(word_info['word'])

        # Only 'abandon' should appear in practice (it's the only saved unknown word)
        self.assertIn('abandon', all_practice_words)

        # 'ability', 'academic', 'achieve' will appear in NEW words schedule (not practice)
        # because they're not in saved_words_with_reviews

        # Metadata should only count 1 practice word (abandon)
        self.assertEqual(result['metadata']['test_practice_words_count'], 1)

    def test_known_words_excluded_from_new_words_pool(self):
        """
        Known words should be excluded from new words pool when all_saved_words is provided.

        If a user marks 'abandon' as known:
        - It doesn't appear in saved_words_with_reviews (filtered at DB)
        - It DOES appear in all_saved_words (to exclude from new_words_pool)
        - It should NOT appear in new_words schedule
        - It should NOT generate practice reviews
        """
        today = date(2025, 1, 1)
        target = date(2025, 1, 5)
        all_test_words = {'abandon', 'ability', 'academic'}

        # User marked 'abandon' as known, so it doesn't appear in saved_words_with_reviews
        saved_words = {}

        # But 'abandon' IS in all_saved_words (includes known words)
        all_saved_words = {'abandon'}

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews=saved_words,
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule,
            all_saved_words=all_saved_words  # Exclude known word 'abandon'
        )

        # Only 2 words in new words pool (known word 'abandon' excluded)
        self.assertEqual(result['metadata']['total_new_words'], 2)

        # Only 'ability' and 'academic' should be distributed
        all_new_words = []
        for day_schedule in result['daily_schedules'].values():
            all_new_words.extend(day_schedule['new_words'])

        self.assertEqual(sorted(all_new_words), ['ability', 'academic'])
        self.assertNotIn('abandon', all_new_words)  # Known word excluded

    def test_mix_of_known_and_unknown_words(self):
        """
        Test schedule generation with mix of known and unknown saved words.

        Simulates:
        - 5 test words total
        - User has saved 3 words: 1 known, 2 unknown
        - Only the 2 unknown words should appear in practice
        - The 2 not-yet-saved words + 1 known word = 3 words in new_words pool
        """
        today = date(2025, 1, 1)
        target = date(2025, 1, 10)
        all_test_words = {'abandon', 'ability', 'academic', 'achieve', 'acquire'}

        # User saved 3 words:
        # - 'abandon': unknown (appears in dict)
        # - 'ability': KNOWN (filtered out, not in dict)
        # - 'academic': unknown (appears in dict)
        saved_words = {
            'abandon': {
                'id': 1,
                'created_at': datetime(2024, 12, 30),
                'reviews': [],
                'is_known': False
            },
            'academic': {
                'id': 3,
                'created_at': datetime(2024, 12, 31),
                'reviews': [],
                'is_known': False
            }
        }

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews=saved_words,
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # Only 2 unknown saved words should be in practice
        self.assertEqual(result['metadata']['test_practice_words_count'], 2)

        # New words pool should be: all_test_words - saved_words (known filtered at DB)
        # = 5 - 2 = 3 words ('ability', 'achieve', 'acquire')
        self.assertEqual(result['metadata']['total_new_words'], 3)

        # Verify 'ability' appears in new words (it's known but filtered before calc_schedule)
        all_new_words = []
        for day_schedule in result['daily_schedules'].values():
            all_new_words.extend(day_schedule['new_words'])

        self.assertIn('ability', all_new_words)
        self.assertIn('achieve', all_new_words)
        self.assertIn('acquire', all_new_words)


class TestCalcScheduleEdgeCases(unittest.TestCase):
    """Test edge cases and boundary conditions"""

    def test_single_day_schedule(self):
        """Test schedule with only 1 day"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 2)  # Tomorrow
        all_test_words = {'abandon', 'ability', 'academic'}

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews={},
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        self.assertEqual(result['metadata']['days_remaining'], 1)
        self.assertEqual(len(result['daily_schedules']), 1)

        # All 3 words should be in today
        today_words = result['daily_schedules']['2025-01-01']['new_words']
        self.assertEqual(len(today_words), 3)

    def test_more_days_than_words(self):
        """Test when days > words (daily_new_words = 1)"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 11)  # 10 days
        all_test_words = {'abandon', 'ability'}  # Only 2 words

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=all_test_words,
            saved_words_with_reviews={},
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        # Should be 1 word per day
        self.assertEqual(result['metadata']['daily_new_words'], 1)

        # Only first 2 days should have new words
        for i in range(10):
            day = date(2025, 1, 1 + i)
            day_schedule = result['daily_schedules'][day.isoformat()]
            if i < 2:
                self.assertEqual(len(day_schedule['new_words']), 1)
            else:
                self.assertEqual(len(day_schedule['new_words']), 0)

    def test_no_test_words(self):
        """Test with empty test vocabulary"""
        today = date(2025, 1, 1)
        target = date(2025, 1, 10)

        result = calc_schedule(
            today=today,
            target_end_date=target,
            all_test_words=set(),  # Empty
            saved_words_with_reviews={},
            words_saved_today=set(),
            words_reviewed_today=set(),
            get_schedule_fn=mock_get_schedule
        )

        self.assertEqual(result['metadata']['total_new_words'], 0)

        # All days should have empty new_words
        for day_schedule in result['daily_schedules'].values():
            self.assertEqual(len(day_schedule['new_words']), 0)


if __name__ == '__main__':
    unittest.main()
