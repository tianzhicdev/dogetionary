from flask import Blueprint, jsonify
from handlers.test_vocabulary import (
    update_test_settings, get_test_settings,
    add_daily_test_words, get_test_vocabulary_stats,
    get_test_vocabulary_count, batch_populate_test_vocabulary
)
from workers.test_vocabulary_worker import add_daily_test_words_for_all_users
import logging

test_prep_bp = Blueprint('test_prep', __name__)

test_prep_bp.route('/settings', methods=['PUT'])(update_test_settings)
test_prep_bp.route('/settings', methods=['GET'])(get_test_settings)
test_prep_bp.route('/add-words', methods=['POST'])(add_daily_test_words)
test_prep_bp.route('/stats', methods=['GET'])(get_test_vocabulary_stats)
test_prep_bp.route('/vocabulary-count', methods=['GET'])(get_test_vocabulary_count)
test_prep_bp.route('/batch-populate', methods=['POST'])(batch_populate_test_vocabulary)

@test_prep_bp.route('/config', methods=['GET'])
def get_test_config_endpoint():
    """
    Get test vocabulary configuration mapping languages to available tests.
    Returns which tests are available for each learning language.
    """
    try:
        # Static configuration - in the future this could be database-driven
        config = {
            "en": {
                "tests": [
                    {
                        "code": "TOEFL",
                        "name": "TOEFL Preparation",
                        "description": "Test of English as a Foreign Language",
                        "testing_only": False
                    },
                    {
                        "code": "IELTS",
                        "name": "IELTS Preparation",
                        "description": "International English Language Testing System",
                        "testing_only": False
                    },
                    {
                        "code": "DEMO",
                        "name": "Tianz Test",
                        "description": "Testing vocabulary list (20 words)",
                        "testing_only": True  # Only visible in developer mode
                    }
                ]
            },
            # Future language support
            "fr": {"tests": []},
            "es": {"tests": []},
            "de": {"tests": []},
            "it": {"tests": []},
            "pt": {"tests": []},
            "ja": {"tests": []},
            "ko": {"tests": []},
            "zh": {"tests": []}
        }

        logging.info("Test configuration fetched successfully")
        return jsonify({"config": config}), 200

    except Exception as e:
        logging.error(f"Error getting test config: {e}")
        return jsonify({"error": "Internal server error"}), 500

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