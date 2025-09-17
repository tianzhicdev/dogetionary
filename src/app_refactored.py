from flask import Flask, request, jsonify, Response, g
import os
from dotenv import load_dotenv
import time
from datetime import datetime
import logging
import sys

# Load environment variables
load_dotenv('.env.secrets')

# Import utility functions
from utils.database import validate_language, get_db_connection

# Import service functions
from services.user_service import generate_user_profile, get_user_preferences

# Import all the remaining functions from the original app for now
# This allows us to refactor incrementally
from app import (
    # Spaced repetition functions
    calculate_spaced_repetition, get_word_review_data, get_decay_rate,
    calculate_retention, get_next_review_date_new, get_due_words_count,

    # Audio functions
    generate_audio_for_text, audio_exists, store_audio,
    collect_audio_references, queue_missing_audio, audio_generation_worker,

    # Dictionary functions
    get_cached_definition, build_definition_prompt,

    # Middleware functions
    log_request_info, log_response_info
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

app = Flask(__name__)

# Set Flask app logger level
app.logger.setLevel(logging.INFO)
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
app.logger.addHandler(handler)

app.logger.info("=== DOGETIONARY REFACTORED LOGGING INITIALIZED ===")

# Add middleware
app.before_request(log_request_info)
app.after_request(log_response_info)

# Import and register all endpoints from original app
# This allows us to keep all functionality while refactoring incrementally
from app import (
    # save_word, get_next_review_word, 
    # get_due_counts, submit_review,
    # get_word_definition, get_saved_words,
    #  handle_user_preferences,
    # get_review_stats, get_forgetting_curve, 
    # test_review_intervals,
    # get_word_details, get_audio, get_supported_languages,
    # fix_next_review_dates, 
    privacy_agreement, support_page,
    # get_review_statistics, get_weekly_review_counts, get_progress_funnel,
    # get_review_activity, get_leaderboard, generate_illustration,
    # get_illustration, 
    health_check, 
    # submit_feedback, get_review_progress_stats
)

from handlers.actions import save_word, get_next_review_word, submit_feedback, submit_review
from handlers.users import handle_user_preferences
from handlers.reads import get_due_counts, get_review_progress_stats, get_review_stats, get_forgetting_curve, get_review_statistics, get_weekly_review_counts, get_progress_funnel, get_review_activity, get_leaderboard
from handlers.admin import test_review_intervals, fix_next_review_dates
from handlers.usage_dashboard import get_usage_dashboard
# Import word-related functions from original app temporarily
from app import get_word_definition, get_saved_words, get_word_details, get_audio, get_supported_languages, generate_illustration, get_illustration

# Register all routes
app.route('/save', methods=['POST'])(save_word) 
app.route('/review_next', methods=['GET'])(get_next_review_word)  
app.route('/due_counts', methods=['GET'])(get_due_counts)  
app.route('/reviews/submit', methods=['POST'])(submit_review) 
app.route('/word', methods=['GET'])(get_word_definition) 
app.route('/saved_words', methods=['GET'])(get_saved_words) 
app.route('/users/<user_id>/preferences', methods=['GET', 'POST'])(handle_user_preferences) 
app.route('/reviews/stats', methods=['GET'])(get_review_stats) 
app.route('/words/<int:word_id>/forgetting-curve', methods=['GET'])(get_forgetting_curve) 
app.route('/test-review-intervals', methods=['GET'])(test_review_intervals) 
app.route('/words/<int:word_id>/details', methods=['GET'])(get_word_details)
app.route('/audio/<path:text>/<language>')(get_audio)
app.route('/languages', methods=['GET'])(get_supported_languages)
app.route('/fix_next_review_dates', methods=['POST'])(fix_next_review_dates)
app.route('/privacy', methods=['GET'])(privacy_agreement)
app.route('/support', methods=['GET'])(support_page)
app.route('/review_statistics', methods=['GET'])(get_review_statistics)
app.route('/weekly_review_counts', methods=['GET'])(get_weekly_review_counts)
app.route('/progress_funnel', methods=['GET'])(get_progress_funnel)
app.route('/review_activity', methods=['GET'])(get_review_activity)
app.route('/leaderboard', methods=['GET'])(get_leaderboard)
app.route('/generate-illustration', methods=['POST'])(generate_illustration)
app.route('/illustration', methods=['GET'])(get_illustration)
app.route('/health', methods=['GET'])(health_check)
app.route('/feedback', methods=['POST'])(submit_feedback)
app.route('/reviews/progress_stats', methods=['GET'])(get_review_progress_stats)
app.route('/usage', methods=['GET'])(get_usage_dashboard)

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.logger.info(f"Starting Dogetionary Refactored API server on port {port}")
    app.run(host='0.0.0.0', port=port, debug=True)