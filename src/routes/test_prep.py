from flask import Blueprint, jsonify
from handlers.bundle_vocabulary import (
    update_test_settings, get_test_settings,
    add_daily_test_words, get_test_vocabulary_stats,
    get_test_vocabulary_count, batch_populate_test_vocabulary,
    get_test_config
)
from workers.bundle_vocabulary_worker import add_daily_test_words_for_all_users
import logging

test_prep_bp = Blueprint('test_prep', __name__)

test_prep_bp.route('/settings', methods=['PUT'])(update_test_settings)
test_prep_bp.route('/settings', methods=['GET'])(get_test_settings)
test_prep_bp.route('/add-words', methods=['POST'])(add_daily_test_words)
test_prep_bp.route('/stats', methods=['GET'])(get_test_vocabulary_stats)
test_prep_bp.route('/vocabulary-count', methods=['GET'])(get_test_vocabulary_count)
test_prep_bp.route('/batch-populate', methods=['POST'])(batch_populate_test_vocabulary)
test_prep_bp.route('/config', methods=['GET'])(get_test_config)

@test_prep_bp.route('/run-daily-job', methods=['POST'])
def manual_daily_job():
    """Manual trigger for daily test vocabulary job"""
    try:
        logging.info("Manual trigger of daily test vocabulary job")
        add_daily_test_words_for_all_users()
        return jsonify({"success": True, "message": "Daily job completed successfully"}), 200
    except Exception as e:
        logging.error(f"Manual daily job failed: {e}")
        return jsonify({"error": "Failed to run daily job"}), 500