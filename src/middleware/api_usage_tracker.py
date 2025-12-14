"""
API Usage Tracking Middleware

Tracks all API endpoint calls with timing information to help:
- Identify which endpoints are still being used
- Determine when old API versions can be deprecated
- Monitor API performance
"""

import time
import logging
import re
from flask import request, g
from utils.database import get_db_connection
import threading

logger = logging.getLogger(__name__)

def extract_user_id():
    """Extract user_id from request (query params or JSON body)"""
    try:
        # Try query parameters first
        user_id = request.args.get('user_id')
        if user_id:
            return user_id

        # Try JSON body
        if request.is_json:
            data = request.get_json(silent=True)
            if data and 'user_id' in data:
                return data['user_id']
    except:
        pass

    return None

def extract_api_version(endpoint):
    """Extract API version from endpoint path"""
    # Check for /v2/, /v3/ etc in path
    version_match = re.search(r'/v(\d+)/', endpoint)
    if version_match:
        return f'v{version_match.group(1)}'

    # Unversioned endpoint
    return None

def log_api_usage_async(endpoint, method, user_id, status_code, duration_ms, user_agent, api_version):
    """Log API usage to database asynchronously (non-blocking)"""
    def log_to_db():
        conn = None
        cur = None
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            cur.execute("""
                INSERT INTO api_usage_logs
                (timestamp, endpoint, method, user_id, response_status, duration_ms, user_agent, api_version)
                VALUES (NOW(), %s, %s, %s, %s, %s, %s, %s)
            """, (endpoint, method, user_id, status_code, duration_ms, user_agent, api_version))

            conn.commit()
        except Exception as e:
            # Log error but don't crash the app
            logger.error(f"Failed to log API usage: {str(e)}")
        finally:
            if cur:
                cur.close()
            if conn:
                conn.close()  # Wrapper automatically returns to pool

    # Run in background thread to not block request
    thread = threading.Thread(target=log_to_db, daemon=True)
    thread.start()

def track_request_start():
    """Middleware to track request start time"""
    g.start_time = time.time()

def track_request_end(response):
    """Middleware to track request end and log to database"""
    try:
        # Calculate duration
        duration_ms = (time.time() - g.start_time) * 1000 if hasattr(g, 'start_time') else None

        # Get request info
        endpoint = request.path
        method = request.method
        user_id = extract_user_id()
        status_code = response.status_code
        user_agent = request.headers.get('User-Agent', '')
        api_version = extract_api_version(endpoint)

        # Skip logging certain endpoints to reduce noise
        skip_endpoints = ['/health', '/favicon.ico', '/static/']
        if not any(skip in endpoint for skip in skip_endpoints):
            log_api_usage_async(endpoint, method, user_id, status_code, duration_ms, user_agent, api_version)

    except Exception as e:
        # Don't let tracking errors break the response
        logger.error(f"Error in API usage tracking: {str(e)}")

    return response
