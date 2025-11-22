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
from handlers.admin import get_next_review_date_new, calculate_retention, get_decay_rate

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


def get_review_stats():
    """Get review statistics for a user"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get basic stats
        cur.execute("""
            SELECT COUNT(*) as total_words FROM saved_words WHERE user_id = %s
        """, (user_id,))
        total_words = cur.fetchone()['total_words']
        
        # Get reviews today
        cur.execute("""
            SELECT COUNT(*) as reviews_today 
            FROM reviews 
            WHERE user_id = %s AND DATE(reviewed_at) = CURRENT_DATE
        """, (user_id,))
        reviews_today = cur.fetchone()['reviews_today']
        
        # Get success rate last 7 days
        cur.execute("""
            SELECT 
                COUNT(*) as total_reviews,
                SUM(CASE WHEN response = true THEN 1 ELSE 0 END) as correct_reviews
            FROM reviews 
            WHERE user_id = %s AND reviewed_at >= CURRENT_DATE - INTERVAL '7 days'
        """, (user_id,))
        
        week_stats = cur.fetchone()
        success_rate = 0.0
        if week_stats['total_reviews'] > 0:
            success_rate = float(week_stats['correct_reviews']) / float(week_stats['total_reviews'])
        
        # Calculate words due today using shared function for consistency
        due_result = get_due_words_count(user_id, conn)
        due_today = due_result['due_count']
        
        
        cur.close()
        conn.close()
        
        return jsonify({
            "user_id": user_id,
            "total_words": total_words,
            "due_today": due_today,
            "reviews_today": reviews_today,
            "success_rate_7_days": success_rate
        })
        
    except Exception as e:
        logger.error(f"Error getting review stats: {str(e)}")
        return jsonify({"error": f"Failed to get review stats: {str(e)}"}), 500


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
        logger.error(f"Error getting forgetting curve: {str(e)}")
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
        logger.error(f"Error getting word details: {str(e)}")
        return jsonify({"error": f"Failed to get word details: {str(e)}"}), 500


def get_review_statistics():
    """Get comprehensive review statistics"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Total reviews
        cur.execute("SELECT COUNT(*) as count FROM reviews WHERE user_id = %s", (user_id,))
        total_reviews = cur.fetchone()['count'] or 0
        
        
        # Average reviews per week (since first review)
        cur.execute("""
            SELECT 
                MIN(reviewed_at) as first_review,
                COUNT(*) as total_count
            FROM reviews
            WHERE user_id = %s
        """, (user_id,))
        result = cur.fetchone()
        if result and result['first_review']:
            weeks_since_start = max(1, (datetime.now() - result['first_review']).days / 7)
            avg_reviews_per_week = result['total_count'] / weeks_since_start
        else:
            avg_reviews_per_week = 0
        
        # Average reviews per active day
        cur.execute("""
            SELECT COUNT(DISTINCT DATE(reviewed_at)) as active_days
            FROM reviews
            WHERE user_id = %s
        """, (user_id,))
        active_days = cur.fetchone()['active_days'] or 1
        avg_reviews_per_active_day = total_reviews / active_days if active_days > 0 else 0
        
        # Week over week change
        cur.execute("""
            WITH week_counts AS (
                SELECT 
                    COUNT(CASE WHEN reviewed_at >= NOW() - INTERVAL '7 days' THEN 1 END) as this_week,
                    COUNT(CASE WHEN reviewed_at >= NOW() - INTERVAL '14 days' 
                               AND reviewed_at < NOW() - INTERVAL '7 days' THEN 1 END) as last_week
                FROM reviews
                WHERE user_id = %s
            )
            SELECT this_week, last_week FROM week_counts
        """, (user_id,))
        result = cur.fetchone()
        this_week = result['this_week'] or 0
        last_week = result['last_week'] or 1
        week_over_week_change = ((this_week - last_week) / last_week * 100) if last_week > 0 else 0
        
        cur.close()
        conn.close()
        
        return jsonify({
            "total_reviews": total_reviews,
            "avg_reviews_per_week": round(avg_reviews_per_week, 1),
            "avg_reviews_per_active_day": round(avg_reviews_per_active_day, 1),
            "week_over_week_change": round(week_over_week_change)
        })
        
    except Exception as e:
        logger.error(f"Error getting review statistics: {str(e)}")
        return jsonify({"error": f"Failed to get review statistics: {str(e)}"}), 500



def get_weekly_review_counts():
    """Get daily review counts for the past 7 days"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get counts for past 7 days
        cur.execute("""
            WITH date_series AS (
                SELECT generate_series(
                    CURRENT_DATE - INTERVAL '6 days',
                    CURRENT_DATE,
                    '1 day'::interval
                )::date as date
            )
            SELECT 
                ds.date,
                COALESCE(COUNT(r.id), 0) as count
            FROM date_series ds
            LEFT JOIN reviews r ON DATE(r.reviewed_at) = ds.date AND r.user_id = %s
            GROUP BY ds.date
            ORDER BY ds.date ASC
        """, (user_id,))
        
        daily_counts = []
        for row in cur.fetchall():
            daily_counts.append({
                "date": row['date'].strftime('%Y-%m-%d'),
                "count": row['count']
            })
        
        cur.close()
        conn.close()
        
        return jsonify({
            "daily_counts": daily_counts
        })
        
    except Exception as e:
        logger.error(f"Error getting weekly review counts: {str(e)}")
        return jsonify({"error": f"Failed to get weekly review counts: {str(e)}"}), 500


def get_progress_funnel():
    """Get progress funnel data showing words at different memorization stages"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Stage 1: Words with any successful review
        cur.execute("""
            SELECT COUNT(DISTINCT sw.id) as count
            FROM saved_words sw
            JOIN reviews r ON sw.id = r.word_id
            WHERE sw.user_id = %s AND r.response = true
        """, (user_id,))
        stage1_count = cur.fetchone()['count'] or 0
        
        # Stage 2: Words with 2+ continuous successful reviews in past 7 days
        cur.execute("""
            WITH recent_reviews AS (
                SELECT 
                    sw.id as word_id,
                    r.response,
                    r.reviewed_at,
                    LAG(r.response) OVER (PARTITION BY sw.id ORDER BY r.reviewed_at DESC) as prev_response
                FROM saved_words sw
                JOIN reviews r ON sw.id = r.word_id
                WHERE sw.user_id = %s 
                    AND r.reviewed_at >= NOW() - INTERVAL '7 days'
            )
            SELECT COUNT(DISTINCT word_id) as count
            FROM recent_reviews
            WHERE response = true AND prev_response = true
        """, (user_id,))
        stage2_count = cur.fetchone()['count'] or 0
        
        # Stage 3: Words with 3+ successful reviews in past 14 days
        cur.execute("""
            SELECT COUNT(DISTINCT sw.id) as count
            FROM saved_words sw
            JOIN reviews r ON sw.id = r.word_id
            WHERE sw.user_id = %s 
                AND r.reviewed_at >= NOW() - INTERVAL '14 days'
                AND r.response = true
            GROUP BY sw.id
            HAVING COUNT(*) >= 3
        """, (user_id,))
        result = cur.fetchall()
        stage3_count = len(result)
        
        # Stage 4: Words with 4+ successful reviews in past 28 days
        cur.execute("""
            SELECT COUNT(DISTINCT sw.id) as count
            FROM saved_words sw
            JOIN reviews r ON sw.id = r.word_id
            WHERE sw.user_id = %s 
                AND r.reviewed_at >= NOW() - INTERVAL '28 days'
                AND r.response = true
            GROUP BY sw.id
            HAVING COUNT(*) >= 4
        """, (user_id,))
        result = cur.fetchall()
        stage4_count = len(result)
        
        # Get total saved words count
        cur.execute("""
            SELECT COUNT(*) as count
            FROM saved_words
            WHERE user_id = %s
        """, (user_id,))
        total_words = cur.fetchone()['count'] or 0
        
        cur.close()
        conn.close()
        
        logger.info(f"Progress funnel for user {user_id}: Stage1={stage1_count}, Stage2={stage2_count}, Stage3={stage3_count}, Stage4={stage4_count}")
        
        return jsonify({
            "stage1_count": stage1_count,
            "stage2_count": stage2_count,
            "stage3_count": stage3_count,
            "stage4_count": stage4_count,
            "total_words": total_words
        })
        
    except Exception as e:
        logger.error(f"Error getting progress funnel: {str(e)}")
        return jsonify({"error": f"Failed to get progress funnel: {str(e)}"}), 500

def get_review_activity():
    """Get review activity dates for calendar display"""
    try:
        user_id = request.args.get('user_id')
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        if not start_date or not end_date:
            return jsonify({"error": "start_date and end_date parameters are required"}), 400
        
        # Parse ISO date strings
        try:
            start_dt = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
            end_dt = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
        except ValueError as e:
            return jsonify({"error": f"Invalid date format: {e}"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get unique dates where user had reviews
        cur.execute("""
            SELECT DISTINCT DATE(reviewed_at) as review_date
            FROM reviews 
            WHERE user_id = %s 
            AND reviewed_at >= %s 
            AND reviewed_at <= %s
            ORDER BY review_date ASC
        """, (user_id, start_dt, end_dt))
        
        review_dates = []
        for row in cur.fetchall():
            # Format as YYYY-MM-DD string
            review_dates.append(row['review_date'].strftime('%Y-%m-%d'))
        
        cur.close()
        conn.close()
        
        logger.info(f"Found {len(review_dates)} review dates for user {user_id} between {start_date} and {end_date}")
        
        return jsonify({
            "user_id": user_id,
            "review_dates": review_dates,
            "start_date": start_date,
            "end_date": end_date
        })
        
    except Exception as e:
        logger.error(f"Error getting review activity: {str(e)}")
        return jsonify({"error": f"Failed to get review activity: {str(e)}"}), 500


def get_leaderboard():
    """Get leaderboard with all users ranked by total review count"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get all users with their review counts, name, and motto
        cur.execute("""
            SELECT 
                up.user_id,
                COALESCE(up.user_name, 'Anonymous') as user_name,
                COALESCE(up.user_motto, '') as user_motto,
                COALESCE(COUNT(r.id), 0) as total_reviews
            FROM user_preferences up
            LEFT JOIN saved_words sw ON up.user_id = sw.user_id
            LEFT JOIN reviews r ON sw.id = r.word_id
            GROUP BY up.user_id, up.user_name, up.user_motto
            ORDER BY total_reviews DESC, up.user_name ASC
        """)
        
        leaderboard = []
        rank = 1
        for row in cur.fetchall():
            leaderboard.append({
                "rank": rank,
                "user_id": row['user_id'],
                "user_name": row['user_name'],
                "user_motto": row['user_motto'], 
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
        logger.error(f"Error getting leaderboard: {str(e)}")
        return jsonify({"error": f"Failed to get leaderboard: {str(e)}"}), 500


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
        logger.error(f"Error getting leaderboard v2: {str(e)}")
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
        logger.error(f"Error getting review progress stats: {str(e)}")
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
        logger.error(f"Error getting due counts: {str(e)}")
        return jsonify({"error": f"Failed to get due counts: {str(e)}"}), 500


def get_combined_metrics():
    """Get combined metrics: lookups, reviews, and unique users over time"""
    try:
        # Get time range from query params (default to last 30 days)
        days = int(request.args.get('days', 30))

        conn = get_db_connection()
        cur = conn.cursor()

        # Get daily metrics for the past N days
        cur.execute("""
            WITH date_series AS (
                SELECT generate_series(
                    CURRENT_DATE - INTERVAL '%s days',
                    CURRENT_DATE,
                    '1 day'::interval
                )::date as date
            ),
            daily_lookups AS (
                SELECT
                    DATE(created_at) as date,
                    COUNT(*) as count
                FROM definitions
                WHERE created_at >= CURRENT_DATE - INTERVAL '%s days'
                GROUP BY DATE(created_at)
            ),
            daily_reviews AS (
                SELECT
                    DATE(reviewed_at) as date,
                    COUNT(*) as count
                FROM reviews
                WHERE reviewed_at >= CURRENT_DATE - INTERVAL '%s days'
                GROUP BY DATE(reviewed_at)
            ),
            daily_unique_users AS (
                SELECT
                    DATE(created_at) as date,
                    COUNT(DISTINCT user_id) as count
                FROM saved_words
                WHERE created_at >= CURRENT_DATE - INTERVAL '%s days'
                GROUP BY DATE(created_at)
            )
            SELECT
                ds.date,
                COALESCE(dl.count, 0) as lookups,
                COALESCE(dr.count, 0) as reviews,
                COALESCE(du.count, 0) as unique_users
            FROM date_series ds
            LEFT JOIN daily_lookups dl ON ds.date = dl.date
            LEFT JOIN daily_reviews dr ON ds.date = dr.date
            LEFT JOIN daily_unique_users du ON ds.date = du.date
            ORDER BY ds.date ASC
        """, (days, days, days, days))

        daily_metrics = []
        for row in cur.fetchall():
            daily_metrics.append({
                "date": row['date'].strftime('%Y-%m-%d'),
                "lookups": row['lookups'],
                "reviews": row['reviews'],
                "unique_users": row['unique_users']
            })

        cur.close()
        conn.close()

        return jsonify({
            "daily_metrics": daily_metrics,
            "days": days
        })

    except Exception as e:
        logger.error(f"Error getting combined metrics: {str(e)}")
        return jsonify({"error": f"Failed to get combined metrics: {str(e)}"}), 500