"""
Achievements Handler

This module provides functions to:
- Calculate achievement progress based on score (from reviews)
- Score formula: failed review = 1 point, success review = 2 points
- Return unlocked achievements and next milestone
"""

from flask import jsonify, request
import sys
import os
import uuid
import logging

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utils.database import db_fetch_one

logger = logging.getLogger(__name__)

# Achievement milestones with metadata (score-based, 10x original word thresholds)
ACHIEVEMENTS = [
    # Entry Level
    {"milestone": 1, "title": "Getting Started", "symbol": "sparkle", "tier": "beginner", "is_award": False},

    # Beginner Tier
    {"milestone": 100, "title": "First Steps", "symbol": "leaf.fill", "tier": "beginner", "is_award": False},
    {"milestone": 300, "title": "Growing", "symbol": "leaf.circle.fill", "tier": "beginner", "is_award": False},
    {"milestone": 500, "title": "Blooming", "symbol": "sparkles", "tier": "beginner", "is_award": False},
    {"milestone": 1000, "title": "Century", "symbol": "star.fill", "tier": "beginner", "is_award": False},

    # Intermediate Tier
    {"milestone": 1500, "title": "On Fire", "symbol": "flame.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 2000, "title": "Gem Collector", "symbol": "gem.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 2500, "title": "Champion", "symbol": "trophy.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 3000, "title": "Royalty", "symbol": "crown.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 3500, "title": "Sharpshooter", "symbol": "target", "tier": "intermediate", "is_award": False},
    {"milestone": 4000, "title": "Soaring", "symbol": "paperplane.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 4500, "title": "Lightning", "symbol": "bolt.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 5000, "title": "Word Master", "symbol": "medal.fill", "tier": "intermediate", "is_award": True},

    # Advanced Tier
    {"milestone": 6000, "title": "Rising Star", "symbol": "star.circle.fill", "tier": "advanced", "is_award": False},
    {"milestone": 7000, "title": "Brilliant", "symbol": "sparkle", "tier": "advanced", "is_award": False},
    {"milestone": 8000, "title": "Mystical", "symbol": "moon.stars.fill", "tier": "advanced", "is_award": False},
    {"milestone": 9000, "title": "Magical", "symbol": "wand.and.stars", "tier": "advanced", "is_award": False},
    {"milestone": 10000, "title": "Grand Master", "symbol": "rosette", "tier": "advanced", "is_award": True},

    # Expert Tier
    {"milestone": 15000, "title": "Legendary", "symbol": "sparkles.rectangle.stack.fill", "tier": "expert", "is_award": True},
    {"milestone": 20000, "title": "Vocabulary God", "symbol": "crown.fill", "tier": "expert", "is_award": True},
]

# Test types mapping with metadata (Phase 1 & 3)
TEST_TYPES_MAPPING = {
    'TOEFL_BEGINNER': {
        'vocab_column': 'is_toefl_beginner',
        'pref_column': 'toefl_beginner_enabled',
        'title': 'TOEFL Beginner Master',
        'description': 'TOEFL Beginner vocabulary completed!'
    },
    'TOEFL_INTERMEDIATE': {
        'vocab_column': 'is_toefl_intermediate',
        'pref_column': 'toefl_intermediate_enabled',
        'title': 'TOEFL Intermediate Master',
        'description': 'TOEFL Intermediate vocabulary completed!'
    },
    'TOEFL_ADVANCED': {
        'vocab_column': 'is_toefl_advanced',
        'pref_column': 'toefl_advanced_enabled',
        'title': 'TOEFL Advanced Master',
        'description': 'TOEFL Advanced vocabulary completed!'
    },
    'IELTS_BEGINNER': {
        'vocab_column': 'is_ielts_beginner',
        'pref_column': 'ielts_beginner_enabled',
        'title': 'IELTS Beginner Master',
        'description': 'IELTS Beginner vocabulary completed!'
    },
    'IELTS_INTERMEDIATE': {
        'vocab_column': 'is_ielts_intermediate',
        'pref_column': 'ielts_intermediate_enabled',
        'title': 'IELTS Intermediate Master',
        'description': 'IELTS Intermediate vocabulary completed!'
    },
    'IELTS_ADVANCED': {
        'vocab_column': 'is_ielts_advanced',
        'pref_column': 'ielts_advanced_enabled',
        'title': 'IELTS Advanced Master',
        'description': 'IELTS Advanced vocabulary completed!'
    },
    'DEMO': {
        'vocab_column': 'is_demo',
        'pref_column': 'demo_enabled',
        'title': 'Demo Master',
        'description': 'Demo vocabulary completed!'
    },
    'BUSINESS_ENGLISH': {
        'vocab_column': 'business_english',
        'pref_column': 'business_english_enabled',
        'title': 'Business English Master',
        'description': 'Business English vocabulary completed!'
    },
    'EVERYDAY_ENGLISH': {
        'vocab_column': 'everyday_english',
        'pref_column': 'everyday_english_enabled',
        'title': 'Everyday English Master',
        'description': 'Everyday English vocabulary completed!'
    }
}


# ============================================================================
# UTILITY FUNCTIONS - Shared logic for achievements, badges, and progress
# ============================================================================

def calculate_user_score(user_id: str) -> int:
    """
    Calculate total score from reviews.

    Score formula:
    - Correct review = 2 points
    - Incorrect review = 1 point

    Args:
        user_id: User UUID string

    Returns:
        Total score as integer (0 if no reviews)
    """
    result = db_fetch_one("""
        SELECT COALESCE(SUM(CASE WHEN response THEN 2 ELSE 1 END), 0) as score
        FROM reviews
        WHERE user_id = %s
    """, (user_id,))

    return result['score'] if result else 0


def count_test_vocabulary_progress(user_id: str, vocab_column: str, language: str = 'en') -> dict:
    """
    Count total and saved words for a specific test vocabulary.

    Args:
        user_id: User UUID string
        vocab_column: Column name like 'is_toefl_beginner', 'is_demo', etc.
        language: Language code (default: 'en')

    Returns:
        Dictionary with:
        - saved_words: Number of words user has saved from this test
        - total_words: Total number of words in this test vocabulary
    """
    # Count total words in test vocabulary
    total_words_result = db_fetch_one(f"""
        SELECT COUNT(*) as total
        FROM bundle_vocabularies
        WHERE {vocab_column} = TRUE AND language = %s
    """, (language,))
    total_words = total_words_result['total'] if total_words_result else 0

    # Count saved words (completed by user)
    saved_words_result = db_fetch_one(f"""
        SELECT COUNT(DISTINCT sw.word) as saved
        FROM saved_words sw
        INNER JOIN bundle_vocabularies tv ON
            LOWER(sw.word) = LOWER(tv.word) AND
            sw.learning_language = tv.language
        WHERE sw.user_id = %s AND tv.{vocab_column} = TRUE
    """, (user_id,))
    saved_words = saved_words_result['saved'] if saved_words_result else 0

    return {
        "saved_words": saved_words,
        "total_words": total_words
    }


def get_newly_earned_score_badges(old_score: int, new_score: int) -> list:
    """
    Determine which score-based badges were newly earned.

    A badge is newly earned if: old_score < milestone <= new_score

    Args:
        old_score: Score before the review
        new_score: Score after the review

    Returns:
        List of badge dictionaries with ultra-minimal structure:
        [{"badge_id": "score_100", "title": "First Steps", "description": "100 points reached"}]
    """
    new_badges = []

    for achievement in ACHIEVEMENTS:
        milestone = achievement['milestone']
        # Badge is newly earned if old_score < milestone <= new_score
        if old_score < milestone <= new_score:
            new_badges.append({
                "badge_id": f"score_{milestone}",
                "title": achievement['title'],
                "description": f"{milestone} points reached"
            })

    return new_badges


def get_user_test_preferences(user_id: str) -> dict:
    """
    Get user's test vocabulary preferences (which tests are enabled).

    Args:
        user_id: User UUID string

    Returns:
        Dictionary mapping test names to enabled status:
        {
            'TOEFL_BEGINNER': True/False,
            'TOEFL_INTERMEDIATE': True/False,
            ...
        }
        Returns empty dict if user has no preferences.
    """
    # Get user's test settings
    prefs = db_fetch_one("""
        SELECT toefl_beginner_enabled, toefl_intermediate_enabled, toefl_advanced_enabled,
               ielts_beginner_enabled, ielts_intermediate_enabled, ielts_advanced_enabled,
               demo_enabled
        FROM user_preferences
        WHERE user_id = %s
    """, (user_id,))

    if not prefs:
        return {}

    # Map test types to their enabled status
    result = {}
    for test_name, metadata in TEST_TYPES_MAPPING.items():
        pref_column = metadata['pref_column']
        result[test_name] = prefs.get(pref_column, False)

    return result


def check_test_completion_badges(
    user_id: str,
    current_word: str,
    learning_language: str,
    enabled_tests_only: bool = True
) -> list:
    """
    Check if user just completed any test vocabularies.

    A test is completed when:
    1. User has saved all words in the test vocabulary
    2. The current word being reviewed is part of that test
    3. The test is enabled (if enabled_tests_only=True)

    Args:
        user_id: User UUID string
        current_word: The word that was just reviewed
        learning_language: Language code (e.g., 'en')
        enabled_tests_only: Only check enabled tests (default: True)

    Returns:
        List of completion badge dictionaries:
        [{"badge_id": "DEMO", "title": "Demo Master", "description": "Demo vocabulary completed!"}]
    """
    completion_badges = []

    # Get user's test preferences if needed
    enabled_tests = {}
    if enabled_tests_only:
        enabled_tests = get_user_test_preferences(user_id)

    # Check each test type
    for test_name, metadata in TEST_TYPES_MAPPING.items():
        # Skip if checking enabled tests only and this test is not enabled
        if enabled_tests_only and not enabled_tests.get(test_name, False):
            continue

        vocab_column = metadata['vocab_column']

        # Get progress for this test
        progress = count_test_vocabulary_progress(user_id, vocab_column, learning_language)

        # Check if test is completed (saved == total)
        if progress['total_words'] > 0 and progress['saved_words'] == progress['total_words']:
            # Check if current word is part of this test vocabulary
            is_test_word_result = db_fetch_one(f"""
                SELECT COUNT(*) as is_test_word
                FROM bundle_vocabularies
                WHERE LOWER(word) = LOWER(%s)
                  AND language = %s
                  AND {vocab_column} = TRUE
            """, (current_word, learning_language))

            is_test_word = (is_test_word_result['is_test_word'] > 0) if is_test_word_result else False

            # If this review was for a test word, award the completion badge
            if is_test_word:
                completion_badges.append({
                    "badge_id": test_name,
                    "title": metadata['title'],
                    "description": metadata['description']
                })
                logger.info(f"User {user_id} completed {test_name} test vocabulary!")

    return completion_badges


# ============================================================================
# API ENDPOINTS
# ============================================================================

def get_achievement_progress():
    """
    GET /v3/achievements/progress?user_id=XXX
    Get achievement progress for a user based on score from reviews.
    Score formula: failed review = 1 point, success review = 2 points

    Response:
        {
            "user_id": "uuid",
            "score": 450,
            "achievements": [...all achievements with unlocked status...],
            "next_milestone": 500,
            "next_achievement": {...},
            "current_achievement": {...}
        }
    """
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        # Validate UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400

        # Calculate score using utility function
        score = calculate_user_score(user_id)

        # Determine unlocked achievements
        achievements_with_status = []
        current_achievement = None
        next_achievement = None

        for achievement in ACHIEVEMENTS:
            is_unlocked = score >= achievement['milestone']
            achievements_with_status.append({
                **achievement,
                "unlocked": is_unlocked
            })

            # Track current achievement (highest unlocked)
            if is_unlocked:
                current_achievement = achievement

            # Track next achievement (first locked)
            if not is_unlocked and next_achievement is None:
                next_achievement = achievement

        return jsonify({
            "user_id": user_id,
            "score": score,
            "achievements": achievements_with_status,
            "next_milestone": next_achievement['milestone'] if next_achievement else None,
            "next_achievement": next_achievement,
            "current_achievement": current_achievement
        }), 200

    except Exception as e:
        logger.error(f"Error in get_achievement_progress: {str(e)}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500


def get_test_vocabulary_awards():
    """
    GET /v3/achievements/test-vocabulary-awards?user_id=XXX
    Get test vocabulary completion progress for ALL tests.

    Returns progress for all test types regardless of which test the user has enabled.
    This allows displaying past badges even if user switched tests.

    Response:
        {
            "TOEFL_BEGINNER": {
                "saved_test_words": 750,
                "total_test_words": 796
            },
            "TOEFL_INTERMEDIATE": {
                "saved_test_words": 1200,
                "total_test_words": 1995
            },
            ...
        }
    """
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        # Validate UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400

        # Use utility functions to get progress for all test types
        result = {}

        for test_name, metadata in TEST_TYPES_MAPPING.items():
            vocab_column = metadata['vocab_column']
            progress = count_test_vocabulary_progress(user_id, vocab_column, language='en')

            result[test_name] = {
                "saved_test_words": progress['saved_words'],
                "total_test_words": progress['total_words']
            }

        return jsonify(result), 200

    except Exception as e:
        logger.error(f"Error in get_test_vocabulary_awards: {str(e)}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500
