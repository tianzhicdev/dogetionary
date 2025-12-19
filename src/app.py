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

    # Import admin handlers (only remaining legacy routes)
    from handlers.admin import (
        test_review_intervals, fix_next_review_dates,
        privacy_agreement, support_page, health_check
    )
    from handlers.usage_dashboard import get_usage_dashboard
    from handlers.api_usage_analytics import get_api_usage_analytics

    # =================================================================
    # LEGACY ENDPOINTS REMOVED
    # =================================================================
    # All legacy endpoints have been removed as iOS app uses V3 API exclusively.
    # Deleted 37 legacy route registrations:
    # - Core endpoints (10): /save, /unsave, /word, /saved_words, etc.
    # - User management (2): /users/<id>/preferences, /languages
    # - Analytics (7): /leaderboard, /reviews/stats, /analytics/data, etc.
    # - Media (3): /audio/<text>/<lang>, /get-illustration, etc.
    # - Pronunciation (3): /pronunciation/practice, /pronunciation/stats, etc.
    # - Static site (3): /words, /words/summary, /words/featured
    # - Bulk data (1): /api/words/generate
    # - Test prep (8): /api/test-prep/* endpoints
    #
    # All functionality is now available through V3 API (/v3/*)
    # =================================================================

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
