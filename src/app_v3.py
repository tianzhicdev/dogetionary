# V3 API Endpoints - Current Version
# These endpoints represent the latest API version with all improvements
# while maintaining backward compatibility in the main app

from flask import Blueprint, jsonify
import logging
from handlers.actions import save_word, delete_saved_word_v2, submit_feedback, submit_review
from handlers.users import handle_user_preferences
from handlers.reads import get_due_counts, get_review_progress_stats, get_forgetting_curve, get_leaderboard_v2
from handlers.admin import test_review_intervals, fix_next_review_dates, privacy_agreement, support_page, health_check
from handlers.usage_dashboard import get_usage_dashboard
from handlers.analytics import track_user_action
from handlers.pronunciation import practice_pronunciation, submit_pronunciation_review
from handlers.words import get_saved_words, get_word_definition_v4, get_word_details, get_audio, get_illustration, toggle_exclude_from_practice, is_word_saved
from handlers.videos import get_video, get_video_bytes_only, get_video_generator_memoryview
from handlers.admin_videos import batch_upload_videos, get_bundle_words_needing_videos
from handlers.admin_questions import batch_generate_questions
from handlers.admin_questions_smart import smart_batch_generate_questions
from handlers.bundle_vocabulary import (
    get_test_vocabulary_count, update_test_settings, get_test_settings,
    add_daily_test_words, get_test_vocabulary_stats, batch_populate_test_vocabulary,
    get_test_config
)
from workers.bundle_vocabulary_worker import add_daily_test_words_for_all_users
from handlers.schedule import get_today_schedule, get_schedule_range, get_test_progress
from handlers.review_batch import get_review_words_batch
from handlers.streaks import get_streak_days
from handlers.achievements import get_achievement_progress, get_test_vocabulary_awards
from handlers.practice_status import get_practice_status
from handlers.app_version import check_app_version

# Create v3 blueprint
v3_api = Blueprint('v3_api', __name__, url_prefix='/v3')

# ============================================================================
# V3 CORE ENDPOINTS - Latest API versions with all improvements
# ============================================================================

# Word Management (V4 - with word validation, suggestions, and vocabulary learning features)
v3_api.route('/word', methods=['GET'])(get_word_definition_v4)  # V4 with vocabulary learning enhancements
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
v3_api.route('/videos/<int:video_id>', methods=['GET'])(get_video)  # Video binary data for practice mode
v3_api.route('/videos/bytes-only/<int:video_id>', methods=['GET'])(get_video_bytes_only)  # TEST: bytes only, no generator
v3_api.route('/videos/generator-with-memoryview/<int:video_id>', methods=['GET'])(get_video_generator_memoryview)  # TEST: generator with memoryview

# User Management (V3)
v3_api.route('/users/<user_id>/preferences', methods=['GET', 'POST'])(handle_user_preferences)

# Analytics and Statistics (V3)
v3_api.route('/leaderboard-score', methods=['GET'])(get_leaderboard_v2)

# Pronunciation Features (V3)
v3_api.route('/pronunciation/practice', methods=['POST'])(practice_pronunciation)
v3_api.route('/review/pronounce', methods=['POST'])(submit_pronunciation_review)  # Pronunciation review during practice

# Word Operations (V3)
v3_api.route('/words/toggle-exclude', methods=['POST'])(toggle_exclude_from_practice)
v3_api.route('/is-word-saved', methods=['GET'])(is_word_saved)  # Check if word is saved

# Test Vocabulary (V3)
v3_api.route('/api/test-vocabulary-count', methods=['GET'])(get_test_vocabulary_count)  # Onboarding endpoint (legacy path)

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
v3_api.route('/admin/videos/batch-upload', methods=['POST'])(batch_upload_videos)
v3_api.route('/admin/bundles/<bundle_name>/words-needing-videos', methods=['GET'])(get_bundle_words_needing_videos)
v3_api.route('/admin/questions/batch-generate', methods=['POST'])(batch_generate_questions)
v3_api.route('/admin/questions/smart-batch-generate', methods=['POST'])(smart_batch_generate_questions)

# Analytics Tracking (V3)
v3_api.route('/analytics/track', methods=['POST'])(track_user_action)

# Streak Days (V3)
v3_api.route('/get-streak-days', methods=['GET'])(get_streak_days)

# Achievements (V3)
v3_api.route('/achievements/progress', methods=['GET'])(get_achievement_progress)
v3_api.route('/achievements/test-vocabulary-awards', methods=['GET'])(get_test_vocabulary_awards)

# Practice Status (V3)
v3_api.route('/practice-status', methods=['GET'])(get_practice_status)

# Feedback (V3)
v3_api.route('/feedback', methods=['POST'])(submit_feedback)

# App Version Check (V3)
v3_api.route('/app-version', methods=['GET'])(check_app_version)

# ============================================================================
# TEST PREP ENDPOINTS (V3) - TOEFL/IELTS/DEMO vocabulary preparation
# ============================================================================

# Test prep settings
v3_api.route('/test-prep/settings', methods=['PUT'])(update_test_settings)
v3_api.route('/test-prep/settings', methods=['GET'])(get_test_settings)

# Test prep vocabulary management
v3_api.route('/test-prep/add-words', methods=['POST'])(add_daily_test_words)
v3_api.route('/test-prep/stats', methods=['GET'])(get_test_vocabulary_stats)
v3_api.route('/test-prep/vocabulary-count', methods=['GET'])(get_test_vocabulary_count)
v3_api.route('/test-prep/batch-populate', methods=['POST'])(batch_populate_test_vocabulary)
v3_api.route('/test-prep/config', methods=['GET'])(get_test_config)

@v3_api.route('/test-prep/run-daily-job', methods=['POST'])
def manual_daily_job():
    """Manual trigger for daily test vocabulary job"""
    try:
        logging.info("Manual trigger of daily test vocabulary job")
        add_daily_test_words_for_all_users()
        return jsonify({"success": True, "message": "Daily job completed successfully"}), 200
    except Exception as e:
        logging.error(f"Manual daily job failed: {e}")
        return jsonify({"error": "Failed to run daily job"}), 500

def register_v3_routes(app):
    """Register all V3 routes with the Flask app"""
    app.register_blueprint(v3_api)
    app.logger.info("✅ V3 API routes registered at /v3/*")