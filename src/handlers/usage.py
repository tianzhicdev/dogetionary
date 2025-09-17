"""
Usage analytics handlers for monitoring user activity
"""

from flask import jsonify, request
from utils.database import get_db_connection
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

def get_usage_analytics():
    """
    Get usage analytics showing:
    - Most recent user creations by time desc
    - Most recent word lookups (definitions) by time desc
    - Most recent saved words by time desc with user ID
    """
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        limit = int(request.args.get('limit', 10))

        # 1. Most recent user creations
        logger.info(f"Fetching {limit} most recent user creations")
        cur.execute("""
            SELECT
                user_id,
                user_name,
                learning_language,
                native_language,
                created_at
            FROM user_preferences
            ORDER BY created_at DESC
            LIMIT %s
        """, (limit,))

        recent_users = []
        for row in cur.fetchall():
            recent_users.append({
                'user_id': row['user_id'],
                'user_name': row['user_name'],
                'learning_language': row['learning_language'],
                'native_language': row['native_language'],
                'created_at': row['created_at'].isoformat() if row['created_at'] else None
            })

        # 2. Most recent word lookups (from definitions table)
        logger.info(f"Fetching {limit} most recent word lookups")
        cur.execute("""
            SELECT
                word,
                learning_language,
                native_language,
                created_at,
                updated_at
            FROM definitions
            ORDER BY created_at DESC
            LIMIT %s
        """, (limit,))

        recent_lookups = []
        for row in cur.fetchall():
            recent_lookups.append({
                'word': row['word'],
                'learning_language': row['learning_language'],
                'native_language': row['native_language'],
                'created_at': row['created_at'].isoformat() if row['created_at'] else None,
                'updated_at': row['updated_at'].isoformat() if row['updated_at'] else None
            })

        # 3. Most recent saved words by time desc with user ID
        logger.info(f"Fetching {limit} most recent saved words")
        cur.execute("""
            SELECT
                sw.user_id,
                sw.word,
                sw.learning_language,
                sw.created_at,
                up.user_name
            FROM saved_words sw
            LEFT JOIN user_preferences up ON sw.user_id = up.user_id
            ORDER BY sw.created_at DESC
            LIMIT %s
        """, (limit,))

        recent_saved_words = []
        for row in cur.fetchall():
            recent_saved_words.append({
                'user_id': row['user_id'],
                'user_name': row['user_name'],
                'word': row['word'],
                'learning_language': row['learning_language'],
                'created_at': row['created_at'].isoformat() if row['created_at'] else None
            })

        # 4. Additional stats
        cur.execute("SELECT COUNT(*) as total_users FROM user_preferences")
        total_users = cur.fetchone()['total_users']

        cur.execute("SELECT COUNT(*) as total_definitions FROM definitions")
        total_definitions = cur.fetchone()['total_definitions']

        cur.execute("SELECT COUNT(*) as total_saved_words FROM saved_words")
        total_saved_words = cur.fetchone()['total_saved_words']

        cur.execute("SELECT COUNT(*) as total_reviews FROM reviews")
        total_reviews = cur.fetchone()['total_reviews']

        # 5. Most active users (by saved words count)
        cur.execute("""
            SELECT
                sw.user_id,
                up.user_name,
                COUNT(sw.id) as saved_words_count,
                MAX(sw.created_at) as last_activity
            FROM saved_words sw
            LEFT JOIN user_preferences up ON sw.user_id = up.user_id
            GROUP BY sw.user_id, up.user_name
            ORDER BY saved_words_count DESC, last_activity DESC
            LIMIT %s
        """, (limit,))

        most_active_users = []
        for row in cur.fetchall():
            most_active_users.append({
                'user_id': row['user_id'],
                'user_name': row['user_name'],
                'saved_words_count': row['saved_words_count'],
                'last_activity': row['last_activity'].isoformat() if row['last_activity'] else None
            })

        cur.close()
        conn.close()

        response_data = {
            'timestamp': datetime.utcnow().isoformat(),
            'limit': limit,
            'stats': {
                'total_users': total_users,
                'total_definitions': total_definitions,
                'total_saved_words': total_saved_words,
                'total_reviews': total_reviews
            },
            'recent_user_creations': recent_users,
            'recent_word_lookups': recent_lookups,
            'recent_saved_words': recent_saved_words,
            'most_active_users': most_active_users
        }

        logger.info(f"Usage analytics retrieved successfully. Found {len(recent_users)} users, {len(recent_lookups)} lookups, {len(recent_saved_words)} saved words")

        return jsonify(response_data)

    except Exception as e:
        logger.error(f"Error fetching usage analytics: {str(e)}")
        return jsonify({
            'error': 'Failed to fetch usage analytics',
            'message': str(e)
        }), 500