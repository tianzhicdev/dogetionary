"""
Achievements Handler

This module provides functions to:
- Calculate achievement progress based on saved words
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

# Achievement milestones with metadata
ACHIEVEMENTS = [
    # Beginner Tier
    {"milestone": 10, "title": "First Steps", "symbol": "leaf.fill", "tier": "beginner", "is_award": False},
    {"milestone": 30, "title": "Growing", "symbol": "leaf.circle.fill", "tier": "beginner", "is_award": False},
    {"milestone": 50, "title": "Blooming", "symbol": "sparkles", "tier": "beginner", "is_award": False},
    {"milestone": 100, "title": "Century", "symbol": "star.fill", "tier": "beginner", "is_award": False},

    # Intermediate Tier
    {"milestone": 150, "title": "On Fire", "symbol": "flame.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 200, "title": "Gem Collector", "symbol": "gem.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 250, "title": "Champion", "symbol": "trophy.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 300, "title": "Royalty", "symbol": "crown.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 350, "title": "Sharpshooter", "symbol": "target", "tier": "intermediate", "is_award": False},
    {"milestone": 400, "title": "Soaring", "symbol": "paperplane.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 450, "title": "Lightning", "symbol": "bolt.fill", "tier": "intermediate", "is_award": False},
    {"milestone": 500, "title": "Word Master", "symbol": "medal.fill", "tier": "intermediate", "is_award": True},

    # Advanced Tier
    {"milestone": 600, "title": "Rising Star", "symbol": "star.circle.fill", "tier": "advanced", "is_award": False},
    {"milestone": 700, "title": "Brilliant", "symbol": "sparkle", "tier": "advanced", "is_award": False},
    {"milestone": 800, "title": "Mystical", "symbol": "moon.stars.fill", "tier": "advanced", "is_award": False},
    {"milestone": 900, "title": "Magical", "symbol": "wand.and.stars", "tier": "advanced", "is_award": False},
    {"milestone": 1000, "title": "Grand Master", "symbol": "rosette", "tier": "advanced", "is_award": True},

    # Expert Tier
    {"milestone": 1500, "title": "Legendary", "symbol": "sparkles.rectangle.stack.fill", "tier": "expert", "is_award": True},
    {"milestone": 2000, "title": "Vocabulary God", "symbol": "crown.fill", "tier": "expert", "is_award": True},
]


def get_achievement_progress():
    """
    GET /v3/achievements/progress?user_id=XXX
    Get achievement progress for a user based on saved words count.

    Response:
        {
            "user_id": "uuid",
            "saved_words": 450,
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

        # Get saved words count for user
        result = db_fetch_one("""
            SELECT COUNT(*) as saved_words
            FROM saved_words
            WHERE user_id = %s
        """, (user_id,))

        saved_words = result['saved_words'] if result else 0

        # Determine unlocked achievements
        achievements_with_status = []
        current_achievement = None
        next_achievement = None

        for achievement in ACHIEVEMENTS:
            is_unlocked = saved_words >= achievement['milestone']
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
            "saved_words": saved_words,
            "achievements": achievements_with_status,
            "next_milestone": next_achievement['milestone'] if next_achievement else None,
            "next_achievement": next_achievement,
            "current_achievement": current_achievement
        }), 200

    except Exception as e:
        logger.error(f"Error in get_achievement_progress: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500
