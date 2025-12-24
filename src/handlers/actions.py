
from flask import Flask, request, jsonify, Response, g
import os
from dotenv import load_dotenv
import openai
from typing import Optional, Dict, Any
import json
import psycopg2
from psycopg2.extras import RealDictCursor
import uuid
from datetime import datetime, timedelta
import io
import math
import threading
import queue
import time
import base64
import logging
import sys
import os

# Add parent directory to Python path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from config.config import *
from utils.database import validate_language, get_db_connection, db_insert_returning, db_cursor, db_fetch_one, db_fetch_all, db_execute
from services.user_service import get_user_preferences
from services.spaced_repetition_service import get_next_review_date_new
from handlers.achievements import (
    calculate_user_score,
    get_newly_earned_score_badges,
    check_test_completion_badges,
    count_test_vocabulary_progress
)
from handlers.bundle_vocabulary import get_active_test_type, TEST_TYPE_MAPPING

# Get logger from current app context
import logging
logger = logging.getLogger(__name__)


def get_or_create_saved_word(user_id: str, word: str, learning_language: str, native_language: str, cur) -> tuple:
    """
    Get existing saved_word or create new one if it doesn't exist.

    Args:
        user_id: User UUID string
        word: The word to save
        learning_language: Learning language code
        native_language: Native language code
        cur: Database cursor (for transaction support)

    Returns:
        Tuple of (word_id, created_at)
    """
    # Look up word in saved_words using composite key
    cur.execute("""
        SELECT id, created_at
        FROM saved_words
        WHERE user_id = %s AND word = %s AND learning_language = %s AND native_language = %s
    """, (user_id, word, learning_language, native_language))
    word_data = cur.fetchone()

    if word_data:
        # Word already saved
        return word_data['id'], word_data['created_at']
    else:
        # Word not saved yet - save it now
        cur.execute("""
            INSERT INTO saved_words (user_id, word, learning_language, native_language)
            VALUES (%s, %s, %s, %s)
            RETURNING id, created_at
        """, (user_id, word, learning_language, native_language))
        new_word = cur.fetchone()
        logger.info(f"Created new saved_word for '{word}' (id={new_word['id']}) for user {user_id}")
        return new_word['id'], new_word['created_at']


def save_word():
    try:
        data = request.get_json()
        
        if not data or 'word' not in data or 'user_id' not in data:
            return jsonify({"error": "Both 'word' and 'user_id' are required"}), 400
        
        word = data['word'].strip().lower()
        user_id = data['user_id']
        learning_lang = data.get('learning_language', 'en')
        native_lang = data.get('native_language')  # Can be None for v1.0.9 clients
        metadata = data.get('metadata', {})

        # Get user preferences if any language is missing
        if 'learning_language' not in data or native_lang is None:
            stored_learning_lang, stored_native_lang, _, _ = get_user_preferences(user_id)
            if 'learning_language' not in data:
                learning_lang = stored_learning_lang
            if native_lang is None:  # Fallback for v1.0.9 clients
                native_lang = stored_native_lang

        # Validate provided languages
        if not validate_language(learning_lang):
            return jsonify({"error": f"Unsupported learning language: {learning_lang}"}), 400
        if not validate_language(native_lang):
            return jsonify({"error": f"Unsupported native language: {native_lang}"}), 400
        
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        result = db_insert_returning("""
            INSERT INTO saved_words (user_id, word, learning_language, native_language, metadata)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT ON CONSTRAINT saved_words_user_id_word_learning_language_native_language_key
            DO UPDATE SET metadata = EXCLUDED.metadata
            RETURNING id, created_at
        """, (user_id, word, learning_lang, native_lang, json.dumps(metadata)))
        
        return jsonify({
            "success": True,
            "message": f"Word '{word}' saved successfully",
            "word_id": result['id'],
            "created_at": result['created_at'].isoformat()
        }), 201
    
    except Exception as e:
        logger.error(f"Error saving word: {str(e)}", exc_info=True)
        return jsonify({"error": f"Failed to save word: {str(e)}"}), 500

def delete_saved_word_v2():
    """Delete a saved word using word_id - v1.0.10+ clients"""
    logger.info(f"V2 UNSAVE ENDPOINT HIT - Method: {request.method}")
    try:
        data = request.get_json()

        if not data or 'user_id' not in data:
            return jsonify({"error": "user_id is required"}), 400

        if 'word_id' not in data:
            return jsonify({"error": "word_id is required"}), 400

        word_id = data['word_id']
        user_id = data['user_id']
        # Ignore learning_language if provided (for backward compatibility)

        # Validate UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400

        # Validate word_id is integer
        try:
            word_id = int(word_id)
        except (ValueError, TypeError):
            return jsonify({"error": "Invalid word_id format. Must be an integer"}), 400

        with db_cursor(commit=True) as cur:
            # Delete the saved word (reviews will cascade delete automatically)
            cur.execute("""
                DELETE FROM saved_words
                WHERE id = %s AND user_id = %s
                RETURNING id, word
            """, (word_id, user_id))

            deleted = cur.fetchone()

        if deleted:
            return jsonify({
                "success": True,
                "message": f"Word '{deleted['word']}' removed from saved words",
                "deleted_word_id": deleted['id']
            }), 200
        else:
            return jsonify({
                "error": f"Word with ID {word_id} not found in saved words"
            }), 404

    except Exception as e:
        logger.error(f"Error deleting saved word: {str(e)}", exc_info=True)
        return jsonify({"error": f"Failed to delete saved word: {str(e)}"}), 500

def submit_review():
    """
    Submit a review for a word.

    Uses composite key (word, learning_language, native_language) to identify words.
    If word is not yet saved, it will be saved first.
    """
    try:
        data = request.get_json()

        user_id = data.get('user_id')
        word = data.get('word')
        learning_language = data.get('learning_language')
        native_language = data.get('native_language')
        response = data.get('response')

        if not all([user_id, word, learning_language, native_language, response is not None]):
            return jsonify({"error": "user_id, word, learning_language, native_language, and response are required"}), 400

        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400

        # Record the current review time
        current_review_time = datetime.now()

        # Use a single connection for the entire transaction
        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # Get or create saved_word
            word_id, created_at = get_or_create_saved_word(user_id, word, learning_language, native_language, cur)

            # Get existing reviews
            cur.execute("""
                SELECT response, reviewed_at FROM reviews
                WHERE user_id = %s AND word_id = %s
                ORDER BY reviewed_at ASC
            """, (user_id, word_id))
            reviews_data = cur.fetchall()

            existing_reviews = [{"response": row['response'], "reviewed_at": row['reviewed_at']} for row in reviews_data]

            # Add current review to history for next review calculation
            all_reviews = existing_reviews + [{"response": response, "reviewed_at": current_review_time}]

            # Calculate next review date using new algorithm
            next_review_date = get_next_review_date_new(all_reviews, created_at)

            # Insert the new review with calculated next_review_date
            # Convert response to boolean (1 = correct/true, 0 = incorrect/false)
            response_bool = bool(response)
            # Note: question_type is optional and not stored in base reviews table
            cur.execute("""
                INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date)
                VALUES (%s, %s, %s, %s, %s)
            """, (user_id, word_id, response_bool, current_review_time, next_review_date))

            conn.commit()
        except Exception as e:
            conn.rollback()
            raise e
        finally:
            cur.close()
            conn.close()

        # Calculate new score AFTER inserting review
        new_score = calculate_user_score(user_id)

        # Calculate practice status for immediate UI update (avoids separate API calls)
        from handlers.streaks import calculate_streak_days

        # Get practice counts
        due_count_row = db_fetch_one("""
            SELECT COUNT(DISTINCT sw.id) as cnt
            FROM saved_words sw
            LEFT JOIN (
                SELECT word_id, next_review_date,
                       ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                FROM reviews
            ) r ON sw.id = r.word_id AND r.rn = 1
            WHERE sw.user_id = %s
            AND (sw.is_known IS NULL OR sw.is_known = FALSE)
            AND (
                r.next_review_date IS NULL OR
                r.next_review_date <= CURRENT_DATE
            )
        """, (user_id,))
        due_word_count = due_count_row['cnt'] if due_count_row else 0

        new_count_row = db_fetch_one("""
            SELECT COUNT(*) as cnt
            FROM saved_words
            WHERE user_id = %s
            AND created_at >= NOW() - INTERVAL '24 hours'
        """, (user_id,))
        new_word_count_past_24h = new_count_row['cnt'] if new_count_row else 0

        total_count_row = db_fetch_one("""
            SELECT COUNT(*) as cnt
            FROM saved_words
            WHERE user_id = %s
        """, (user_id,))
        total_word_count = total_count_row['cnt'] if total_count_row else 0

        reviews_24h_row = db_fetch_one("""
            SELECT COUNT(*) as cnt
            FROM reviews
            WHERE user_id = %s
            AND reviewed_at >= NOW() - INTERVAL '24 hours'
        """, (user_id,))
        reviews_past_24h = reviews_24h_row['cnt'] if reviews_24h_row else 0

        streak_days = calculate_streak_days(user_id)
        has_practice = due_word_count > 0

        # Calculate bundle progress (if user has active test type)
        bundle_progress = None
        prefs = db_fetch_one("""
            SELECT * FROM user_preferences WHERE user_id = %s
        """, (user_id,))

        if prefs:
            active_test_type = get_active_test_type(prefs)
            if active_test_type and active_test_type in TEST_TYPE_MAPPING:
                vocab_column = TEST_TYPE_MAPPING[active_test_type][2]  # e.g., 'is_toefl_beginner'
                progress = count_test_vocabulary_progress(user_id, vocab_column, learning_language)
                bundle_progress = {
                    "saved_words": progress["saved_words"],
                    "total_words": progress["total_words"],
                    "percentage": round(progress["saved_words"] / progress["total_words"] * 100) if progress["total_words"] > 0 else 0
                }

        return jsonify({
            "success": True,
            "word": word,
            "word_id": word_id,
            "response": response,
            "new_score": new_score,
            "new_badges": None,
            "practice_status": {
                "user_id": user_id,
                "due_word_count": due_word_count,
                "new_word_count_past_24h": new_word_count_past_24h,
                "total_word_count": total_word_count,
                "score": new_score,
                "has_practice": has_practice,
                "reviews_past_24h": reviews_past_24h,
                "streak_days": streak_days,
                "bundle_progress": bundle_progress
            }
        })

    except Exception as e:
        logger.error(f"Error submitting review: {str(e)}", exc_info=True)
        return jsonify({"error": f"Failed to submit review: {str(e)}"}), 500


def submit_feedback():
    """Submit user feedback"""
    try:
        data = request.json
        user_id = data.get('user_id')
        feedback = data.get('feedback')

        # Validate inputs
        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        if not feedback:
            return jsonify({"error": "feedback is required"}), 400

        # Validate feedback length
        if len(feedback) > 500:
            return jsonify({"error": "Feedback must be 500 characters or less"}), 400

        # Validate UUID format
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format"}), 400

        # Insert feedback
        result = db_insert_returning("""
            INSERT INTO user_feedback (user_id, feedback)
            VALUES (%s, %s)
            RETURNING id, created_at
        """, (user_id, feedback))

        feedback_id = result['id']
        created_at = result['created_at']

        return jsonify({
            "success": True,
            "message": "Thank you for your feedback!",
            "feedback_id": feedback_id,
            "created_at": created_at.isoformat()
        }), 201

    except Exception as e:
        logger.error(f"Error submitting feedback: {str(e)}", exc_info=True)
        return jsonify({"error": f"Failed to submit feedback: {str(e)}"}), 500