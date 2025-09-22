from flask import Flask, request, jsonify, Response, g
import os
from dotenv import load_dotenv
import time
from datetime import datetime
import logging
import sys
import json
import threading
# Load environment variables
load_dotenv('.env.secrets')

# Import utility functions
from utils.database import validate_language, get_db_connection

# Import service functions
from services.user_service import generate_user_profile, get_user_preferences

# Import all the remaining functions from the original app for now
# This allows us to refactor incrementally
# from app import (
#     # Spaced repetition functions
#     # calculate_spaced_repetition, 
#     # get_word_review_data,

#     #  ========  ?unused?  ========
#     # get_decay_rate,
#     # calculate_retention, get_next_review_date_new, get_due_words_count,

#     # Audio functions
#     # audio_exists, 
#     # store_audio,
#     # collect_audio_references, queue_missing_audio, audio_generation_worker,

#     # Dictionary functions
#     # get_cached_definition, build_definition_prompt,

#     # Middleware functions
#     # log_request_info, log_response_info
# )

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


@app.before_request
def log_request_info():
    """Log all incoming requests with full details"""
    g.start_time = time.time()
    
    # Log request details
    request_data = {
        'method': request.method,
        'url': request.url,
        'remote_addr': request.remote_addr,
        'user_agent': request.headers.get('User-Agent', ''),
        'content_type': request.headers.get('Content-Type', ''),
        'content_length': request.headers.get('Content-Length', ''),
        'headers': dict(request.headers),
        'args': dict(request.args),
    }
    
    # Only log request body for non-GET requests and if it's not too large
    if request.method != 'GET' and request.content_length and request.content_length < 10000:
        try:
            if request.is_json:
                request_data['json_body'] = request.get_json()
            elif request.form:
                request_data['form_data'] = dict(request.form)
            else:
                request_data['raw_body'] = request.get_data(as_text=True)[:1000]  # Limit to 1000 chars
        except Exception as e:
            request_data['body_error'] = str(e)
    
    app.logger.info(f"REQUEST: {json.dumps(request_data, default=str, indent=2)}")

@app.after_request
def log_response_info(response):
    """Log all outgoing responses with full details"""
    duration = time.time() - getattr(g, 'start_time', time.time())
    
    response_data = {
        'status_code': response.status_code,
        'status': response.status,
        'content_type': response.content_type,
        'content_length': response.content_length,
        'headers': dict(response.headers),
        'duration_ms': round(duration * 1000, 2)
    }
    
    # Log response body if it's not too large and is text-based
    if response.content_length and response.content_length < 10000:
        try:
            if response.content_type and 'json' in response.content_type:
                response_data['json_body'] = response.get_json()
            elif response.content_type and response.content_type.startswith('text/'):
                response_data['text_body'] = response.get_data(as_text=True)[:1000]  # Limit to 1000 chars
        except Exception as e:
            response_data['body_error'] = str(e)
    
    app.logger.info(f"RESPONSE: {json.dumps(response_data, default=str, indent=2)}")
    
    return response

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

from handlers.actions import save_word, delete_saved_word, delete_saved_word_v2, get_next_review_word, submit_feedback, submit_review
from handlers.users import handle_user_preferences, get_supported_languages
from handlers.reads import get_due_counts, get_review_progress_stats, get_review_stats, get_forgetting_curve, get_review_statistics, get_weekly_review_counts, get_progress_funnel, get_review_activity, get_leaderboard
from handlers.admin import test_review_intervals, fix_next_review_dates
from handlers.usage_dashboard import get_usage_dashboard
from handlers.analytics import track_user_action, get_analytics_data
from handlers.pronunciation import practice_pronunciation, get_pronunciation_history, get_pronunciation_stats

from handlers.words import audio_generation_worker, get_saved_words, get_word_definition, get_word_definition_v2, get_word_details, get_audio, generate_illustration, get_illustration

# Register all routes
app.route('/save', methods=['POST'])(save_word)

app.route('/v2/unsave', methods=['POST'])(delete_saved_word_v2)
app.route('/unsave', methods=['POST'])(delete_saved_word)
app.route('/review_next', methods=['GET'])(get_next_review_word)  
app.route('/due_counts', methods=['GET'])(get_due_counts)  
app.route('/reviews/submit', methods=['POST'])(submit_review)
app.route('/word', methods=['GET'])(get_word_definition)
app.route('/v2/word', methods=['GET'])(get_word_definition_v2)
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
app.route('/analytics/track', methods=['POST'])(track_user_action)
app.route('/analytics/data', methods=['GET'])(get_analytics_data)
app.route('/pronunciation/practice', methods=['POST'])(practice_pronunciation)
app.route('/pronunciation/history', methods=['GET'])(get_pronunciation_history)
app.route('/pronunciation/stats', methods=['GET'])(get_pronunciation_stats)

if __name__ == '__main__':
    audio_worker_thread = threading.Thread(target=audio_generation_worker, daemon=True)
    audio_worker_thread.start()

    port = int(os.environ.get('PORT', 5000))
    app.logger.info(f"Starting Dogetionary Refactored API server on port {port}")
    app.run(host='0.0.0.0', port=port, debug=True)