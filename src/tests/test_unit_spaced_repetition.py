#!/usr/bin/env python3

import unittest
import sys
import os
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock

# Add the src directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from services.spaced_repetition_service import (
    calculate_spaced_repetition, get_decay_rate
)

# Set environment variable before importing app
import os
os.environ.setdefault('OPENAI_API_KEY', 'test-key-for-unit-tests')

# Import functions from the original app for testing
from app import (
    calculate_retention, get_next_review_date_new, get_due_words_count
)

class TestSpacedRepetitionService(unittest.TestCase):
    """Unit tests for spaced repetition business logic"""

    def setUp(self):
        """Set up test fixtures"""
        self.base_time = datetime(2024, 1, 1, 12, 0, 0)
        self.test_reviews = [
            {'reviewed_at': self.base_time, 'response': True},
            {'reviewed_at': self.base_time + timedelta(days=1), 'response': True},
            {'reviewed_at': self.base_time + timedelta(days=2), 'response': False},
            {'reviewed_at': self.base_time + timedelta(days=3), 'response': True}
        ]

    def test_calculate_spaced_repetition_empty_reviews(self):
        """Test spaced repetition calculation with no reviews"""
        review_count, interval_days, next_review, last_reviewed = calculate_spaced_repetition([])

        self.assertEqual(review_count, 0)
        self.assertEqual(interval_days, 1)
        self.assertIsNone(last_reviewed)
        # next_review should be tomorrow
        self.assertIsInstance(next_review, datetime)

    def test_calculate_spaced_repetition_with_reviews(self):
        """Test spaced repetition calculation with review history"""
        review_count, interval_days, next_review, last_reviewed = calculate_spaced_repetition(
            self.test_reviews.copy()
        )

        self.assertEqual(review_count, 4)
        self.assertEqual(interval_days, 5)  # Updated to match new logic
        self.assertEqual(last_reviewed, self.test_reviews[-1]['reviewed_at'])
        self.assertIsInstance(next_review, datetime)

    def test_calculate_spaced_repetition_consecutive_correct(self):
        """Test spaced repetition with consecutive correct answers"""
        consecutive_correct_reviews = [
            {'reviewed_at': self.base_time, 'response': True},
            {'reviewed_at': self.base_time + timedelta(days=5), 'response': True},
            {'reviewed_at': self.base_time + timedelta(days=10), 'response': True}
        ]

        review_count, interval_days, next_review, last_reviewed = calculate_spaced_repetition(
            consecutive_correct_reviews.copy()
        )

        self.assertEqual(review_count, 3)
        # Should use 2.5 * time_diff_days calculation
        expected_interval = max(1, int(2.5 * 5))  # 5 days between last two reviews
        self.assertEqual(interval_days, expected_interval)

    def test_calculate_spaced_repetition_last_incorrect(self):
        """Test spaced repetition when last review was incorrect"""
        incorrect_last = [
            {'reviewed_at': self.base_time, 'response': True},
            {'reviewed_at': self.base_time + timedelta(days=1), 'response': False}
        ]

        review_count, interval_days, next_review, last_reviewed = calculate_spaced_repetition(
            incorrect_last.copy()
        )

        self.assertEqual(review_count, 2)
        self.assertEqual(interval_days, 1)  # Reset to 1 day for incorrect answer

    def test_get_decay_rate_week_1(self):
        """Test decay rate calculation for week 1"""
        # Days 0-6 should return DECAY_RATE_WEEK_1
        for days in [0, 1, 3, 6]:
            rate = get_decay_rate(days)
            self.assertEqual(rate, 0.45)  # DECAY_RATE_WEEK_1

    def test_get_decay_rate_week_2(self):
        """Test decay rate calculation for week 2"""
        # Days 7-13 should return DECAY_RATE_WEEK_2
        for days in [7, 10, 13]:
            rate = get_decay_rate(days)
            self.assertEqual(rate, 0.18)  # DECAY_RATE_WEEK_2

    def test_get_decay_rate_week_3_4(self):
        """Test decay rate calculation for weeks 3-4"""
        # Days 14-27 should return DECAY_RATE_WEEK_3_4
        for days in [14, 20, 27]:
            rate = get_decay_rate(days)
            self.assertEqual(rate, 0.09)  # DECAY_RATE_WEEK_3_4

    def test_get_decay_rate_week_5_8(self):
        """Test decay rate calculation for weeks 5-8"""
        # Days 28-55 should return DECAY_RATE_WEEK_5_8
        for days in [28, 40, 55]:
            rate = get_decay_rate(days)
            self.assertEqual(rate, 0.035)  # DECAY_RATE_WEEK_5_8

    def test_get_decay_rate_week_9_plus(self):
        """Test decay rate calculation for weeks 9+"""
        # Days 56-111 should return DECAY_RATE_WEEK_9_PLUS
        for days in [56, 80, 111]:
            rate = get_decay_rate(days)
            self.assertEqual(rate, 0.015)  # DECAY_RATE_WEEK_9_PLUS

    def test_get_decay_rate_extended_periods(self):
        """Test decay rate calculation for very long periods (halving)"""
        # Days > 112 should halve the rate progressively
        rate_224 = get_decay_rate(224)  # 2 * 112
        rate_448 = get_decay_rate(448)  # 4 * 112

        # Rate should halve
        self.assertEqual(rate_224, 0.015 / 2)
        self.assertEqual(rate_448, 0.015 / 4)

    def test_calculate_retention_no_reviews(self):
        """Test retention calculation with no review history"""
        created_at = self.base_time
        target_date = self.base_time + timedelta(days=1)

        retention = calculate_retention([], target_date, created_at)

        # Should start at 100% and decay based on time
        self.assertLess(retention, 1.0)
        self.assertGreater(retention, 0.0)

    def test_calculate_retention_same_day_creation(self):
        """Test retention calculation on same day as creation"""
        created_at = self.base_time
        target_date = self.base_time  # Same day

        retention = calculate_retention([], target_date, created_at)

        self.assertEqual(retention, 1.0)  # 100% on creation day

    def test_calculate_retention_before_creation(self):
        """Test retention calculation before word creation"""
        created_at = self.base_time
        target_date = self.base_time - timedelta(days=1)  # Before creation

        retention = calculate_retention([], target_date, created_at)

        self.assertEqual(retention, 0.0)  # No retention before creation

    def test_calculate_retention_with_reviews(self):
        """Test retention calculation with review history"""
        created_at = self.base_time
        target_date = self.base_time + timedelta(days=5)
        reviews = [
            {'reviewed_at': self.base_time + timedelta(days=1), 'response': True},
            {'reviewed_at': self.base_time + timedelta(days=3), 'response': False}
        ]

        retention = calculate_retention(reviews, target_date, created_at)

        # Should be between 0 and 1
        self.assertGreaterEqual(retention, 0.0)
        self.assertLessEqual(retention, 1.0)

    def test_get_next_review_date_new_no_reviews(self):
        """Test next review date calculation with no reviews"""
        created_at = self.base_time

        next_review = get_next_review_date_new([], created_at)

        # Should return a future date
        self.assertIsInstance(next_review, datetime)
        self.assertGreater(next_review, created_at)

    def test_get_next_review_date_new_with_reviews(self):
        """Test next review date calculation with review history"""
        created_at = self.base_time
        reviews = [
            {'reviewed_at': self.base_time + timedelta(days=1), 'response': True}
        ]

        next_review = get_next_review_date_new(reviews, created_at)

        # Should return a date after the last review
        self.assertIsInstance(next_review, datetime)
        self.assertGreater(next_review, reviews[-1]['reviewed_at'])

    @patch('app.get_db_connection')
    def test_get_due_words_count(self, mock_db_connection):
        """Test due words count calculation"""
        # Mock database response
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_db_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        # Mock query result
        mock_cursor.fetchone.return_value = {
            'total_count': 10,
            'due_count': 3
        }

        result = get_due_words_count('test-user-id')

        # Verify the result structure
        self.assertIsInstance(result, dict)
        self.assertIn('total_count', result)
        self.assertIn('due_count', result)
        self.assertEqual(result['total_count'], 10)
        self.assertEqual(result['due_count'], 3)

        # Verify database calls
        mock_db_connection.assert_called_once()
        mock_conn.cursor.assert_called_once()
        mock_cursor.execute.assert_called_once()
        mock_cursor.close.assert_called_once()

    def test_review_sorting(self):
        """Test that reviews are sorted by date in calculate_spaced_repetition"""
        unsorted_reviews = [
            {'reviewed_at': self.base_time + timedelta(days=2), 'response': True},
            {'reviewed_at': self.base_time, 'response': True},
            {'reviewed_at': self.base_time + timedelta(days=1), 'response': False}
        ]

        review_count, interval_days, next_review, last_reviewed = calculate_spaced_repetition(
            unsorted_reviews.copy()
        )

        # Should process the latest review (day 2) as the last one
        self.assertEqual(last_reviewed, self.base_time + timedelta(days=2))
        self.assertEqual(review_count, 3)

    def test_edge_case_single_review(self):
        """Test spaced repetition with single review"""
        single_review = [
            {'reviewed_at': self.base_time, 'response': True}
        ]

        review_count, interval_days, next_review, last_reviewed = calculate_spaced_repetition(
            single_review.copy()
        )

        self.assertEqual(review_count, 1)
        self.assertEqual(interval_days, 5)  # Single correct review should give 5 days
        self.assertEqual(last_reviewed, self.base_time)

if __name__ == '__main__':
    # Run the tests
    unittest.main(verbosity=2)