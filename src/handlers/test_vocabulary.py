"""
Test vocabulary handlers for TOEFL/IELTS preparation features
"""

from flask import jsonify, request
from datetime import datetime, date
import logging
import sys
import os
from typing import Dict, Any, Optional

# Add parent directory to Python path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utils.database import get_db_connection

logger = logging.getLogger(__name__)

# Configuration
DAILY_TEST_WORDS = 10  # Number of words to add per day (compile-time configurable)

def update_test_settings():
    """
    Update user's test preparation settings (enable/disable TOEFL/IELTS)
    """
    try:
        data = request.get_json()
        user_id = data.get('user_id')

        if not user_id:
            return jsonify({"error": "User ID is required"}), 400

        # Get optional parameters
        toefl_enabled = data.get('toefl_enabled')
        ielts_enabled = data.get('ielts_enabled')

        if toefl_enabled is None and ielts_enabled is None:
            return jsonify({"error": "At least one setting must be provided"}), 400

        conn = get_db_connection()
        cur = conn.cursor()
        try:

            # Build dynamic update query
            update_fields = []
            params = []

            if toefl_enabled is not None:
                update_fields.append("toefl_enabled = %s")
                params.append(toefl_enabled)

            if ielts_enabled is not None:
                update_fields.append("ielts_enabled = %s")
                params.append(ielts_enabled)

            # If disabling all tests, clear the last_test_words_added date
            if toefl_enabled == False and ielts_enabled == False:
                update_fields.append("last_test_words_added = NULL")

            params.append(user_id)

            # Update user preferences
            cur.execute(f"""
                UPDATE user_preferences
                SET {', '.join(update_fields)}
                WHERE user_id = %s
                RETURNING toefl_enabled, ielts_enabled, last_test_words_added
            """, params)

            result = cur.fetchone()
            conn.commit()

            if result:
                return jsonify({
                    "success": True,
                    "settings": {
                        "toefl_enabled": result[0],
                        "ielts_enabled": result[1],
                        "last_test_words_added": result[2].isoformat() if result[2] else None
                    }
                }), 200
            else:
                return jsonify({"error": "User not found"}), 404

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error updating test settings: {e}")
        return jsonify({"error": "Internal server error"}), 500


def get_test_settings():
    """
    Get user's current test preparation settings
    """
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "User ID is required"}), 400

        conn = get_db_connection()
        cur = conn.cursor()
        try:

            # Get current settings and progress
            cur.execute("""
                WITH user_settings AS (
                    SELECT
                        up.toefl_enabled,
                        up.ielts_enabled,
                        up.last_test_words_added,
                        up.learning_language,
                        up.native_language
                    FROM user_preferences up
                    WHERE up.user_id = %s
                ),
                progress AS (
                    SELECT
                        COUNT(DISTINCT CASE WHEN tv.is_toefl THEN sw.word END) as toefl_saved,
                        COUNT(DISTINCT CASE WHEN tv.is_ielts THEN sw.word END) as ielts_saved
                    FROM saved_words sw
                    LEFT JOIN test_vocabularies tv ON tv.word = sw.word
                    WHERE sw.user_id = %s
                ),
                totals AS (
                    SELECT
                        COUNT(DISTINCT CASE WHEN is_toefl THEN word END) as total_toefl,
                        COUNT(DISTINCT CASE WHEN is_ielts THEN word END) as total_ielts
                    FROM test_vocabularies
                    WHERE language = 'en'
                )
                SELECT
                    us.*,
                    p.toefl_saved,
                    p.ielts_saved,
                    t.total_toefl,
                    t.total_ielts
                FROM user_settings us
                CROSS JOIN progress p
                CROSS JOIN totals t
            """, (user_id, user_id))

            result = cur.fetchone()

            if result:
                return jsonify({
                    "settings": {
                        "toefl_enabled": result[0],
                        "ielts_enabled": result[1],
                        "last_test_words_added": result[2].isoformat() if result[2] else None,
                        "learning_language": result[3],
                        "native_language": result[4]
                    },
                    "progress": {
                        "toefl": {
                            "saved": result[5],
                            "total": result[7],
                            "percentage": round(100 * result[5] / result[7], 1) if result[7] > 0 else 0
                        },
                        "ielts": {
                            "saved": result[6],
                            "total": result[8],
                            "percentage": round(100 * result[6] / result[8], 1) if result[8] > 0 else 0
                        }
                    }
                }), 200
            else:
                return jsonify({"error": "User not found"}), 404

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting test settings: {e}")
        return jsonify({"error": "Internal server error"}), 500


def add_daily_test_words():
    """
    Add daily test vocabulary words to user's saved words.
    This can be called manually or by a scheduled job.
    """
    try:
        data = request.get_json()
        user_id = data.get('user_id')

        if not user_id:
            return jsonify({"error": "User ID is required"}), 400

        learning_language = data.get('learning_language', 'en')
        native_language = data.get('native_language', 'zh')

        conn = get_db_connection()
        cur = conn.cursor()
        try:

            # Check if user has test mode enabled
            cur.execute("""
                SELECT toefl_enabled, ielts_enabled, last_test_words_added
                FROM user_preferences
                WHERE user_id = %s
            """, (user_id,))

            settings = cur.fetchone()

            if not settings:
                return jsonify({"error": "User not found"}), 404

            toefl_enabled, ielts_enabled, last_added = settings

            if not toefl_enabled and not ielts_enabled:
                return jsonify({"error": "Test preparation mode is not enabled"}), 400

            # Check if words were already added today
            if last_added and last_added >= date.today():
                return jsonify({
                    "message": "Daily words already added",
                    "next_available": (date.today().replace(day=date.today().day + 1)).isoformat()
                }), 200

            # Get random test words not already saved
            cur.execute("""
                WITH existing_words AS (
                    SELECT word
                    FROM saved_words
                    WHERE user_id = %s
                    AND learning_language = %s
                )
                SELECT DISTINCT tv.word
                FROM test_vocabularies tv
                WHERE tv.language = %s
                AND (
                    (%s = TRUE AND tv.is_toefl = TRUE) OR
                    (%s = TRUE AND tv.is_ielts = TRUE)
                )
                AND tv.word NOT IN (SELECT word FROM existing_words)
                ORDER BY RANDOM()
                LIMIT %s
            """, (user_id, learning_language, learning_language, toefl_enabled, ielts_enabled, DAILY_TEST_WORDS))

            words_to_add = cur.fetchall()

            if not words_to_add:
                return jsonify({
                    "message": "No new words available",
                    "reason": "All test vocabulary words have been added"
                }), 200

            # Add words to saved_words
            added_words = []
            for (word,) in words_to_add:
                cur.execute("""
                    INSERT INTO saved_words (user_id, word, learning_language, native_language)
                    VALUES (%s, %s, %s, %s)
                    ON CONFLICT DO NOTHING
                    RETURNING word
                """, (user_id, word, learning_language, native_language))

                if cur.fetchone():
                    added_words.append(word)

            # Update last_test_words_added date
            if added_words:
                cur.execute("""
                    UPDATE user_preferences
                    SET last_test_words_added = CURRENT_DATE
                    WHERE user_id = %s
                """, (user_id,))

            conn.commit()

            # Get updated progress
            cur.execute("""
                SELECT
                    COUNT(DISTINCT CASE WHEN tv.is_toefl THEN sw.word END) as toefl_saved,
                    COUNT(DISTINCT CASE WHEN tv.is_ielts THEN sw.word END) as ielts_saved,
                    (SELECT COUNT(DISTINCT word) FROM test_vocabularies WHERE is_toefl = TRUE AND language = %s) as total_toefl,
                    (SELECT COUNT(DISTINCT word) FROM test_vocabularies WHERE is_ielts = TRUE AND language = %s) as total_ielts
                FROM saved_words sw
                LEFT JOIN test_vocabularies tv ON tv.word = sw.word AND tv.language = sw.learning_language
                WHERE sw.user_id = %s
            """, (learning_language, learning_language, user_id))

            progress = cur.fetchone()

            return jsonify({
                "success": True,
                "words_added": added_words,
                "count": len(added_words),
                "progress": {
                    "toefl": {
                        "saved": progress[0],
                        "total": progress[2],
                        "percentage": round(100 * progress[0] / progress[2], 1) if progress[2] > 0 else 0
                    } if toefl_enabled else None,
                    "ielts": {
                        "saved": progress[1],
                        "total": progress[3],
                        "percentage": round(100 * progress[1] / progress[3], 1) if progress[3] > 0 else 0
                    } if ielts_enabled else None
                }
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error adding daily test words: {e}")
        return jsonify({"error": "Internal server error"}), 500


def get_test_vocabulary_stats():
    """
    Get overall test vocabulary statistics
    """
    try:
        language = request.args.get('language', 'en')

        conn = get_db_connection()
        cur = conn.cursor()
        try:

            cur.execute("""
                SELECT
                    COUNT(DISTINCT word) as total_words,
                    COUNT(DISTINCT CASE WHEN is_toefl THEN word END) as toefl_words,
                    COUNT(DISTINCT CASE WHEN is_ielts THEN word END) as ielts_words,
                    COUNT(DISTINCT CASE WHEN is_toefl AND is_ielts THEN word END) as both_tests,
                    COUNT(DISTINCT CASE WHEN is_toefl AND NOT is_ielts THEN word END) as toefl_only,
                    COUNT(DISTINCT CASE WHEN is_ielts AND NOT is_toefl THEN word END) as ielts_only
                FROM test_vocabularies
                WHERE language = %s
            """, (language,))

            stats = cur.fetchone()

            return jsonify({
                "language": language,
                "statistics": {
                    "total_unique_words": stats[0],
                    "toefl_words": stats[1],
                    "ielts_words": stats[2],
                    "words_in_both": stats[3],
                    "toefl_exclusive": stats[4],
                    "ielts_exclusive": stats[5]
                }
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting test vocabulary stats: {e}")
        return jsonify({"error": "Internal server error"}), 500