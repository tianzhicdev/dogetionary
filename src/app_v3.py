# V3 API Endpoints - Current Version
# These endpoints represent the latest API version with all improvements
# while maintaining backward compatibility in the main app

from flask import Blueprint
from handlers.actions import save_word, delete_saved_word_v2, submit_feedback, submit_review
from handlers.users import handle_user_preferences
from handlers.reads import get_due_counts, get_review_progress_stats, get_forgetting_curve, get_leaderboard_v2
from handlers.admin import test_review_intervals, fix_next_review_dates, privacy_agreement, support_page, health_check
from handlers.usage_dashboard import get_usage_dashboard
from handlers.analytics import track_user_action
from handlers.pronunciation import practice_pronunciation
from handlers.words import get_saved_words, get_word_definition_v3, get_word_details, get_audio, get_illustration, toggle_exclude_from_practice
from handlers.test_vocabulary import get_test_vocabulary_count
from handlers.schedule import get_today_schedule, get_schedule_range, get_test_progress
from handlers.review_batch import get_review_words_batch
from handlers.streaks import get_streak_days
from handlers.achievements import get_achievement_progress
from handlers.practice_status import get_practice_status
from handlers.app_version import check_app_version

# Create v3 blueprint
v3_api = Blueprint('v3_api', __name__, url_prefix='/v3')

# ============================================================================
# V3 CORE ENDPOINTS - Latest API versions with all improvements
# ============================================================================

# Word Management (V3 - with word validation and suggestions)
v3_api.route('/word', methods=['GET'])(get_word_definition_v3)  # V3 with validation
v3_api.route('/save', methods=['POST'])(save_word)
v3_api.route('/unsave', methods=['POST'])(delete_saved_word_v2)  # V2 unsave as default
v3_api.route('/saved_words', methods=['GET'])(get_saved_words)

# Review System (V3 - current version)
v3_api.route('/next-review-words-batch', methods=['GET'])(get_review_words_batch)  # Batch fetch for performance
v3_api.route('/reviews/submit', methods=['POST'])(submit_review)
v3_api.route('/due_counts', methods=['GET'])(get_due_counts)
v3_api.route('/reviews/progress_stats', methods=['GET'])(get_review_progress_stats)

# Word Details and Analytics (V3)
v3_api.route('/words/<int:word_id>/details', methods=['GET'])(get_word_details)
v3_api.route('/words/<int:word_id>/forgetting-curve', methods=['GET'])(get_forgetting_curve)

# Media and Assets (V3 - merged illustration functionality)
v3_api.route('/audio/<path:text>/<language>')(get_audio)
v3_api.route('/illustration', methods=['GET', 'POST'])(get_illustration)  # Merged cache-first logic

# User Management (V3)
v3_api.route('/users/<user_id>/preferences', methods=['GET', 'POST'])(handle_user_preferences)

# Analytics and Statistics (V3)
v3_api.route('/leaderboard-score', methods=['GET'])(get_leaderboard_v2)

# Pronunciation Features (V3)
v3_api.route('/pronunciation/practice', methods=['POST'])(practice_pronunciation)

# Word Operations (V3)
v3_api.route('/words/toggle-exclude', methods=['POST'])(toggle_exclude_from_practice)

# Test Vocabulary (V3)
v3_api.route('/api/test-vocabulary-count', methods=['GET'])(get_test_vocabulary_count)  # Onboarding endpoint

# Schedule Management (V3) - Study plan scheduling (on-the-fly calculation)
v3_api.route('/schedule/today', methods=['GET'])(get_today_schedule)
v3_api.route('/schedule/range', methods=['GET'])(get_schedule_range)
v3_api.route('/schedule/test-progress', methods=['GET'])(get_test_progress)

# Administrative (V3)
v3_api.route('/test-review-intervals', methods=['GET'])(test_review_intervals)
v3_api.route('/fix_next_review_dates', methods=['POST'])(fix_next_review_dates)
v3_api.route('/privacy', methods=['GET'])(privacy_agreement)
v3_api.route('/support', methods=['GET'])(support_page)
v3_api.route('/health', methods=['GET'])(health_check)
v3_api.route('/usage', methods=['GET'])(get_usage_dashboard)

# Analytics Tracking (V3)
v3_api.route('/analytics/track', methods=['POST'])(track_user_action)

# Streak Days (V3)
v3_api.route('/get-streak-days', methods=['GET'])(get_streak_days)

# Achievements (V3)
v3_api.route('/achievements/progress', methods=['GET'])(get_achievement_progress)

# Practice Status (V3)
v3_api.route('/practice-status', methods=['GET'])(get_practice_status)

# Feedback (V3)
v3_api.route('/feedback', methods=['POST'])(submit_feedback)

# App Version Check (V3)
v3_api.route('/app-version', methods=['GET'])(check_app_version)

def register_v3_routes(app):
    """Register all V3 routes with the Flask app"""
    app.register_blueprint(v3_api)
    app.logger.info("✅ V3 API routes registered at /v3/*")