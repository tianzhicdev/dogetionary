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

from utils.database import validate_language, get_db_connection
from services.spaced_repetition_service import get_next_review_date_new, calculate_retention, get_decay_rate

from config.config import *

# Get logger
import logging
logger = logging.getLogger(__name__)
from static.privacy import PRIVACY_POLICY
from static.support import SUPPORT_HTML


def get_forgetting_curve(word_id):
    """Get forgetting curve data for a specific word"""
    conn = None
    cur = None
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # Get word details
        try:
            cur.execute("""
                SELECT id, word, learning_language, created_at
                FROM saved_words
                WHERE id = %s AND user_id = %s
            """, (word_id, user_id))

            word = cur.fetchone()
            if not word:
                return jsonify({"error": "Word not found"}), 404
        except Exception as e:
            logger.error(f"Error fetching word details: {str(e)}", exc_info=True)
            if conn:
                conn.rollback()
            raise

        # Get review history
        try:
            cur.execute("""
                SELECT response, reviewed_at
                FROM reviews
                WHERE word_id = %s AND user_id = %s
                ORDER BY reviewed_at ASC
            """, (word_id, user_id))

            review_history = []
            for review in cur.fetchall():
                review_history.append({
                    "response": review['response'],
                    "reviewed_at": review['reviewed_at']
                })
        except Exception as e:
            logger.error(f"Error fetching review history: {str(e)}", exc_info=True)
            if conn:
                conn.rollback()
            raise
        
        # Calculate curve data points
        created_at = word['created_at']
        
        # Calculate next review date first
        next_review_date = get_next_review_date_new(review_history, created_at)
        
        # Determine time range: from creation to next review date (or 30 days if no reviews)
        if review_history:
            # Extend the curve to the next review date for complete visualization
            end_date = next_review_date if next_review_date else max([r['reviewed_at'] for r in review_history])
        else:
            # For words with no reviews, show until next review or 30 days
            end_date = next_review_date if next_review_date else (created_at + timedelta(days=30))
        
        # Generate curve points (one per day) - use datetime throughout
        curve_points = []
        
        # Ensure we have datetime objects
        current_datetime = created_at
        end_datetime = end_date
        
        # Start from beginning of creation day
        if hasattr(current_datetime, 'date'):
            current_datetime = datetime.combine(current_datetime.date(), datetime.min.time())
        else:
            current_datetime = datetime.combine(current_datetime, datetime.min.time())
            
        # End at end of last review day
        if hasattr(end_datetime, 'date'):
            end_datetime = datetime.combine(end_datetime.date(), datetime.max.time())
        else:
            end_datetime = datetime.combine(end_datetime, datetime.max.time())
        
        # Find last review date for determining solid vs dotted line
        last_review_date = None
        if review_history:
            last_review_date = max([r['reviewed_at'] for r in review_history])
            if hasattr(last_review_date, 'date'):
                last_review_date = last_review_date.date()
        
        # Generate points for each day
        while current_datetime <= end_datetime:
            # Use end of day for retention calculation (to include same-day reviews)
            end_of_day = datetime.combine(current_datetime.date(), datetime.max.time())
            retention = calculate_retention(review_history, end_of_day, created_at)
            
            # Determine if this point is part of the solid line (historical) or dotted line (projection)
            is_projection = False
            if last_review_date and current_datetime.date() > last_review_date:
                is_projection = True
            
            curve_points.append({
                "date": current_datetime.strftime('%Y-%m-%d'),  # Display as date string
                "retention": retention * 100,  # Convert to percentage
                "is_projection": is_projection  # Flag for UI to render as dotted line
            })
            
            # Move to next day (start of day)
            current_datetime = datetime.combine((current_datetime + timedelta(days=1)).date(), datetime.min.time())
        
        # Prepare all markers including creation and next review
        all_markers = []
        
        # Add creation marker
        all_markers.append({
            "date": created_at.strftime('%Y-%m-%d'),
            "type": "creation",
            "success": None
        })
        
        # Add review markers
        for r in review_history:
            all_markers.append({
                "date": r['reviewed_at'].strftime('%Y-%m-%d'),
                "type": "review",
                "success": r['response']
            })
        
        # Add next review marker if available
        if next_review_date:
            all_markers.append({
                "date": next_review_date.strftime('%Y-%m-%d'),
                "type": "next_review",
                "success": None
            })

        return jsonify({
            "word_id": word_id,
            "word": word['word'],
            "created_at": created_at.strftime('%Y-%m-%d'),
            "forgetting_curve": curve_points,
            "next_review_date": next_review_date.strftime('%Y-%m-%d') if next_review_date else None,
            "review_markers": [
                {
                    "date": r['reviewed_at'].strftime('%Y-%m-%d'),
                    "success": r['response']
                }
                for r in review_history
            ],
            "all_markers": all_markers
        })

    except Exception as e:
        logger.error(f"Error getting forgetting curve: {str(e)}", exc_info=True)
        if conn:
            conn.rollback()
        return jsonify({"error": f"Failed to get forgetting curve: {str(e)}"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


def get_word_details(word_id):
    """Get detailed information about a saved word"""
    conn = None
    cur = None
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # Get word details
        try:
            cur.execute("""
                SELECT id, word, learning_language, metadata, created_at
                FROM saved_words
                WHERE id = %s AND user_id = %s
            """, (word_id, user_id))

            word = cur.fetchone()
            if not word:
                return jsonify({"error": "Word not found"}), 404
        except Exception as e:
            logger.error(f"Error fetching word details: {str(e)}", exc_info=True)
            if conn:
                conn.rollback()
            raise

        # Get review history
        try:
            cur.execute("""
                SELECT response, reviewed_at
                FROM reviews
                WHERE word_id = %s AND user_id = %s
                ORDER BY reviewed_at DESC
            """, (word_id, user_id))

            review_history = []
            for review in cur.fetchall():
                review_history.append({
                    "response": review['response'],
                    "response_time_ms": None,  # Simplified
                    "reviewed_at": review['reviewed_at'].strftime('%Y-%m-%d %H:%M:%S')
                })
        except Exception as e:
            logger.error(f"Error fetching review history: {str(e)}", exc_info=True)
            if conn:
                conn.rollback()
            raise

        # Calculate review data
        review_count, interval_days, next_review_date, last_reviewed_at = get_word_review_data(user_id, word_id)
        
        return jsonify({
            "id": word['id'],
            "word": word['word'],
            "learning_language": word['learning_language'],
            "metadata": word['metadata'],
            "created_at": word['created_at'].strftime('%Y-%m-%d %H:%M:%S'),
            "review_count": review_count,
            "interval_days": interval_days,
            "next_review_date": next_review_date.strftime('%Y-%m-%d %H:%M:%S') if next_review_date else None,
            "last_reviewed_at": last_reviewed_at.strftime('%Y-%m-%d %H:%M:%S') if last_reviewed_at else None,
            "review_history": review_history
        })

    except Exception as e:
        logger.error(f"Error getting word details: {str(e)}", exc_info=True)
        if conn:
            conn.rollback()
        return jsonify({"error": f"Failed to get word details: {str(e)}"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()


def get_leaderboard_v2():
    """Get leaderboard with all users ranked by score (correct=2pts, wrong=1pt)"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # Get all users with their scores, name, and motto
        # Score = 2 points for correct answers, 1 point for wrong answers
        cur.execute("""
            SELECT
                up.user_id,
                COALESCE(up.user_name, 'Anonymous') as user_name,
                COALESCE(up.user_motto, '') as user_motto,
                COALESCE(SUM(CASE WHEN r.response THEN 2 ELSE 1 END), 0) as score,
                COALESCE(COUNT(r.id), 0) as total_reviews
            FROM user_preferences up
            LEFT JOIN reviews r ON up.user_id = r.user_id
            GROUP BY up.user_id, up.user_name, up.user_motto
            ORDER BY score DESC, total_reviews DESC, up.user_name ASC
        """)

        leaderboard = []
        rank = 1
        for row in cur.fetchall():
            leaderboard.append({
                "rank": rank,
                "user_id": row['user_id'],
                "user_name": row['user_name'],
                "user_motto": row['user_motto'],
                "score": row['score'],
                "total_reviews": row['total_reviews']
            })
            rank += 1

        cur.close()
        conn.close()

        return jsonify({
            "leaderboard": leaderboard,
            "total_users": len(leaderboard)
        })

    except Exception as e:
        logger.error(f"Error getting leaderboard v2: {str(e)}", exc_info=True)
        return jsonify({"error": f"Failed to get leaderboard: {str(e)}"}), 500

def get_due_counts():
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # Use shared service for consistent due words logic
            from services.due_words_service import build_due_words_base_query, get_total_saved_words_count

            from_where_clause, params = build_due_words_base_query(user_id)

            # Count due words using shared query logic
            count_query = f"SELECT COUNT(*) as due_count {from_where_clause}"
            cur.execute(count_query, params)
            result = cur.fetchone()
            due_count = result['due_count'] if result else 0

            # Get total saved words count
            total_count = get_total_saved_words_count(user_id, conn)

            return jsonify({
                "user_id": user_id,
                "overdue_count": due_count,
                "total_count": total_count
            })

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting due counts: {str(e)}", exc_info=True)
        return jsonify({"error": f"Failed to get due counts: {str(e)}"}), 500