#!/usr/bin/env python3
"""
Daily job to add test vocabulary words to users' saved words.
This script should be run once per day via cron or a task scheduler.

Example cron entry (runs at 6 AM daily):
0 6 * * * /usr/bin/python3 /path/to/daily_test_words.py
"""

import psycopg2
from psycopg2.extras import RealDictCursor
import os
import logging
from datetime import date
from typing import List, Dict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
DAILY_WORDS_COUNT = int(os.getenv('DAILY_TEST_WORDS', '10'))

def get_db_connection():
    """Get database connection"""
    db_url = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')
    return psycopg2.connect(db_url, cursor_factory=RealDictCursor)

def get_users_needing_words(conn) -> List[Dict]:
    """
    Get all users who have test mode enabled and haven't received words today
    """
    cur = conn.cursor()
    cur.execute("""
        SELECT
            user_id,
            learning_language,
            native_language,
            toefl_enabled,
            ielts_enabled,
            last_test_words_added
        FROM user_preferences
        WHERE (toefl_enabled = TRUE OR ielts_enabled = TRUE)
        AND (last_test_words_added IS NULL OR last_test_words_added < CURRENT_DATE)
    """)

    users = cur.fetchall()
    cur.close()
    return users

def add_words_for_user(conn, user_info: Dict) -> int:
    """
    Add daily test words for a single user
    Returns the number of words added
    """
    cur = conn.cursor()
    words_added = 0

    try:
        # Get random test words not already in user's saved words
        cur.execute("""
            WITH existing_words AS (
                SELECT word
                FROM saved_words
                WHERE user_id = %(user_id)s
                AND learning_language = %(learning_language)s
            )
            SELECT DISTINCT tv.word
            FROM test_vocabularies tv
            WHERE tv.language = %(learning_language)s
            AND (
                (%(toefl_enabled)s = TRUE AND tv.is_toefl = TRUE) OR
                (%(ielts_enabled)s = TRUE AND tv.is_ielts = TRUE)
            )
            AND tv.word NOT IN (SELECT word FROM existing_words)
            ORDER BY RANDOM()
            LIMIT %(limit)s
        """, {
            'user_id': user_info['user_id'],
            'learning_language': user_info['learning_language'],
            'toefl_enabled': user_info['toefl_enabled'],
            'ielts_enabled': user_info['ielts_enabled'],
            'limit': DAILY_WORDS_COUNT
        })

        words_to_add = cur.fetchall()

        # Add each word to saved_words
        for word_row in words_to_add:
            cur.execute("""
                INSERT INTO saved_words (user_id, word, learning_language, native_language)
                VALUES (%(user_id)s, %(word)s, %(learning_language)s, %(native_language)s)
                ON CONFLICT DO NOTHING
            """, {
                'user_id': user_info['user_id'],
                'word': word_row['word'],
                'learning_language': user_info['learning_language'],
                'native_language': user_info['native_language']
            })

            if cur.rowcount > 0:
                words_added += 1

        # Update last_test_words_added date if words were added
        if words_added > 0:
            cur.execute("""
                UPDATE user_preferences
                SET last_test_words_added = CURRENT_DATE
                WHERE user_id = %(user_id)s
            """, {'user_id': user_info['user_id']})

        conn.commit()

    except Exception as e:
        conn.rollback()
        logger.error(f"Error adding words for user {user_info['user_id']}: {e}")
        raise
    finally:
        cur.close()

    return words_added

def send_notification(user_id: str, words_added: int):
    """
    Send a notification to the user about new words added
    (Placeholder - implement based on your notification system)
    """
    # TODO: Implement push notification or email
    logger.info(f"Would notify user {user_id}: {words_added} new test words added")

def get_daily_stats(conn) -> Dict:
    """
    Get statistics about today's word additions
    """
    cur = conn.cursor()
    cur.execute("""
        SELECT
            COUNT(DISTINCT user_id) as users_updated,
            COUNT(*) as total_words_added
        FROM saved_words
        WHERE DATE(saved_at) = CURRENT_DATE
        AND word IN (SELECT word FROM test_vocabularies)
    """)

    stats = cur.fetchone()
    cur.close()
    return stats

def main():
    """
    Main function to run daily test word additions
    """
    logger.info("=" * 50)
    logger.info("Starting daily test vocabulary word additions")
    logger.info(f"Date: {date.today()}")
    logger.info(f"Words per user: {DAILY_WORDS_COUNT}")

    conn = get_db_connection()
    total_users = 0
    total_words = 0
    failed_users = []

    try:
        # Get users needing words
        users = get_users_needing_words(conn)
        logger.info(f"Found {len(users)} users needing daily words")

        # Process each user
        for user in users:
            try:
                words_added = add_words_for_user(conn, user)

                if words_added > 0:
                    total_users += 1
                    total_words += words_added
                    logger.info(f"User {user['user_id']}: Added {words_added} words")

                    # Send notification
                    send_notification(user['user_id'], words_added)
                else:
                    logger.info(f"User {user['user_id']}: No new words available")

            except Exception as e:
                failed_users.append(user['user_id'])
                logger.error(f"Failed to add words for user {user['user_id']}: {e}")

        # Get overall stats
        stats = get_daily_stats(conn)

        # Log summary
        logger.info("=" * 50)
        logger.info("Daily job completed")
        logger.info(f"Users processed: {total_users}")
        logger.info(f"Total words added: {total_words}")
        if failed_users:
            logger.warning(f"Failed users: {failed_users}")
        logger.info(f"Database stats - Users updated today: {stats['users_updated']}")
        logger.info(f"Database stats - Total words added today: {stats['total_words_added']}")

    except Exception as e:
        logger.error(f"Fatal error in daily job: {e}")
        raise
    finally:
        conn.close()

if __name__ == "__main__":
    main()