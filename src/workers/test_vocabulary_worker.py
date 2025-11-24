import schedule
import time
import logging
from utils.database import db_fetch_all, db_cursor

logger = logging.getLogger(__name__)

def add_daily_test_words_for_all_users():
    """Add daily test vocabulary words for all users who have test mode enabled"""
    try:
        logger.info("🚀 Starting daily test vocabulary word addition for all users")

        # Get all users who have test mode enabled and haven't received words today
        users = db_fetch_all("""
            SELECT
                user_id,
                learning_language,
                native_language,
                toefl_enabled,
                ielts_enabled,
                tianz_enabled
            FROM user_preferences
            WHERE (toefl_enabled = TRUE OR ielts_enabled = TRUE OR tianz_enabled = TRUE)
            AND (last_test_words_added IS NULL OR last_test_words_added < CURRENT_DATE)
        """)
        logger.info(f"Found {len(users)} users needing daily test words")

        total_users = 0
        total_words = 0

        for user in users:
            try:
                user_id = user['user_id']
                learning_language = user['learning_language']
                native_language = user['native_language']
                toefl_enabled = user['toefl_enabled']
                ielts_enabled = user['ielts_enabled']
                tianz_enabled = user['tianz_enabled']

                with db_cursor(commit=True) as cur:
                    # Get random test words not already saved
                    cur.execute("""
                        WITH existing_words AS (
                            SELECT word
                            FROM saved_words
                            WHERE user_id = %s
                            AND learning_language = %s
                        ),
                        available_words AS (
                            SELECT DISTINCT tv.word
                            FROM test_vocabularies tv
                            WHERE tv.language = %s
                            AND (
                                (%s = TRUE AND tv.is_toefl = TRUE) OR
                                (%s = TRUE AND tv.is_ielts = TRUE) OR
                                (%s = TRUE AND tv.is_tianz = TRUE)
                            )
                            AND tv.word NOT IN (SELECT ew.word FROM existing_words ew)
                        )
                        SELECT word FROM available_words
                        ORDER BY RANDOM()
                        LIMIT 10
                    """, (user_id, learning_language, learning_language, toefl_enabled, ielts_enabled, tianz_enabled))

                    words_to_add = cur.fetchall()
                    words_added = 0

                    # Add words to saved_words
                    for word_row in words_to_add:
                        word = word_row['word']
                        cur.execute("""
                            INSERT INTO saved_words (user_id, word, learning_language, native_language)
                            VALUES (%s, %s, %s, %s)
                            ON CONFLICT DO NOTHING
                        """, (user_id, word, learning_language, native_language))
                        if cur.rowcount > 0:
                            words_added += 1

                    # Update last_test_words_added date
                    if words_added > 0:
                        cur.execute("""
                            UPDATE user_preferences
                            SET last_test_words_added = CURRENT_DATE
                            WHERE user_id = %s
                        """, (user_id,))

                        total_users += 1
                        total_words += words_added
                        logger.info(f"Added {words_added} words for user {user_id}")

            except Exception as e:
                logger.error(f"Failed to add words for user {user['user_id']}: {e}")

        logger.info(f"✅ Daily test words completed: {total_users} users, {total_words} words added")

    except Exception as e:
        logger.error(f"❌ Error in daily test words job: {e}")

def daily_test_words_worker():
    """
    Background worker that adds daily test vocabulary words for all enabled users.
    Runs at midnight every day.
    """
    # Schedule daily test vocabulary words at midnight
    schedule.every().day.at("00:00").do(add_daily_test_words_for_all_users)
    logger.info("📅 Scheduled daily test vocabulary words at midnight")

    while True:
        try:
            schedule.run_pending()
            time.sleep(60)  # Check every minute
        except Exception as e:
            logger.error(f"Error in daily test words scheduler: {e}")
            time.sleep(300)  # Wait 5 minutes on error before retrying