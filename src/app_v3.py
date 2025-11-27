# V3 API Endpoints - Current Version
# These endpoints represent the latest API version with all improvements
# while maintaining backward compatibility in the main app

from flask import Blueprint
from handlers.actions import save_word, delete_saved_word_v2, submit_feedback, submit_review
from handlers.users import handle_user_preferences, get_supported_languages
from handlers.reads import get_due_counts, get_review_progress_stats, get_forgetting_curve, get_leaderboard, get_leaderboard_v2, get_combined_metrics
from handlers.admin import test_review_intervals, fix_next_review_dates, privacy_agreement, support_page, health_check
from handlers.usage_dashboard import get_usage_dashboard
from handlers.analytics import track_user_action, get_analytics_data
from handlers.pronunciation import practice_pronunciation, get_pronunciation_history, get_pronunciation_stats
from handlers.words import get_next_review_word_v2, get_saved_words, get_word_definition_v3, get_word_details, get_audio, get_illustration, generate_word_definition, get_all_words_for_language_pair, toggle_exclude_from_practice
from handlers.static_site import get_all_words, get_words_summary, get_featured_words
from handlers.test_vocabulary import add_daily_test_words, get_test_vocabulary_stats, manual_daily_job, get_test_vocabulary_count, get_test_config
from handlers.schedule import get_today_schedule, get_schedule_range, get_next_review_word_with_scheduled_new_words, get_test_progress
from handlers.enhanced_review import get_next_review_enhanced
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
v3_api.route('/review_next', methods=['GET'])(get_next_review_word_v2)  # V2 as default in V3
v3_api.route('/review_next_enhanced', methods=['GET'])(get_next_review_enhanced)  # V3 Enhanced with diverse question types
v3_api.route('/next-review-word-with-scheduled-new-words', methods=['GET'])(get_next_review_word_with_scheduled_new_words)  # V3 with schedule integration
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
v3_api.route('/languages', methods=['GET'])(get_supported_languages)

# Analytics and Statistics (V3)
v3_api.route('/leaderboard', methods=['GET'])(get_leaderboard)
v3_api.route('/leaderboard-score', methods=['GET'])(get_leaderboard_v2)
v3_api.route('/combined_metrics', methods=['GET'])(get_combined_metrics)

# Pronunciation Features (V3)
v3_api.route('/pronunciation/practice', methods=['POST'])(practice_pronunciation)
v3_api.route('/pronunciation/history', methods=['GET'])(get_pronunciation_history)
v3_api.route('/pronunciation/stats', methods=['GET'])(get_pronunciation_stats)

# Static Content (V3)
v3_api.route('/words', methods=['GET'])(get_all_words)
v3_api.route('/words/summary', methods=['GET'])(get_words_summary)
v3_api.route('/words/featured', methods=['GET'])(get_featured_words)

# Bulk Operations (V3)
v3_api.route('/api/words/generate', methods=['POST'])(generate_word_definition)
v3_api.route('/words/toggle-exclude', methods=['POST'])(toggle_exclude_from_practice)

# Test Vocabulary (V3)
v3_api.route('/api/test-prep/add-words', methods=['POST'])(add_daily_test_words)
v3_api.route('/api/test-prep/stats', methods=['GET'])(get_test_vocabulary_stats)
v3_api.route('/api/test-prep/config', methods=['GET'])(get_test_config)  # Language -> tests mapping
v3_api.route('/api/test-prep/run-daily-job', methods=['POST'])(manual_daily_job)
v3_api.route('/api/test-vocabulary-count', methods=['GET'])(get_test_vocabulary_count)  # New onboarding endpoint

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
v3_api.route('/analytics/data', methods=['GET'])(get_analytics_data)

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

# ============================================================================
# V3 NEW ENDPOINTS - Enhanced functionality
# ============================================================================

# These endpoints provide enhanced functionality that wasn't available before

# Language Pair Word List (V3)
v3_api.route('/<learning_lang>/<native_lang>/all_words', methods=['GET'])(get_all_words_for_language_pair)

def register_v3_routes(app):
    """Register all V3 routes with the Flask app"""
    app.register_blueprint(v3_api)
    app.logger.info("✅ V3 API routes registered at /v3/*")