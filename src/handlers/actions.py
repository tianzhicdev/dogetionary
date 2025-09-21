
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
from utils.database import validate_language, get_db_connection
from services.user_service import get_user_preferences
from app import get_next_review_date_new

# Get logger from current app context
import logging
logger = logging.getLogger(__name__)

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
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            INSERT INTO saved_words (user_id, word, learning_language, native_language, metadata)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT ON CONSTRAINT saved_words_user_id_word_learning_language_native_language_key
            DO UPDATE SET metadata = EXCLUDED.metadata
            RETURNING id, created_at
        """, (user_id, word, learning_lang, native_lang, json.dumps(metadata)))
        
        result = cur.fetchone()
        conn.commit()
        conn.close()
        
        return jsonify({
            "success": True,
            "message": f"Word '{word}' saved successfully",
            "word_id": result['id'],
            "created_at": result['created_at'].isoformat()
        }), 201
    
    except Exception as e:
        logger.error(f"Error saving word: {str(e)}")
        return jsonify({"error": f"Failed to save word: {str(e)}"}), 500

def delete_saved_word():
    """Delete a saved word and all associated reviews (cascade delete)"""
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

        conn = get_db_connection()
        cur = conn.cursor()

        # Delete the saved word (reviews will cascade delete automatically)
        # Include user_id check for security
        cur.execute("""
            DELETE FROM saved_words
            WHERE id = %s AND user_id = %s
            RETURNING id, word
        """, (word_id, user_id))

        deleted = cur.fetchone()
        conn.commit()
        conn.close()

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
        logger.error(f"Error deleting saved word: {str(e)}")
        return jsonify({"error": f"Failed to delete saved word: {str(e)}"}), 500

def get_next_review_word():
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Find word with earliest next review date (due now or overdue)
        cur.execute("""
            SELECT
                sw.id,
                sw.word,
                sw.learning_language,
                sw.native_language,
                sw.metadata,
                sw.created_at,
                COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') as next_review_date,
                COALESCE(latest_review.review_count, 0) as review_count,
                latest_review.last_reviewed_at,
                CASE 
                    WHEN latest_review.last_reviewed_at IS NOT NULL AND latest_review.next_review_date IS NOT NULL 
                    THEN EXTRACT(epoch FROM (latest_review.next_review_date - latest_review.last_reviewed_at)) / 86400
                    WHEN latest_review.next_review_date IS NOT NULL
                    THEN EXTRACT(epoch FROM (latest_review.next_review_date - sw.created_at)) / 86400
                    ELSE 1
                END as interval_days
            FROM saved_words sw
            LEFT JOIN (
                SELECT 
                    word_id,
                    next_review_date,
                    reviewed_at as last_reviewed_at,
                    COUNT(*) as review_count,
                    ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                FROM reviews
                GROUP BY word_id, next_review_date, reviewed_at
            ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
            WHERE sw.user_id = %s 
            -- Exclude words reviewed in the past 24 hours
            AND (latest_review.last_reviewed_at IS NULL OR latest_review.last_reviewed_at <= NOW() - INTERVAL '24 hours')
            -- AND COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= NOW()
            ORDER BY COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') ASC
            LIMIT 1
        """, (user_id,))
        
        word = cur.fetchone()
        cur.close()
        conn.close()
        
        if not word:
            return jsonify({
                "user_id": user_id,
                "saved_words": [],
                "count": 0
            })
        
        return jsonify({
            "user_id": user_id,
            "saved_words": [{
                "id": word['id'],
                "word": word['word'],
                "learning_language": word['learning_language'],
                "native_language": word['native_language']
            }],
            "count": 1
        })
        
    except Exception as e:
        logger.error(f"Error getting next review word: {str(e)}")
        return jsonify({"error": f"Failed to get next review word: {str(e)}"}), 500

def submit_review():
    try:
        data = request.get_json()
        
        user_id = data.get('user_id')
        word_id = data.get('word_id')
        response = data.get('response')
        
        if not all([user_id, word_id is not None, response is not None]):
            return jsonify({"error": "user_id, word_id, and response are required"}), 400
        
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Record the current review time
        current_review_time = datetime.now()
        
        # Get existing review data and word creation date
        cur.execute("""
            SELECT sw.created_at
            FROM saved_words sw
            WHERE sw.id = %s AND sw.user_id = %s
        """, (word_id, user_id))
        
        word_data = cur.fetchone()
        if not word_data:
            return jsonify({"error": "Word not found"}), 404
            
        created_at = word_data['created_at']
        
        cur.execute("""
            SELECT response, reviewed_at FROM reviews 
            WHERE user_id = %s AND word_id = %s 
            ORDER BY reviewed_at ASC
        """, (user_id, word_id))
        
        existing_reviews = [{"response": row['response'], "reviewed_at": row['reviewed_at']} for row in cur.fetchall()]
        
        # Add current review to history for next review calculation
        all_reviews = existing_reviews + [{"response": response, "reviewed_at": current_review_time}]
        
        # Calculate next review date using new algorithm
        next_review_date = get_next_review_date_new(all_reviews, created_at)
        
        # Insert the new review with calculated next_review_date
        cur.execute("""
            INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date)
            VALUES (%s, %s, %s, %s, %s)
        """, (user_id, word_id, response, current_review_time, next_review_date))
        
        conn.commit()
        
        # Calculate simple stats for response
        review_count = len(all_reviews)
        interval_days = (next_review_date - current_review_time).days if next_review_date else 1
        
        conn.close()
        
        return jsonify({
            "success": True,
            "word_id": word_id,
            "response": response,
            "review_count": review_count,
            "ease_factor": 2.5,
            "interval_days": interval_days,
            "next_review_date": next_review_date.isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error submitting review: {str(e)}")
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

        conn = get_db_connection()
        cur = conn.cursor()

        # Insert feedback
        cur.execute("""
            INSERT INTO user_feedback (user_id, feedback)
            VALUES (%s, %s)
            RETURNING id, created_at
        """, (user_id, feedback))

        result = cur.fetchone()
        feedback_id = result['id']
        created_at = result['created_at']

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({
            "success": True,
            "message": "Thank you for your feedback!",
            "feedback_id": feedback_id,
            "created_at": created_at.isoformat()
        }), 201

    except Exception as e:
        logger.error(f"Error submitting feedback: {str(e)}")
        return jsonify({"error": f"Failed to submit feedback: {str(e)}"}), 500