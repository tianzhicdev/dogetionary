# this is legacy code, do not edit
# for any changes, we should do it in app_v3.py

from flask import Flask
import os
from dotenv import load_dotenv
import threading

# Load environment variables
load_dotenv('.env.secrets')

app = Flask(__name__)

# Import and setup logging middleware
from middleware.logging import setup_logging, log_request_info, log_response_info
from middleware.api_usage_tracker import track_request_start as track_api_usage_start, track_request_end as track_api_usage_end
from middleware.error_handler import register_error_handlers
from middleware.metrics import metrics_endpoint
from middleware.metrics_middleware import track_request_start as track_metrics_start, track_request_end as track_metrics_end

setup_logging(app)
register_error_handlers(app)

# Register middleware
app.before_request(log_request_info)
app.before_request(track_api_usage_start)
app.before_request(track_metrics_start)
app.after_request(log_response_info)
app.after_request(track_api_usage_end)
app.after_request(track_metrics_end)


from handlers.actions import save_word, delete_saved_word, delete_saved_word_v2, submit_feedback, submit_review, get_next_review_word
from handlers.users import handle_user_preferences, get_supported_languages
from handlers.reads import get_due_counts, get_review_progress_stats, get_review_stats, get_forgetting_curve, get_review_statistics, get_weekly_review_counts, get_progress_funnel, get_review_activity, get_leaderboard
from handlers.admin import test_review_intervals, fix_next_review_dates, privacy_agreement, support_page, health_check
from handlers.usage_dashboard import get_usage_dashboard
from handlers.analytics import track_user_action, get_analytics_data
from handlers.api_usage_analytics import get_api_usage_analytics
from handlers.pronunciation import practice_pronunciation, get_pronunciation_history, get_pronunciation_stats
from handlers.words import get_next_review_word_v2, audio_generation_worker, get_saved_words, get_word_definition, get_word_details, get_audio, get_illustration, generate_word_definition
from handlers.static_site import get_all_words, get_words_summary, get_featured_words

# Register all routes
app.route('/save', methods=['POST'])(save_word) # ok
app.route('/unsave', methods=['POST'])(delete_saved_word) # ok
app.route('/v2/unsave', methods=['POST'])(delete_saved_word_v2) # ok
app.route('/review_next', methods=['GET'])(get_next_review_word) # backward compatibility for old iOS versions
app.route('/due_counts', methods=['GET'])(get_due_counts) # ok
app.route('/reviews/submit', methods=['POST'])(submit_review) # returning more than needed but ok
app.route('/word', methods=['GET'])(get_word_definition)
app.route('/saved_words', methods=['GET'])(get_saved_words) # returning more than needed but ok
app.route('/users/<user_id>/preferences', methods=['GET', 'POST'])(handle_user_preferences)  # ok
app.route('/words/<int:word_id>/forgetting-curve', methods=['GET'])(get_forgetting_curve)  # might be able to simplify but ok
app.route('/words/<int:word_id>/details', methods=['GET'])(get_word_details) # might be able to simplify but ok
app.route('/audio/<path:text>/<language>')(get_audio) # ok
app.route('/languages', methods=['GET'])(get_supported_languages) # ok
app.route('/review_statistics', methods=['GET'])(get_review_statistics) # ok
app.route('/weekly_review_counts', methods=['GET'])(get_weekly_review_counts) # ok
app.route('/progress_funnel', methods=['GET'])(get_progress_funnel) # ok
app.route('/review_activity', methods=['GET'])(get_review_activity) # ok
app.route('/leaderboard', methods=['GET'])(get_leaderboard) # ok
app.route('/get-illustration', methods=['GET', 'POST'])(get_illustration) # merged: cache-first illustration endpoint
app.route('/generate-illustration', methods=['POST'])(get_illustration) # backward compatibility for old iOS versions
app.route('/feedback', methods=['POST'])(submit_feedback) # ok
app.route('/reviews/stats', methods=['GET'])(get_review_stats) # backward compatibility for old iOS versions
app.route('/reviews/progress_stats', methods=['GET'])(get_review_progress_stats) # ok
app.route('/pronunciation/practice', methods=['POST'])(practice_pronunciation) # learning lang should be word-specific but ok for now
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
    get_test_vocabulary_stats,
    manual_daily_job,
    get_test_config
)
app.route('/api/test-prep/settings', methods=['PUT'])(update_test_settings)
app.route('/api/test-prep/settings', methods=['GET'])(get_test_settings)
app.route('/api/test-prep/add-words', methods=['POST'])(add_daily_test_words)
app.route('/api/test-prep/stats', methods=['GET'])(get_test_vocabulary_stats)
app.route('/api/test-prep/config', methods=['GET'])(get_test_config)
app.route('/test-review-intervals', methods=['GET'])(test_review_intervals) 
app.route('/fix_next_review_dates', methods=['POST'])(fix_next_review_dates)
app.route('/privacy', methods=['GET'])(privacy_agreement)
app.route('/support', methods=['GET'])(support_page)
app.route('/health', methods=['GET'])(health_check)
app.route('/usage', methods=['GET'])(get_usage_dashboard)
app.route('/api/usage', methods=['GET'])(get_api_usage_analytics)
app.route('/analytics/track', methods=['POST'])(track_user_action)
app.route('/analytics/data', methods=['GET'])(get_analytics_data) # perhaps we dont need it but it is ok for now
app.route('/pronunciation/history', methods=['GET'])(get_pronunciation_history) # not used by ios
app.route('/api/test-prep/run-daily-job', methods=['POST'])(manual_daily_job)

# Prometheus metrics endpoint
app.route('/metrics', methods=['GET'])(metrics_endpoint)

# Register v3 API blueprint
try:
    from app_v3 import v3_api
    app.register_blueprint(v3_api)
    print("✅ V3 API registered successfully")  # Use print since logger may not work at module level
except Exception as e:
    print(f"❌ Failed to register V3 API: {e}")
    import traceback
    traceback.print_exc()

if __name__ == '__main__':
    # Import workers
    from workers.test_vocabulary_worker import daily_test_words_worker

    # Start background workers
    audio_worker_thread = threading.Thread(target=audio_generation_worker, daemon=True)
    audio_worker_thread.start()

    # Start daily test words scheduler
    test_words_scheduler_thread = threading.Thread(target=daily_test_words_worker, daemon=True)
    test_words_scheduler_thread.start()
    app.logger.info("🕒 Daily test vocabulary scheduler started")

    port = int(os.environ.get('PORT', 5000))
    app.logger.info(f"Starting Dogetionary Refactored API server on port {port}")
    app.run(host='0.0.0.0', port=port, debug=True)