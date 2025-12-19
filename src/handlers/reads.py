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


def get_due_words_count(user_id, conn=None):
    """
    Shared function to calculate words due for review today (including overdue).
    
    Logic:
    - Words that have never been reviewed are due 1 day after being saved
    - Words with reviews are due based on their latest next_review_date
    - Uses consistent timestamp comparison (NOW() for precision)
    
    Returns dict with 'total_count' and 'due_count'
    """
    should_close_conn = conn is None
    if conn is None:
        conn = get_db_connection()
    
    try:
        cur = conn.cursor()
        
        # Single query to get both total and due counts using consistent logic
        cur.execute("""
            SELECT 
                COUNT(*) as total_count,
                COUNT(CASE 
                    WHEN COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= NOW() 
                    THEN 1 
                END) as due_count
            FROM saved_words sw
            LEFT JOIN (
                SELECT 
                    word_id,
                    next_review_date,
                    ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                FROM reviews
            ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
            WHERE sw.user_id = %s
            -- Exclude known words from due counts
            AND (sw.is_known IS NULL OR sw.is_known = FALSE)
        """, (user_id,))
        
        result = cur.fetchone()
        cur.close()
        
        return {
            'total_count': result['total_count'] or 0,
            'due_count': result['due_count'] or 0
        }
        
    finally:
        if should_close_conn:
            conn.close()


def get_forgetting_curve(word_id):
    """Get forgetting curve data for a specific word"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get word details
        cur.execute("""
            SELECT id, word, learning_language, created_at
            FROM saved_words 
            WHERE id = %s AND user_id = %s
        """, (word_id, user_id))
        
        word = cur.fetchone()
        if not word:
            return jsonify({"error": "Word not found"}), 404
        
        # Get review history
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
        
        cur.close()
        conn.close()
        
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
        return jsonify({"error": f"Failed to get forgetting curve: {str(e)}"}), 500


def get_word_details(word_id):
    """Get detailed information about a saved word"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get word details
        cur.execute("""
            SELECT id, word, learning_language, metadata, created_at
            FROM saved_words 
            WHERE id = %s AND user_id = %s
        """, (word_id, user_id))
        
        word = cur.fetchone()
        if not word:
            return jsonify({"error": "Word not found"}), 404
        
        # Get review history
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
        
        # Calculate review data
        review_count, interval_days, next_review_date, last_reviewed_at = get_word_review_data(user_id, word_id)
        
        cur.close()
        conn.close()
        
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
        return jsonify({"error": f"Failed to get word details: {str(e)}"}), 500


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


def get_review_progress_stats():
    """Get review progress statistics for ReviewGoalAchievedView"""
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # Get reviews in the past 24 hours
        cur.execute("""
            SELECT
                COUNT(*) as reviews_today,
                SUM(CASE WHEN response = true THEN 1 ELSE 0 END) as correct_reviews
            FROM reviews
            WHERE user_id = %s
            AND reviewed_at >= NOW() - INTERVAL '24 hours'
        """, (user_id,))

        review_stats = cur.fetchone()
        reviews_today = review_stats['reviews_today'] or 0
        correct_reviews = review_stats['correct_reviews'] or 0
        success_rate_today = (correct_reviews / reviews_today * 100) if reviews_today > 0 else 0

        # Get progression changes (words moving between familiarity levels)
        # This is a simplified version - in reality you'd need to track state changes
        # For now, we'll estimate based on review patterns
        cur.execute("""
            WITH word_reviews AS (
                SELECT
                    sw.word,
                    COUNT(r.id) as total_reviews,
                    SUM(CASE WHEN r.response = true THEN 1 ELSE 0 END) as correct_reviews,
                    MAX(r.reviewed_at) as last_reviewed
                FROM saved_words sw
                LEFT JOIN reviews r ON sw.id = r.word_id
                WHERE sw.user_id = %s
                AND r.reviewed_at >= NOW() - INTERVAL '24 hours'
                GROUP BY sw.word
            )
            SELECT
                COUNT(CASE WHEN total_reviews = 1 AND correct_reviews = 1 THEN 1 END) as acquainted_to_familiar,
                COUNT(CASE WHEN total_reviews >= 2 AND total_reviews < 5 AND correct_reviews = total_reviews THEN 1 END) as familiar_to_remembered,
                COUNT(CASE WHEN total_reviews >= 5 AND correct_reviews = total_reviews THEN 1 END) as remembered_to_unforgettable
            FROM word_reviews
        """, (user_id,))

        progression = cur.fetchone()

        # Get total review count for the user
        cur.execute("""
            SELECT COUNT(*) as total_reviews
            FROM reviews
            WHERE user_id = %s
        """, (user_id,))

        total_reviews_result = cur.fetchone()
        total_reviews = total_reviews_result['total_reviews'] or 0

        cur.close()
        conn.close()

        return jsonify({
            "reviews_today": reviews_today,
            "success_rate_today": round(success_rate_today, 1),
            "acquainted_to_familiar": progression['acquainted_to_familiar'] or 0,
            "familiar_to_remembered": progression['familiar_to_remembered'] or 0,
            "remembered_to_unforgettable": progression['remembered_to_unforgettable'] or 0,
            "total_reviews": total_reviews
        })

    except Exception as e:
        logger.error(f"Error getting review progress stats: {str(e)}", exc_info=True)
        return jsonify({"error": f"Failed to get review progress stats: {str(e)}"}), 500

def get_due_counts():
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        # Use shared function for consistent calculation
        result = get_due_words_count(user_id)

        return jsonify({
            "user_id": user_id,
            "overdue_count": result['due_count'],
            "total_count": result['total_count']
        })

    except Exception as e:
        logger.error(f"Error getting due counts: {str(e)}", exc_info=True)
        return jsonify({"error": f"Failed to get due counts: {str(e)}"}), 500