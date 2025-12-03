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
from static.privacy import PRIVACY_POLICY
from static.support import SUPPORT_HTML
from utils.database import get_db_connection
# from app import get_next_review_date_new

# Import spaced repetition functions from service layer
from services.spaced_repetition_service import get_next_review_date_new, calculate_retention, get_decay_rate

# Get logger
import logging
logger = logging.getLogger(__name__)


def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

def support_page():
    """Support page with app information and contact details"""
    
    return Response(SUPPORT_HTML, mimetype='text/html')

def privacy_agreement():
    """Display comprehensive privacy agreement and terms of service"""
    privacy_policy = PRIVACY_POLICY
    # Replace timestamp placeholder
    privacy_policy = privacy_policy.replace('{timestamp}', datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC'))
    
    return Response(privacy_policy, mimetype='text/html')



def test_review_intervals():
    """
    Test endpoint to show review intervals if word is always reviewed at predicted time.
    Shows the gaps between reviews for the first 10 reviews.
    """
    try:
        from datetime import datetime, timedelta
        import math
        
        # Start from today
        created_at = datetime.now()
        review_dates = []
        intervals = []
        
        # Simulate 10 reviews where each is done exactly at the predicted time
        current_date = created_at
        review_history = []
        
        for review_num in range(10):
            # Calculate next review date using the algorithm
            next_review_date = get_next_review_date_new(review_history, created_at)
            
            # Calculate interval in days
            if review_dates:
                interval = (next_review_date - review_dates[-1]).days
            else:
                interval = (next_review_date - created_at).days
            
            intervals.append(interval)
            review_dates.append(next_review_date)
            
            # Add this review to history (assume always successful)
            review_history.append({
                'reviewed_at': next_review_date,
                'response': True  # Always successful review
            })
        
        # Format the response
        review_schedule = []
        for i, (date, interval) in enumerate(zip(review_dates, intervals)):
            review_schedule.append({
                "review_number": i + 1,
                "date": date.strftime('%Y-%m-%d'),
                "days_from_previous": interval,
                "total_days_from_creation": (date - created_at).days
            })
        
        # Also test with some failures
        review_history_with_failures = []
        failure_schedule = []
        failure_intervals = []
        failure_dates = []
        
        for review_num in range(10):
            # Calculate next review date
            next_review_date = get_next_review_date_new(review_history_with_failures, created_at)
            
            # Calculate interval
            if failure_dates:
                interval = (next_review_date - failure_dates[-1]).days
            else:
                interval = (next_review_date - created_at).days
            
            failure_intervals.append(interval)
            failure_dates.append(next_review_date)
            
            # Add review to history - fail every 3rd review
            review_history_with_failures.append({
                'reviewed_at': next_review_date,
                'response': (review_num + 1) % 3 != 0  # Fail on reviews 3, 6, 9
            })
            
            failure_schedule.append({
                "review_number": review_num + 1,
                "date": next_review_date.strftime('%Y-%m-%d'),
                "days_from_previous": interval,
                "total_days_from_creation": (next_review_date - created_at).days,
                "result": "success" if (review_num + 1) % 3 != 0 else "failure"
            })
        
        return jsonify({
            "description": "Review intervals simulation",
            "configuration": {
                "retention_threshold": RETENTION_THRESHOLD,
                "decay_rates": {
                    "week_1": DECAY_RATE_WEEK_1,
                    "week_2": DECAY_RATE_WEEK_2,
                    "week_3_4": DECAY_RATE_WEEK_3_4,
                    "week_5_8": DECAY_RATE_WEEK_5_8,
                    "week_9_plus": DECAY_RATE_WEEK_9_PLUS
                }
            },
            "perfect_reviews": {
                "description": "All reviews done successfully at predicted time",
                "schedule": review_schedule,
                "intervals_summary": {
                    "intervals_in_days": intervals,
                    "average_interval": sum(intervals) / len(intervals) if intervals else 0,
                    "max_interval": max(intervals) if intervals else 0,
                    "min_interval": min(intervals) if intervals else 0
                }
            },
            "reviews_with_failures": {
                "description": "Reviews with failures every 3rd review",
                "schedule": failure_schedule,
                "intervals_summary": {
                    "intervals_in_days": failure_intervals,
                    "average_interval": sum(failure_intervals) / len(failure_intervals) if failure_intervals else 0,
                    "max_interval": max(failure_intervals) if failure_intervals else 0,
                    "min_interval": min(failure_intervals) if failure_intervals else 0
                }
            }
        })
        
    except Exception as e:
        logger.error(f"Error testing review intervals: {str(e)}")
        return jsonify({"error": f"Failed to test review intervals: {str(e)}"}), 500


def fix_next_review_dates():
    """
    Fix existing review records by calculating proper next_review_date using get_next_review_date_new
    Reports statistics on correct vs incorrect records
    """
    try:
        conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
        cur = conn.cursor()
        
        logger.info("Starting next_review_date fix process...")
        
        # Get all review records that have next_review_date (newest first per word)
        cur.execute("""
            WITH latest_reviews AS (
                SELECT word_id, user_id, MAX(reviewed_at) as latest_reviewed_at
                FROM reviews 
                WHERE next_review_date IS NOT NULL
                GROUP BY word_id, user_id
            )
            SELECT r.id AS id, r.word_id AS word_id, r.user_id AS user_id, r.next_review_date AS next_review_date, r.reviewed_at AS reviewed_at
            FROM reviews r
            INNER JOIN latest_reviews lr ON 
                r.word_id = lr.word_id AND 
                r.user_id = lr.user_id AND 
                r.reviewed_at = lr.latest_reviewed_at
            ORDER BY r.word_id, r.user_id
        """)
        
        records_to_check = cur.fetchall()
        print(records_to_check)
        logger.info(f"Found {len(records_to_check)} latest review records to check")
        
        stats = {
            'total_checked': 0,
            'correct_records': 0,
            'incorrect_records': 0,
            'updated_records': 0,
            'error_records': 0,
            'details': []
        }
        
        for record in records_to_check:
            record_id = record['id']
            word_id = record['word_id']
            user_id = record['user_id'] 
            current_next_review_date = record['next_review_date']
            reviewed_at = record['reviewed_at']
            stats['total_checked'] += 1

            print("record:")
            print(record)
            
            try:
                # Get word creation date
                cur.execute("""
                    SELECT created_at AS created_at FROM saved_words 
                    WHERE id = %s AND user_id = %s
                """, (word_id, user_id))
                
                word_data = cur.fetchone()
                if not word_data:
                    logger.warning(f"Word {word_id} not found for user {user_id}")
                    continue
                
                created_at = word_data['created_at']

                print("created_at")
                
                # Get all review history for this word/user combination
                cur.execute("""
                    SELECT reviewed_at AS reviewed_at, response AS response FROM reviews 
                    WHERE word_id = %s AND user_id = %s 
                    ORDER BY reviewed_at ASC
                """, (word_id, user_id))
                
                review_history = cur.fetchall()
                
                # Convert to format expected by get_next_review_date_new
                review_list = []
                for review in review_history:
                    # Handle as tuple: (reviewed_at, response)
                    reviewed_at = review['reviewed_at']
                    response = review['response']
                    review_list.append({
                        'reviewed_at': reviewed_at,
                        'response': response
                    })
                
                # Calculate correct next_review_date
                calculated_next_review_date = get_next_review_date_new(review_list, created_at)
                
                # Compare with current value (allowing for small time differences)
                current_date = datetime.fromisoformat(current_next_review_date.replace('Z', '+00:00')) if isinstance(current_next_review_date, str) else current_next_review_date
                time_diff = abs((calculated_next_review_date - current_date).total_seconds())
                print("here 0")
                # Consider dates within 1 minute as "correct" (to account for processing time differences)
                if time_diff <= 60:
                    stats['correct_records'] += 1
                    logger.info(f"Record {record_id} (word_id={word_id}): CORRECT")
                    print("here 1")
                else:
                    stats['incorrect_records'] += 1
                    print("here 2")
                    # Update the record with correct next_review_date
                    cur.execute("""
                        UPDATE reviews 
                        SET next_review_date = %s 
                        WHERE id = %s
                    """, (calculated_next_review_date, record_id))
                    
                    stats['updated_records'] += 1
                    print("here 3")
                    detail = {
                        'record_id': record_id,
                        'word_id': word_id,
                        'user_id': user_id,
                        'old_next_review_date': current_next_review_date.isoformat() if current_next_review_date else None,
                        'new_next_review_date': calculated_next_review_date.isoformat(),
                        'time_diff_seconds': time_diff,
                        'review_count': len(review_history)
                    }
                    stats['details'].append(detail)
                    print("here 4")
                    logger.info(f"Record {record_id} (word_id={word_id}): UPDATED - was {current_date}, now {calculated_next_review_date} (diff: {time_diff:.1f}s)")
                    print("here 5")
            except Exception as e:
                stats['error_records'] += 1
                logger.error(f"Error processing record {record_id}: {str(e)}")
                
                stats['details'].append({
                    'record_id': record_id,
                    'word_id': word_id,
                    'user_id': user_id,
                    'error': str(e)
                })
        
        # Commit all updates
        conn.commit()
        cur.close()
        conn.close()
        
        logger.info(f"Fix process completed: {stats['updated_records']} records updated, {stats['correct_records']} were already correct")
        
        # Prepare response
        response = {
            'success': True,
            'message': 'next_review_date fix process completed',
            'statistics': {
                'total_checked': stats['total_checked'],
                'correct_records': stats['correct_records'],
                'incorrect_records': stats['incorrect_records'],
                'updated_records': stats['updated_records'],
                'error_records': stats['error_records'],
                'correct_percentage': round((stats['correct_records'] / stats['total_checked']) * 100, 2) if stats['total_checked'] > 0 else 0
            },
            'updated_details': [d for d in stats['details'] if 'error' not in d],
            'errors': [d for d in stats['details'] if 'error' in d]
        }
        
        return jsonify(response)
        
    except Exception as e:
        logger.error(f"Error in fix_next_review_dates: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500