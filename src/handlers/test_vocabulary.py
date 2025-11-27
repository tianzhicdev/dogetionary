"""
Test vocabulary handlers for TOEFL/IELTS/TIANZ preparation features
"""

from flask import jsonify, request
from datetime import datetime, date
import logging
import sys
import os
from typing import Dict, Any, Optional

# Add parent directory to Python path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utils.database import get_db_connection, db_cursor, db_fetch_scalar

logger = logging.getLogger(__name__)

# Configuration
DAILY_TEST_WORDS = 10  # Number of words to add per day (compile-time configurable)

# Test type mapping: test_type -> (enabled_column, target_days_column, vocab_column)
TEST_TYPE_MAPPING = {
    'TOEFL_BEGINNER': ('toefl_beginner_enabled', 'toefl_beginner_target_days', 'is_toefl_beginner'),
    'TOEFL_INTERMEDIATE': ('toefl_intermediate_enabled', 'toefl_intermediate_target_days', 'is_toefl_intermediate'),
    'TOEFL_ADVANCED': ('toefl_advanced_enabled', 'toefl_advanced_target_days', 'is_toefl_advanced'),
    'IELTS_BEGINNER': ('ielts_beginner_enabled', 'ielts_beginner_target_days', 'is_ielts_beginner'),
    'IELTS_INTERMEDIATE': ('ielts_intermediate_enabled', 'ielts_intermediate_target_days', 'is_ielts_intermediate'),
    'IELTS_ADVANCED': ('ielts_advanced_enabled', 'ielts_advanced_target_days', 'is_ielts_advanced'),
    'TIANZ': ('tianz_enabled', 'tianz_target_days', 'is_tianz'),
    # Legacy mappings for backward compatibility
    'TOEFL': ('toefl_advanced_enabled', 'toefl_advanced_target_days', 'is_toefl_advanced'),
    'IELTS': ('ielts_advanced_enabled', 'ielts_advanced_target_days', 'is_ielts_advanced'),
}

# All test enable columns (for disabling all tests)
ALL_TEST_ENABLE_COLUMNS = [
    'toefl_beginner_enabled', 'toefl_intermediate_enabled', 'toefl_advanced_enabled',
    'ielts_beginner_enabled', 'ielts_intermediate_enabled', 'ielts_advanced_enabled',
    'tianz_enabled'
]

def update_test_settings():
    """
    Update user's test preparation settings using level-based test types.

    New API format:
    {
        "user_id": "uuid",
        "test_type": "TOEFL_INTERMEDIATE",  // One of the TEST_TYPE_MAPPING keys, or null to disable
        "target_days": 45  // Optional, defaults to 30
    }

    Legacy format (still supported):
    {
        "user_id": "uuid",
        "toefl_enabled": true,
        "toefl_target_days": 45,
        ...
    }
    """
    try:
        data = request.get_json()
        user_id = data.get('user_id')

        if not user_id:
            return jsonify({"error": "User ID is required"}), 400

        # Check for new API format (test_type parameter)
        # Note: test_type can be null/None to disable all tests
        has_test_type_param = 'test_type' in data
        test_type = data.get('test_type')
        target_days = data.get('target_days', 30)

        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # Verify user exists
            cur.execute("SELECT user_id FROM user_preferences WHERE user_id = %s", (user_id,))
            if not cur.fetchone():
                return jsonify({"error": "User not found"}), 404

            if has_test_type_param:
                # New API format: use test_type string
                if test_type and test_type not in TEST_TYPE_MAPPING:
                    return jsonify({"error": f"Invalid test_type. Must be one of: {', '.join(TEST_TYPE_MAPPING.keys())}, or null"}), 400

                if test_type:
                    # Enable the selected test, disable all others
                    enabled_col, target_days_col, _ = TEST_TYPE_MAPPING[test_type]

                    # Build SET clause: all columns FALSE except the selected one
                    set_clauses = []
                    for col in ALL_TEST_ENABLE_COLUMNS:
                        if col == enabled_col:
                            set_clauses.append(f"{col} = TRUE")
                        else:
                            set_clauses.append(f"{col} = FALSE")
                    set_clauses.append(f"{target_days_col} = %s")

                    query = f"""
                        UPDATE user_preferences
                        SET {', '.join(set_clauses)}
                        WHERE user_id = %s
                    """
                    cur.execute(query, (target_days, user_id))
                else:
                    # Disable all tests
                    disable_all = ', '.join([f"{col} = FALSE" for col in ALL_TEST_ENABLE_COLUMNS])
                    query = f"""
                        UPDATE user_preferences
                        SET {disable_all},
                            last_test_words_added = NULL
                        WHERE user_id = %s
                    """
                    cur.execute(query, (user_id,))

                    # Delete schedule if all tests disabled
                    cur.execute("DELETE FROM study_schedules WHERE user_id = %s", (user_id,))

                conn.commit()

                # Return new format response
                return get_test_settings_response(user_id, cur)

            else:
                # Legacy API format: handle old parameters
                return handle_legacy_update(data, user_id, cur, conn)

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error updating test settings: {e}")
        return jsonify({"error": "Internal server error"}), 500


def handle_legacy_update(data, user_id, cur, conn):
    """Handle legacy update_test_settings API format"""
    toefl_enabled = data.get('toefl_enabled')
    ielts_enabled = data.get('ielts_enabled')
    tianz_enabled = data.get('tianz_enabled')
    toefl_target_days = data.get('toefl_target_days')
    ielts_target_days = data.get('ielts_target_days')
    tianz_target_days = data.get('tianz_target_days')

    if all(param is None for param in [toefl_enabled, ielts_enabled, tianz_enabled,
                                        toefl_target_days, ielts_target_days, tianz_target_days]):
        return jsonify({"error": "At least one setting must be provided"}), 400

    # Get current settings
    cur.execute("""
        SELECT toefl_enabled, ielts_enabled, tianz_enabled,
               toefl_advanced_enabled, ielts_advanced_enabled
        FROM user_preferences
        WHERE user_id = %s
    """, (user_id,))
    current = cur.fetchone()
    if not current:
        return jsonify({"error": "User not found"}), 404

    # Map old flags to new level flags (use advanced level)
    if toefl_enabled is not None:
        toefl_enabled_new = 'toefl_advanced_enabled'
        toefl_target_col = 'toefl_advanced_target_days'
    if ielts_enabled is not None:
        ielts_enabled_new = 'ielts_advanced_enabled'
        ielts_target_col = 'ielts_advanced_target_days'

    # Build update
    update_fields = []
    params = []

    if toefl_enabled is not None:
        update_fields.append("toefl_advanced_enabled = %s")
        params.append(toefl_enabled)
    if ielts_enabled is not None:
        update_fields.append("ielts_advanced_enabled = %s")
        params.append(ielts_enabled)
    if tianz_enabled is not None:
        update_fields.append("tianz_enabled = %s")
        params.append(tianz_enabled)
    if toefl_target_days is not None:
        update_fields.append("toefl_advanced_target_days = %s")
        params.append(toefl_target_days)
    if ielts_target_days is not None:
        update_fields.append("ielts_advanced_target_days = %s")
        params.append(ielts_target_days)
    if tianz_target_days is not None:
        update_fields.append("tianz_target_days = %s")
        params.append(tianz_target_days)

    params.append(user_id)

    query = f"""
        UPDATE user_preferences
        SET {', '.join(update_fields)}
        WHERE user_id = %s
    """
    cur.execute(query, params)
    conn.commit()

    # Return legacy format response
    cur.execute("""
        SELECT toefl_enabled, ielts_enabled, tianz_enabled,
               last_test_words_added,
               toefl_target_days, ielts_target_days, tianz_target_days,
               toefl_advanced_enabled, ielts_advanced_enabled
        FROM user_preferences
        WHERE user_id = %s
    """, (user_id,))
    result = cur.fetchone()

    return jsonify({
        "success": True,
        "settings": {
            "toefl_enabled": result['toefl_advanced_enabled'],
            "ielts_enabled": result['ielts_advanced_enabled'],
            "tianz_enabled": result['tianz_enabled'],
            "last_test_words_added": result['last_test_words_added'].isoformat() if result['last_test_words_added'] else None,
            "toefl_target_days": result['toefl_target_days'],
            "ielts_target_days": result['ielts_target_days'],
            "tianz_target_days": result['tianz_target_days']
        }
    }), 200


def get_test_settings_response(user_id, cur):
    """Helper to build test settings response in new format"""
    # Get all test settings
    select_cols = ', '.join(ALL_TEST_ENABLE_COLUMNS)
    target_cols = [TEST_TYPE_MAPPING[tt][1] for tt in ['TOEFL_BEGINNER', 'TOEFL_INTERMEDIATE', 'TOEFL_ADVANCED',
                                                         'IELTS_BEGINNER', 'IELTS_INTERMEDIATE', 'IELTS_ADVANCED', 'TIANZ']]
    select_target = ', '.join(target_cols)

    cur.execute(f"""
        SELECT {select_cols}, {select_target}, last_test_words_added
        FROM user_preferences
        WHERE user_id = %s
    """, (user_id,))
    result = cur.fetchone()

    if not result:
        return jsonify({"error": "User not found"}), 404

    # Determine active test
    active_test = None
    target_days = 30

    for test_type, (enabled_col, target_col, _) in TEST_TYPE_MAPPING.items():
        if test_type in ['TOEFL', 'IELTS']:  # Skip legacy mappings
            continue
        if result[enabled_col]:
            active_test = test_type
            target_days = result[target_col]
            break

    return jsonify({
        "success": True,
        "settings": {
            "active_test": active_test,
            "target_days": target_days,
            "last_test_words_added": result['last_test_words_added'].isoformat() if result['last_test_words_added'] else None
        }
    }), 200


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
                        up.tianz_enabled,
                        up.last_test_words_added,
                        up.learning_language,
                        up.native_language,
                        up.toefl_target_days,
                        up.ielts_target_days,
                        up.tianz_target_days
                    FROM user_preferences up
                    WHERE up.user_id = %s
                ),
                progress AS (
                    SELECT
                        COUNT(DISTINCT CASE WHEN tv.is_toefl THEN sw.word END) as toefl_saved,
                        COUNT(DISTINCT CASE WHEN tv.is_ielts THEN sw.word END) as ielts_saved,
                        COUNT(DISTINCT CASE WHEN tv.is_tianz THEN sw.word END) as tianz_saved
                    FROM saved_words sw
                    LEFT JOIN test_vocabularies tv ON tv.word = sw.word
                    WHERE sw.user_id = %s
                ),
                totals AS (
                    SELECT
                        COUNT(DISTINCT CASE WHEN is_toefl THEN word END) as total_toefl,
                        COUNT(DISTINCT CASE WHEN is_ielts THEN word END) as total_ielts,
                        COUNT(DISTINCT CASE WHEN is_tianz THEN word END) as total_tianz
                    FROM test_vocabularies
                    WHERE language = 'en'
                )
                SELECT
                    us.*,
                    p.toefl_saved,
                    p.ielts_saved,
                    p.tianz_saved,
                    t.total_toefl,
                    t.total_ielts,
                    t.total_tianz
                FROM user_settings us
                CROSS JOIN progress p
                CROSS JOIN totals t
            """, (user_id, user_id))

            result = cur.fetchone()

            if result:
                return jsonify({
                    "settings": {
                        "toefl_enabled": result['toefl_enabled'],
                        "ielts_enabled": result['ielts_enabled'],
                        "tianz_enabled": result['tianz_enabled'],
                        "last_test_words_added": result['last_test_words_added'].isoformat() if result['last_test_words_added'] else None,
                        "learning_language": result['learning_language'],
                        "native_language": result['native_language'],
                        "toefl_target_days": result['toefl_target_days'],
                        "ielts_target_days": result['ielts_target_days'],
                        "tianz_target_days": result['tianz_target_days']
                    },
                    "progress": {
                        "toefl": {
                            "saved": result['toefl_saved'],
                            "total": result['total_toefl'],
                            "percentage": round(100 * result['toefl_saved'] / result['total_toefl'], 1) if result['total_toefl'] > 0 else 0
                        },
                        "ielts": {
                            "saved": result['ielts_saved'],
                            "total": result['total_ielts'],
                            "percentage": round(100 * result['ielts_saved'] / result['total_ielts'], 1) if result['total_ielts'] > 0 else 0
                        },
                        "tianz": {
                            "saved": result['tianz_saved'],
                            "total": result['total_tianz'],
                            "percentage": round(100 * result['tianz_saved'] / result['total_tianz'], 1) if result['total_tianz'] > 0 else 0
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
                SELECT toefl_enabled, ielts_enabled, tianz_enabled, last_test_words_added
                FROM user_preferences
                WHERE user_id = %s
            """, (user_id,))

            settings = cur.fetchone()

            if not settings:
                return jsonify({"error": "User not found"}), 404

            toefl_enabled, ielts_enabled, tianz_enabled, last_added = settings

            if not toefl_enabled and not ielts_enabled and not tianz_enabled:
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
                    (%s = TRUE AND tv.is_ielts = TRUE) OR
                    (%s = TRUE AND tv.is_tianz = TRUE)
                )
                AND tv.word NOT IN (SELECT ew.word FROM existing_words ew)
                ORDER BY RANDOM()
                LIMIT %s
            """, (user_id, learning_language, learning_language, toefl_enabled, ielts_enabled, tianz_enabled, DAILY_TEST_WORDS))

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
                    COUNT(DISTINCT CASE WHEN tv.is_tianz THEN sw.word END) as tianz_saved,
                    (SELECT COUNT(DISTINCT word) FROM test_vocabularies WHERE is_toefl = TRUE AND language = %s) as total_toefl,
                    (SELECT COUNT(DISTINCT word) FROM test_vocabularies WHERE is_ielts = TRUE AND language = %s) as total_ielts,
                    (SELECT COUNT(DISTINCT word) FROM test_vocabularies WHERE is_tianz = TRUE AND language = %s) as total_tianz
                FROM saved_words sw
                LEFT JOIN test_vocabularies tv ON tv.word = sw.word AND tv.language = sw.learning_language
                WHERE sw.user_id = %s
            """, (learning_language, learning_language, learning_language, user_id))

            progress = cur.fetchone()

            return jsonify({
                "success": True,
                "words_added": added_words,
                "count": len(added_words),
                "progress": {
                    "toefl": {
                        "saved": progress[0],
                        "total": progress[3],
                        "percentage": round(100 * progress[0] / progress[3], 1) if progress[3] > 0 else 0
                    } if toefl_enabled else None,
                    "ielts": {
                        "saved": progress[1],
                        "total": progress[4],
                        "percentage": round(100 * progress[1] / progress[4], 1) if progress[4] > 0 else 0
                    } if ielts_enabled else None,
                    "tianz": {
                        "saved": progress[2],
                        "total": progress[5],
                        "percentage": round(100 * progress[2] / progress[5], 1) if progress[5] > 0 else 0
                    } if tianz_enabled else None
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
                    COUNT(DISTINCT CASE WHEN is_tianz THEN word END) as tianz_words
                FROM test_vocabularies
                WHERE language = %s
            """, (language,))

            stats = cur.fetchone()

            return jsonify({
                "language": language,
                "statistics": {
                    "total_unique_words": stats['total_words'],
                    "toefl_words": stats['toefl_words'],
                    "ielts_words": stats['ielts_words'],
                    "tianz_words": stats['tianz_words']
                }
            }), 200

        finally:
            cur.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error getting test vocabulary stats: {e}")
        return jsonify({"error": "Internal server error"}), 500


def get_test_vocabulary_count():
    """
    Get test vocabulary count and calculate study plans.
    V3 API endpoint for onboarding.

    Supports level-based test types:
    - TOEFL_BEGINNER, TOEFL_INTERMEDIATE, TOEFL_ADVANCED
    - IELTS_BEGINNER, IELTS_INTERMEDIATE, IELTS_ADVANCED
    - TIANZ
    - Legacy: TOEFL, IELTS (mapped to ADVANCED)
    """
    try:
        test_type = request.args.get('test_type')

        if not test_type:
            return jsonify({"error": "test_type parameter is required"}), 400

        if test_type not in TEST_TYPE_MAPPING:
            valid_types = ', '.join(TEST_TYPE_MAPPING.keys())
            return jsonify({"error": f"Invalid test_type. Must be one of: {valid_types}"}), 400

        # Get vocab column for this test type
        _, _, vocab_column = TEST_TYPE_MAPPING[test_type]

        # Get total count of words for the specified test
        total_words = db_fetch_scalar(f"""
            SELECT COUNT(DISTINCT word)
            FROM test_vocabularies
            WHERE language = 'en' AND {vocab_column} = TRUE
        """) or 0

        # Calculate study plans for 5 durations
        study_plans = []
        for days in [70, 60, 50, 40, 30]:
            words_per_day = (total_words + days - 1) // days  # Ceiling division
            study_plans.append({
                "days": days,
                "words_per_day": words_per_day
            })

        return jsonify({
            "test_type": test_type,
            "total_words": total_words,
            "study_plans": study_plans
        }), 200

    except Exception as e:
        logger.error(f"Error getting test vocabulary count: {e}")
        return jsonify({"error": "Internal server error"}), 500


def manual_daily_job():
    """
    Manual trigger for daily test vocabulary job (for testing/admin use)
    """
    try:
        from workers.test_vocabulary_worker import add_daily_test_words_for_all_users

        logger.info("Manual trigger of daily test vocabulary job")
        add_daily_test_words_for_all_users()
        return jsonify({"success": True, "message": "Daily job completed successfully"}), 200
    except Exception as e:
        logger.error(f"Manual daily job failed: {e}")
        return jsonify({"error": "Failed to run daily job"}), 500


def get_test_config():
    """
    Get test vocabulary configuration mapping languages to available tests.
    Returns which tests are available for each learning language.

    Response format:
    {
        "config": {
            "en": {
                "tests": [
                    {"code": "TOEFL", "name": "TOEFL Preparation", "description": "Test of English as a Foreign Language"},
                    {"code": "IELTS", "name": "IELTS Preparation", "description": "International English Language Testing System"},
                    {"code": "TIANZ", "name": "Tianz Test", "description": "Testing vocabulary list (20 words)", "testing_only": true}
                ]
            },
            "fr": {
                "tests": []  # Future: French tests
            },
            "es": {
                "tests": []  # Future: Spanish tests
            }
        }
    }
    """
    try:
        # Static configuration - in the future this could be database-driven
        config = {
            "en": {
                "tests": [
                    {
                        "code": "TOEFL",
                        "name": "TOEFL Preparation",
                        "description": "Test of English as a Foreign Language",
                        "testing_only": False
                    },
                    {
                        "code": "IELTS",
                        "name": "IELTS Preparation",
                        "description": "International English Language Testing System",
                        "testing_only": False
                    },
                    {
                        "code": "TIANZ",
                        "name": "Tianz Test",
                        "description": "Testing vocabulary list (20 words)",
                        "testing_only": True  # Only visible in developer mode
                    }
                ]
            },
            # Future language support
            "fr": {"tests": []},
            "es": {"tests": []},
            "de": {"tests": []},
            "it": {"tests": []},
            "pt": {"tests": []},
            "ja": {"tests": []},
            "ko": {"tests": []},
            "zh": {"tests": []}
        }

        logger.info("Test configuration fetched successfully")
        return jsonify({"config": config}), 200

    except Exception as e:
        logger.error(f"Error getting test config: {e}")
        return jsonify({"error": "Internal server error"}), 500