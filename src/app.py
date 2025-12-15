"""
Dogetionary API - Main Application Entry Point

This is the consolidated Flask application that serves all API endpoints.
All routes are registered through blueprints for better organization.

Entry point for production deployment via Docker.
"""

from flask import Flask
import os
import logging
import threading
from dotenv import load_dotenv

# Load environment variables
load_dotenv('.env.secrets')

def create_app():
    """
    Create and configure the Flask application.

    Returns:
        Flask: Configured Flask application instance
    """
    app = Flask(__name__)

    # =================================================================
    # APPLICATION CONFIGURATION
    # =================================================================

    # Allow large file uploads (20MB for video uploads)
    app.config['MAX_CONTENT_LENGTH'] = 20 * 1024 * 1024  # 20 MB

    # =================================================================
    # LOGGING SETUP
    # =================================================================

    from middleware.logging import setup_logging, log_request_info, log_response_info
    setup_logging(app)
    app.logger.info("=" * 60)
    app.logger.info("DOGETIONARY API STARTING")
    app.logger.info("=" * 60)

    # =================================================================
    # ERROR HANDLERS
    # =================================================================

    from middleware.error_handler import register_error_handlers
    register_error_handlers(app)

    # =================================================================
    # MIDDLEWARE REGISTRATION
    # =================================================================

    # Logging middleware
    app.before_request(log_request_info)
    app.after_request(log_response_info)

    # API usage tracking
    from middleware.api_usage_tracker import (
        track_request_start as track_api_usage_start,
        track_request_end as track_api_usage_end
    )
    app.before_request(track_api_usage_start)
    app.after_request(track_api_usage_end)

    # Metrics tracking
    from middleware.metrics_middleware import (
        track_request_start as track_metrics_start,
        track_request_end as track_metrics_end
    )
    app.before_request(track_metrics_start)
    app.after_request(track_metrics_end)

    # =================================================================
    # ROUTE REGISTRATION
    # =================================================================

    # Register legacy routes (for backward compatibility)
    register_legacy_routes(app)

    # Register V3 API blueprint (primary API version)
    from app_v3 import v3_api
    app.register_blueprint(v3_api)
    app.logger.info("✅ V3 API blueprint registered at /v3/*")

    # Register metrics endpoint
    from middleware.metrics import metrics_endpoint
    app.route('/metrics', methods=['GET'])(metrics_endpoint)

    app.logger.info("✅ All routes registered successfully")

    return app


def register_legacy_routes(app):
    """
    Register legacy routes for backward compatibility with older iOS versions.

    These routes maintain compatibility with apps that haven't migrated to V3 API.
    New features should be added to the V3 blueprint in app_v3.py.

    Args:
        app: Flask application instance
    """
    app.logger.info("Registering legacy routes for backward compatibility...")

    # Import all legacy handlers
    from handlers.actions import (
        save_word, delete_saved_word, delete_saved_word_v2,
        submit_feedback, submit_review, get_next_review_word
    )
    from handlers.users import handle_user_preferences, get_supported_languages
    from handlers.reads import (
        get_due_counts, get_review_progress_stats, get_review_stats,
        get_forgetting_curve, get_leaderboard
    )
    from handlers.admin import (
        test_review_intervals, fix_next_review_dates,
        privacy_agreement, support_page, health_check
    )
    from handlers.usage_dashboard import get_usage_dashboard
    from handlers.analytics import track_user_action, get_analytics_data
    from handlers.api_usage_analytics import get_api_usage_analytics
    from handlers.pronunciation import (
        practice_pronunciation, get_pronunciation_history, get_pronunciation_stats
    )
    from handlers.words import (
        get_next_review_word_v2, get_saved_words, get_word_definition_v4,
        get_word_details, get_audio, get_illustration, generate_word_definition
    )
    from handlers.static_site import get_all_words, get_words_summary, get_featured_words
    from handlers.bundle_vocabulary import (
        update_test_settings, get_test_settings, add_daily_test_words,
        get_test_vocabulary_stats, get_test_vocabulary_count,
        manual_daily_job, get_test_config, batch_populate_test_vocabulary
    )

    # =================================================================
    # CORE ENDPOINTS (Legacy - for backward compatibility)
    # =================================================================

    app.route('/save', methods=['POST'])(save_word)
    app.route('/unsave', methods=['POST'])(delete_saved_word)
    app.route('/v2/unsave', methods=['POST'])(delete_saved_word_v2)
    app.route('/review_next', methods=['GET'])(get_next_review_word)  # Old iOS versions
    app.route('/v2/review_next', methods=['GET'])(get_next_review_word_v2)
    app.route('/due_counts', methods=['GET'])(get_due_counts)
    app.route('/reviews/submit', methods=['POST'])(submit_review)
    app.route('/word', methods=['GET'])(get_word_definition_v4)
    app.route('/saved_words', methods=['GET'])(get_saved_words)
    app.route('/feedback', methods=['POST'])(submit_feedback)

    # =================================================================
    # USER MANAGEMENT (Legacy)
    # =================================================================

    app.route('/users/<user_id>/preferences', methods=['GET', 'POST'])(handle_user_preferences)
    app.route('/languages', methods=['GET'])(get_supported_languages)

    # =================================================================
    # ANALYTICS & STATISTICS (Legacy)
    # =================================================================

    app.route('/words/<int:word_id>/forgetting-curve', methods=['GET'])(get_forgetting_curve)
    app.route('/words/<int:word_id>/details', methods=['GET'])(get_word_details)
    app.route('/leaderboard', methods=['GET'])(get_leaderboard)
    app.route('/reviews/stats', methods=['GET'])(get_review_stats)  # Old iOS versions
    app.route('/reviews/progress_stats', methods=['GET'])(get_review_progress_stats)
    app.route('/analytics/track', methods=['POST'])(track_user_action)
    app.route('/analytics/data', methods=['GET'])(get_analytics_data)

    # =================================================================
    # MEDIA ENDPOINTS (Legacy)
    # =================================================================

    app.route('/audio/<path:text>/<language>')(get_audio)
    app.route('/get-illustration', methods=['GET', 'POST'])(get_illustration)
    app.route('/generate-illustration', methods=['POST'])(get_illustration)  # Old iOS versions

    # =================================================================
    # PRONUNCIATION (Legacy)
    # =================================================================

    app.route('/pronunciation/practice', methods=['POST'])(practice_pronunciation)
    app.route('/pronunciation/stats', methods=['GET'])(get_pronunciation_stats)
    app.route('/pronunciation/history', methods=['GET'])(get_pronunciation_history)

    # =================================================================
    # STATIC SITE GENERATION (Legacy)
    # =================================================================

    app.route('/words', methods=['GET'])(get_all_words)
    app.route('/words/summary', methods=['GET'])(get_words_summary)
    app.route('/words/featured', methods=['GET'])(get_featured_words)

    # =================================================================
    # BULK DATA MANAGEMENT (Legacy)
    # =================================================================

    app.route('/api/words/generate', methods=['POST'])(generate_word_definition)

    # =================================================================
    # TEST PREP ENDPOINTS (Legacy - TOEFL/IELTS)
    # =================================================================

    app.route('/api/test-prep/settings', methods=['PUT'])(update_test_settings)
    app.route('/api/test-prep/settings', methods=['GET'])(get_test_settings)
    app.route('/api/test-prep/add-words', methods=['POST'])(add_daily_test_words)
    app.route('/api/test-prep/stats', methods=['GET'])(get_test_vocabulary_stats)
    app.route('/api/v3/test-vocabulary-count', methods=['GET'])(get_test_vocabulary_count)
    app.route('/api/test-prep/config', methods=['GET'])(get_test_config)
    app.route('/api/test-prep/batch-populate', methods=['POST'])(batch_populate_test_vocabulary)
    app.route('/api/test-prep/run-daily-job', methods=['POST'])(manual_daily_job)

    # =================================================================
    # ADMIN ENDPOINTS (Legacy)
    # =================================================================

    app.route('/test-review-intervals', methods=['GET'])(test_review_intervals)
    app.route('/fix_next_review_dates', methods=['POST'])(fix_next_review_dates)
    app.route('/privacy', methods=['GET'])(privacy_agreement)
    app.route('/support', methods=['GET'])(support_page)
    app.route('/health', methods=['GET'])(health_check)
    app.route('/usage', methods=['GET'])(get_usage_dashboard)
    app.route('/api/usage', methods=['GET'])(get_api_usage_analytics)

    app.logger.info("✅ Legacy routes registered")


def start_background_workers():
    """
    Start all background worker threads for async processing.

    Workers:
    - Audio generation worker: Processes TTS audio generation queue
    - Daily test words worker: Schedules daily TOEFL/IELTS vocabulary
    """
    logging.info("Starting background workers...")

    # Audio generation worker
    from handlers.words import audio_generation_worker
    audio_worker = threading.Thread(
        target=audio_generation_worker,
        daemon=True,
        name="AudioWorker"
    )
    audio_worker.start()
    logging.info("✅ Audio generation worker started")

    # Daily test vocabulary scheduler
    from workers.bundle_vocabulary_worker import daily_test_words_worker
    test_words_worker = threading.Thread(
        target=daily_test_words_worker,
        daemon=True,
        name="TestVocabWorker"
    )
    test_words_worker.start()
    logging.info("✅ Test vocabulary scheduler started")

    logging.info("✅ All background workers started successfully")


# =================================================================
# APPLICATION ENTRY POINT
# =================================================================

# Create application instance at module level (required for Gunicorn)
app = create_app()

# Start background workers when app is loaded
start_background_workers()

if __name__ == '__main__':
    # This block is only executed when running with `python app.py` (development mode)
    # In production, Gunicorn will import the 'app' object directly

    # Get port from environment or default to 5000
    port = int(os.environ.get('PORT', 5000))

    app.logger.info("=" * 60)
    app.logger.info(f"Starting Dogetionary API on port {port} (Development Mode)")
    app.logger.info("⚠️  WARNING: Using Flask development server - NOT for production!")
    app.logger.info("=" * 60)

    # Start Flask development server
    app.run(
        host='0.0.0.0',
        port=port,
        debug=True  # Development mode only
    )
