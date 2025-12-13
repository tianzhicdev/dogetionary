from flask import Flask
import os
import logging
import sys
import threading
import schedule
from dotenv import load_dotenv

# Load environment variables
load_dotenv('.env.secrets')

# Import blueprints
from routes import register_blueprints
from middleware.logging import setup_logging, log_request_info, log_response_info
from workers.audio_worker import audio_generation_worker
from workers.test_vocabulary_worker import daily_test_words_worker

def create_app():
    """Create and configure the Flask application"""
    app = Flask(__name__)

    # Allow large file uploads (20MB for video uploads)
    app.config['MAX_CONTENT_LENGTH'] = 20 * 1024 * 1024  # 20 MB

    # Setup logging
    setup_logging(app)
    app.logger.info("=== DOGETIONARY API INITIALIZED ===")

    # Register middleware
    app.before_request(log_request_info)
    app.after_request(log_response_info)

    # Register all blueprints
    register_blueprints(app)

    return app

def start_background_workers():
    """Start all background worker threads"""
    # Audio generation worker
    audio_worker = threading.Thread(target=audio_generation_worker, daemon=True)
    audio_worker.start()

    # Daily test vocabulary scheduler
    test_words_worker = threading.Thread(target=daily_test_words_worker, daemon=True)
    test_words_worker.start()

    logging.info("✅ Background workers started")

if __name__ == '__main__':
    app = create_app()
    start_background_workers()

    port = int(os.environ.get('PORT', 5000))
    app.logger.info(f"Starting Dogetionary API server on port {port}")
    app.run(host='0.0.0.0', port=port, debug=True)