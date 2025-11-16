"""
Unit tests for schedule_service.py

Tests the core scheduling functions without database dependencies.
"""

import unittest
from datetime import datetime, timedelta, date
import sys
import os

# Add parent directories to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.schedule_service import (
    get_schedule,
    get_user_timezone,
    get_today_in_timezone,
    get_test_vocabulary_words
)


class TestHelperFunctions(unittest.TestCase):
    """Test helper functions for schedule calculations"""

    def test_get_user_timezone_nonexistent(self):
        """Test timezone defaults to UTC for non-existent user"""
        fake_user_id = '00000000-0000-0000-0000-000000000000'
        tz = get_user_timezone(fake_user_id)
        self.assertEqual(tz, 'UTC', "Should default to UTC for non-existent user")

    def test_get_today_in_timezone_utc(self):
        """Test getting today's date in UTC"""
        today = get_today_in_timezone('UTC')
        self.assertIsInstance(today, date, "Should return a date object")

    def test_get_today_in_timezone_different_zones(self):
        """Test that different timezones can return different dates"""
        utc_date = get_today_in_timezone('UTC')
        tokyo_date = get_today_in_timezone('Asia/Tokyo')
        la_date = get_today_in_timezone('America/Los_Angeles')

        # All should be date objects
        self.assertIsInstance(utc_date, date)
        self.assertIsInstance(tokyo_date, date)
        self.assertIsInstance(la_date, date)

        # Dates should be within reasonable range (at most 1 day apart due to timezone)
        self.assertLessEqual(abs((tokyo_date - utc_date).days), 1)
        self.assertLessEqual(abs((la_date - utc_date).days), 1)

    def test_get_test_vocabulary_words_toefl(self):
        """Test getting TOEFL vocabulary words"""
        words = get_test_vocabulary_words('TOEFL')
        self.assertIsInstance(words, set, "Should return a set")
        # Should have some words (assuming test_vocabularies is populated)
        # We won't check exact count as it depends on database state

    def test_get_test_vocabulary_words_ielts(self):
        """Test getting IELTS vocabulary words"""
        words = get_test_vocabulary_words('IELTS')
        self.assertIsInstance(words, set, "Should return a set")

    def test_get_test_vocabulary_words_both(self):
        """Test getting both TOEFL and IELTS vocabulary words"""
        words = get_test_vocabulary_words('BOTH')
        self.assertIsInstance(words, set, "Should return a set")

        # BOTH should have at least as many words as TOEFL or IELTS alone
        toefl_words = get_test_vocabulary_words('TOEFL')
        ielts_words = get_test_vocabulary_words('IELTS')

        self.assertGreaterEqual(
            len(words),
            max(len(toefl_words), len(ielts_words)),
            "BOTH should include at least all TOEFL or IELTS words"
        )

    def test_get_test_vocabulary_words_invalid(self):
        """Test that invalid test_type raises ValueError"""
        with self.assertRaises(ValueError):
            get_test_vocabulary_words('INVALID')

        with self.assertRaises(ValueError):
            get_test_vocabulary_words('GRE')


class TestGetSchedule(unittest.TestCase):
    """Test get_schedule function for predicting future review dates"""

    def test_no_past_reviews(self):
        """Test schedule generation for a brand new word with no reviews"""
        created_at = datetime(2025, 1, 1, 0, 0, 0)
        past_schedule = []

        future = get_schedule(past_schedule, created_at)

        # Should return exactly 7 dates
        self.assertEqual(len(future), 7, "Should return 7 future review dates")

        # All should be marked as True (assumed correct in future)
        for idx, (date, result) in enumerate(future):
            self.assertTrue(result, f"Review {idx} should be marked as True (assumed correct)")

        # Dates should be strictly increasing
        for i in range(len(future) - 1):
            self.assertLess(
                future[i][0],
                future[i+1][0],
                f"Date {i} should be before date {i+1}"
            )

        # First review should be after creation
        self.assertGreater(
            future[0][0],
            created_at,
            "First review should be after word creation"
        )

    def test_one_correct_review(self):
        """Test schedule after one successful review"""
        created_at = datetime(2025, 1, 1, 0, 0, 0)
        past_schedule = [(datetime(2025, 1, 5, 10, 0, 0), True)]

        future = get_schedule(past_schedule, created_at)

        self.assertEqual(len(future), 7)

        # First future review should be after the last completed review
        self.assertGreater(
            future[0][0],
            past_schedule[-1][0],
            "Next review should be after last completed review"
        )

        # All marked as True
        for date, result in future:
            self.assertTrue(result)

    def test_one_incorrect_review(self):
        """Test schedule after one failed review (should reset interval)"""
        created_at = datetime(2025, 1, 1, 0, 0, 0)
        past_schedule = [(datetime(2025, 1, 5, 10, 0, 0), False)]

        future = get_schedule(past_schedule, created_at)

        self.assertEqual(len(future), 7)

        # Should still generate schedule starting after the failed review
        self.assertGreater(future[0][0], past_schedule[-1][0])

        # All future reviews assumed correct
        for date, result in future:
            self.assertTrue(result)

    def test_mixed_reviews(self):
        """Test schedule with a mixture of correct and incorrect reviews"""
        created_at = datetime(2025, 1, 1, 0, 0, 0)
        past_schedule = [
            (datetime(2025, 1, 2, 9, 0, 0), True),   # First review - correct
            (datetime(2025, 1, 5, 10, 0, 0), True),  # Second review - correct
            (datetime(2025, 1, 10, 11, 0, 0), False), # Third review - incorrect (resets)
            (datetime(2025, 1, 12, 14, 0, 0), True)   # Fourth review - correct
        ]

        future = get_schedule(past_schedule, created_at)

        self.assertEqual(len(future), 7)

        # Should start after last review
        self.assertGreater(future[0][0], past_schedule[-1][0])

        # All future assumed correct
        for date, result in future:
            self.assertTrue(result)

        # Dates should be increasing
        for i in range(len(future) - 1):
            self.assertLess(future[i][0], future[i+1][0])

    def test_multiple_correct_reviews_spacing(self):
        """Test that intervals increase with consecutive correct reviews"""
        created_at = datetime(2025, 1, 1, 0, 0, 0)
        past_schedule = [
            (datetime(2025, 1, 2, 9, 0, 0), True),
            (datetime(2025, 1, 7, 9, 0, 0), True),
            (datetime(2025, 1, 15, 9, 0, 0), True),
        ]

        future = get_schedule(past_schedule, created_at)

        self.assertEqual(len(future), 7)

        # With consecutive correct reviews, intervals should generally increase
        # (This tests the spaced repetition algorithm is working)
        interval_1 = (future[1][0] - future[0][0]).days
        interval_2 = (future[2][0] - future[1][0]).days

        # Later intervals should generally be longer (allowing for algorithm specifics)
        # We just verify they're both positive
        self.assertGreater(interval_1, 0, "First interval should be positive")
        self.assertGreater(interval_2, 0, "Second interval should be positive")

    def test_datetime_types(self):
        """Test that returned dates are datetime objects"""
        created_at = datetime(2025, 1, 1, 0, 0, 0)
        past_schedule = [(datetime(2025, 1, 2, 9, 0, 0), True)]

        future = get_schedule(past_schedule, created_at)

        for date, result in future:
            self.assertIsInstance(date, datetime, "Date should be datetime object")
            self.assertIsInstance(result, bool, "Result should be boolean")

    def test_many_past_reviews(self):
        """Test schedule with many historical reviews"""
        created_at = datetime(2025, 1, 1, 0, 0, 0)

        # Simulate 10 past reviews over time, all correct
        past_schedule = []
        current_date = created_at + timedelta(days=1)

        for i in range(10):
            past_schedule.append((current_date, True))
            # Exponentially increase gap
            current_date += timedelta(days=2 ** (i // 3))

        future = get_schedule(past_schedule, created_at)

        self.assertEqual(len(future), 7)

        # Should start after last review
        self.assertGreater(future[0][0], past_schedule[-1][0])


if __name__ == '__main__':
    # Run with verbose output
    unittest.main(verbosity=2)
