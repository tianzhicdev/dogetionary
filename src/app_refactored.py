from flask import Flask, request, jsonify, Response, g
import os
from dotenv import load_dotenv
import time
from datetime import datetime
import logging
import sys
import json
import threading
import schedule
import time as time_module
from datetime import datetime
# Load environment variables
load_dotenv('.env.secrets')

# Import utility functions
from utils.database import validate_language, get_db_connection

# Import service functions
from services.user_service import generate_user_profile, get_user_preferences

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
from handlers.admin import (
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

from handlers.words import get_next_review_word_v2, audio_generation_worker, get_saved_words, get_word_definition, get_word_definition_v2, get_word_details, get_audio, generate_illustration, get_illustration, generate_word_definition
from handlers.static_site import get_all_words, get_words_summary, get_featured_words

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

app.route('/v2/review_next', methods=['GET'])(get_next_review_word_v2)

# Static site generation endpoints
app.route('/words', methods=['GET'])(get_all_words)
app.route('/words/summary', methods=['GET'])(get_words_summary)
app.route('/words/featured', methods=['GET'])(get_featured_words)

# Bulk data management endpoints
app.route('/api/words/generate', methods=['POST'])(generate_word_definition)

# Test vocabulary endpoints (TOEFL/IELTS)
from handlers.test_vocabulary import (
    update_test_settings,
    get_test_settings,
    add_daily_test_words,
    get_test_vocabulary_stats
)

app.route('/api/test-prep/settings', methods=['PUT'])(update_test_settings)
app.route('/api/test-prep/settings', methods=['GET'])(get_test_settings)
app.route('/api/test-prep/add-words', methods=['POST'])(add_daily_test_words)
app.route('/api/test-prep/stats', methods=['GET'])(get_test_vocabulary_stats)

@app.route('/api/test-prep/run-daily-job', methods=['POST'])
def manual_daily_job():
    """
    Manual trigger for daily test vocabulary job (for testing/admin use)
    """
    try:
        app.logger.info("Manual trigger of daily test vocabulary job")
        add_daily_test_words_for_all_users()
        return jsonify({"success": True, "message": "Daily job completed successfully"}), 200
    except Exception as e:
        app.logger.error(f"Manual daily job failed: {e}")
        return jsonify({"error": "Failed to run daily job"}), 500

def daily_test_words_worker():
    """
    Background worker that adds daily test vocabulary words for all enabled users.
    Runs at midnight every day.
    """
    while True:
        try:
            schedule.run_pending()
            time_module.sleep(60)  # Check every minute
        except Exception as e:
            app.logger.error(f"Error in daily test words scheduler: {e}")
            time_module.sleep(300)  # Wait 5 minutes on error before retrying

def add_daily_test_words_for_all_users():
    """
    Add daily test vocabulary words for all users who have test mode enabled
    """
    try:
        app.logger.info("🚀 Starting daily test vocabulary word addition for all users")

        from utils.database import get_db_connection

        conn = get_db_connection()
        cur = conn.cursor()

        # Get all users who have test mode enabled and haven't received words today
        cur.execute("""
            SELECT
                user_id,
                learning_language,
                native_language,
                toefl_enabled,
                ielts_enabled
            FROM user_preferences
            WHERE (toefl_enabled = TRUE OR ielts_enabled = TRUE)
            AND (last_test_words_added IS NULL OR last_test_words_added < CURRENT_DATE)
        """)

        users = cur.fetchall()
        app.logger.info(f"Found {len(users)} users needing daily test words")

        total_users = 0
        total_words = 0

        for user in users:
            try:
                user_id = user['user_id']
                learning_language = user['learning_language']
                native_language = user['native_language']
                toefl_enabled = user['toefl_enabled']
                ielts_enabled = user['ielts_enabled']

                # Get random test words not already saved
                cur.execute("""
                    WITH existing_words AS (
                        SELECT word
                        FROM saved_words
                        WHERE user_id = %s
                        AND learning_language = %s
                    )
                    SELECT DISTINCT tv.word
                    FROM test_vocabularies tv
                    WHERE tv.language = %s
                    AND (
                        (%s = TRUE AND tv.is_toefl = TRUE) OR
                        (%s = TRUE AND tv.is_ielts = TRUE)
                    )
                    AND tv.word NOT IN (SELECT ew.word FROM existing_words ew)
                    ORDER BY RANDOM()
                    LIMIT 10
                """, (user_id, learning_language, learning_language, toefl_enabled, ielts_enabled))

                words_to_add = cur.fetchall()
                words_added = 0

                # Add words to saved_words
                for (word,) in words_to_add:
                    cur.execute("""
                        INSERT INTO saved_words (user_id, word, learning_language, native_language)
                        VALUES (%s, %s, %s, %s)
                        ON CONFLICT DO NOTHING
                    """, (user_id, word, learning_language, native_language))
                    if cur.rowcount > 0:
                        words_added += 1

                # Update last_test_words_added date
                if words_added > 0:
                    cur.execute("""
                        UPDATE user_preferences
                        SET last_test_words_added = CURRENT_DATE
                        WHERE user_id = %s
                    """, (user_id,))

                    conn.commit()
                    total_users += 1
                    total_words += words_added
                    app.logger.info(f"Added {words_added} words for user {user_id}")

            except Exception as e:
                app.logger.error(f"Failed to add words for user {user['user_id']}: {e}")
                conn.rollback()

        cur.close()
        conn.close()

        app.logger.info(f"✅ Daily test words completed: {total_users} users, {total_words} words added")

    except Exception as e:
        app.logger.error(f"❌ Error in daily test words job: {e}")

if __name__ == '__main__':
    # Start background workers
    audio_worker_thread = threading.Thread(target=audio_generation_worker, daemon=True)
    audio_worker_thread.start()

    # Schedule daily test vocabulary words at midnight
    schedule.every().day.at("00:00").do(add_daily_test_words_for_all_users)
    app.logger.info("📅 Scheduled daily test vocabulary words at midnight")

    # Start daily test words scheduler
    test_words_scheduler_thread = threading.Thread(target=daily_test_words_worker, daemon=True)
    test_words_scheduler_thread.start()
    app.logger.info("🕒 Daily test vocabulary scheduler started")

    port = int(os.environ.get('PORT', 5000))
    app.logger.info(f"Starting Dogetionary Refactored API server on port {port}")
    app.run(host='0.0.0.0', port=port, debug=True)