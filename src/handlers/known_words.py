"""
Known Words Handler

This module provides functions to:
- Mark words as known/learning
- Known words are excluded from reviews and schedules
"""

from flask import jsonify, request
import sys
import os
import uuid
import logging

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utils.database import db_execute, db_fetch_one

logger = logging.getLogger(__name__)


def mark_word_known(word_id):
    """
    POST /v3/words/<word_id>/mark-known
    Mark a word as known or learning.

    Request body:
        {
            "user_id": "uuid",
            "is_known": true/false
        }

    Response:
        {
            "success": true,
            "word_id": 123,
            "is_known": true
        }
    """
    try:
        # Validate word_id is an integer
        try:
            word_id = int(word_id)
        except ValueError:
            return jsonify({"error": "Invalid word_id format"}), 400

        # Get request body
        data = request.get_json()
        if not data:
            return jsonify({"error": "Request body is required"}), 400

        user_id = data.get('user_id')
        is_known = data.get('is_known')

        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        if is_known is None:
            return jsonify({"error": "is_known is required"}), 400

        # Validate UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400

        # Verify word belongs to user
        word = db_fetch_one("""
            SELECT id FROM saved_words
            WHERE id = %s AND user_id = %s
        """, (word_id, user_id))

        if not word:
            return jsonify({"error": "Word not found or does not belong to user"}), 404

        # Update is_known status
        db_execute("""
            UPDATE saved_words
            SET is_known = %s
            WHERE id = %s AND user_id = %s
        """, (is_known, word_id, user_id), commit=True)

        logger.info(f"Word {word_id} marked as {'known' if is_known else 'learning'} for user {user_id}")

        return jsonify({
            "success": True,
            "word_id": word_id,
            "is_known": is_known
        }), 200

    except Exception as e:
        logger.error(f"Error in mark_word_known: {str(e)}")
        return jsonify({"error": "Internal server error"}), 500
