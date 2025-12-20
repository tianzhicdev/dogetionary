from flask import Blueprint, jsonify
from handlers.bundle_vocabulary import batch_populate_test_vocabulary
from workers.bundle_vocabulary_worker import add_daily_test_words_for_all_users
import logging

test_prep_bp = Blueprint('test_prep', __name__)

test_prep_bp.route('/batch-populate', methods=['POST'])(batch_populate_test_vocabulary)

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