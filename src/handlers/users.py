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
from utils.database import validate_language, get_db_connection
from services.user_service import generate_user_profile
from handlers.bundle_vocabulary import TEST_TYPE_MAPPING, ALL_TEST_ENABLE_COLUMNS

# Get logger
import logging
logger = logging.getLogger(__name__)


def get_user_preferences(user_id: str) -> dict:
    """Get full user preferences including test prep settings"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT learning_language, native_language, user_name, user_motto,
                   toefl_enabled, ielts_enabled, demo_enabled,
                   toefl_target_days, ielts_target_days, demo_target_days,
                   daily_time_commitment_minutes
            FROM user_preferences
            WHERE user_id = %s
        """, (user_id,))

        result = cur.fetchone()
        cur.close()
        conn.close()

        if result:
            # Determine active test type from enabled flags (V3 API format)
            test_prep = None
            target_days = 30
            if result['toefl_enabled']:
                test_prep = 'TOEFL_ADVANCED'  # Default to advanced level
                target_days = result['toefl_target_days'] or 30
            elif result['ielts_enabled']:
                test_prep = 'IELTS_ADVANCED'  # Default to advanced level
                target_days = result['ielts_target_days'] or 30
            elif result['demo_enabled']:
                test_prep = 'DEMO'
                target_days = result['demo_target_days'] or 30

            return {
                'learning_language': result['learning_language'],
                'native_language': result['native_language'],
                'user_name': result['user_name'] or '',
                'user_motto': result['user_motto'] or '',
                'test_prep': test_prep,
                'study_duration_days': target_days,
                'daily_time_commitment_minutes': result.get('daily_time_commitment_minutes', 30)
            }
        else:
            # Generate AI profile for new user
            username, motto = generate_user_profile()

            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO user_preferences (user_id, learning_language, native_language, user_name, user_motto)
                VALUES (%s, 'en', 'zh', %s, %s)
                ON CONFLICT (user_id) DO NOTHING
            """, (user_id, username, motto))
            conn.commit()
            conn.close()
            return {
                'learning_language': 'en',
                'native_language': 'zh',
                'user_name': username,
                'user_motto': motto,
                'test_prep': None,
                'study_duration_days': 30,
                'daily_time_commitment_minutes': 30
            }

    except Exception as e:
        logger.error(f"Error getting user preferences: {str(e)}", exc_info=True)
        return {
            'learning_language': 'en',
            'native_language': 'zh',
            'user_name': 'LearningExplorer',
            'user_motto': 'Every word is a new adventure!',
            'test_prep': None,
            'study_duration_days': 30,
            'daily_time_commitment_minutes': 30
        }



def handle_user_preferences(user_id):
    """Get or update user language preferences"""
    try:
        if request.method == 'GET':
            prefs = get_user_preferences(user_id)
            return jsonify({
                "user_id": user_id,
                "learning_language": prefs['learning_language'],
                "native_language": prefs['native_language'],
                "user_name": prefs['user_name'],
                "user_motto": prefs['user_motto'],
                "test_prep": prefs['test_prep'],
                "study_duration_days": prefs['study_duration_days'],
                "daily_time_commitment_minutes": prefs['daily_time_commitment_minutes']
            })
        
        elif request.method == 'POST':
            data = request.get_json()
            learning_lang = data.get('learning_language')
            native_lang = data.get('native_language')
            user_name = data.get('user_name', '')
            user_motto = data.get('user_motto', '')
            test_prep = data.get('test_prep')  # "TOEFL", "IELTS", or null
            study_duration_days = data.get('study_duration_days')  # 30, 40, 50, 60, 70
            timezone = data.get('timezone')  # Optional: IANA timezone string (e.g., "America/New_York")
            target_end_date = data.get('target_end_date')  # "YYYY-MM-DD" format or null
            daily_time_commitment = data.get('daily_time_commitment_minutes')  # Optional: 10-480 minutes

            if not learning_lang or not native_lang:
                return jsonify({"error": "Both learning_language and native_language are required"}), 400

            # Validate language codes are supported
            if not validate_language(learning_lang):
                return jsonify({"error": f"Unsupported learning language: {learning_lang}"}), 400
            if not validate_language(native_lang):
                return jsonify({"error": f"Unsupported native language: {native_lang}"}), 400

            # Validate languages are not the same
            if learning_lang == native_lang:
                return jsonify({"error": "Learning language and native language cannot be the same"}), 400

            # Validate test prep values if provided
            valid_test_types = list(TEST_TYPE_MAPPING.keys())
            if test_prep and test_prep not in valid_test_types:
                return jsonify({"error": f"Invalid test_prep. Must be one of: {', '.join(valid_test_types)}, or null"}), 400

            # Validate study duration if provided (10-100 days)
            if test_prep and not study_duration_days:
                return jsonify({"error": "study_duration_days must be set when test_prep is provided"}), 400

            # Calculate target_end_date from study_duration_days if provided, otherwise use explicit target_end_date
            from datetime import datetime, date, timedelta
            parsed_target_end_date = None

            if study_duration_days:
                # Auto-calculate target_end_date from study_duration_days
                parsed_target_end_date = date.today() + timedelta(days=study_duration_days)
            elif target_end_date:
                # Use explicitly provided target_end_date
                try:
                    parsed_target_end_date = datetime.strptime(target_end_date, '%Y-%m-%d').date()
                    # Validate it's in the future
                    if parsed_target_end_date <= date.today():
                        return jsonify({"error": "target_end_date must be in the future"}), 400
                except ValueError:
                    return jsonify({"error": "target_end_date must be in YYYY-MM-DD format"}), 400

            # Validate timezone if provided
            if timezone:
                import pytz
                try:
                    pytz.timezone(timezone)
                except pytz.exceptions.UnknownTimeZoneError:
                    return jsonify({"error": "Invalid timezone. Use IANA timezone format (e.g., 'America/New_York')"}), 400

            # Validate daily time commitment if provided (10-480 minutes)
            if daily_time_commitment is not None:
                try:
                    daily_time_commitment = int(daily_time_commitment)
                    if daily_time_commitment < 10 or daily_time_commitment > 480:
                        return jsonify({"error": "daily_time_commitment_minutes must be between 10 and 480"}), 400
                except (ValueError, TypeError):
                    return jsonify({"error": "daily_time_commitment_minutes must be an integer"}), 400

            conn = get_db_connection()
            cur = conn.cursor()

            # Determine test settings based on test_prep selection using new level-based format
            target_days = study_duration_days if study_duration_days else 30

            # Build the column values for all test enable columns
            test_settings = {}
            if test_prep:
                enabled_col, target_days_col, _ = TEST_TYPE_MAPPING[test_prep]
                # Enable only the selected test, disable all others
                for col in ALL_TEST_ENABLE_COLUMNS:
                    test_settings[col] = (col == enabled_col)
                test_settings[target_days_col] = target_days
            else:
                # Disable all tests
                for col in ALL_TEST_ENABLE_COLUMNS:
                    test_settings[col] = False

            # Build the INSERT statement with all test columns, target_end_date, and timezone
            insert_cols = ['user_id', 'learning_language', 'native_language', 'user_name', 'user_motto'] + list(test_settings.keys())
            insert_values = [user_id, learning_lang, native_lang, user_name, user_motto] + list(test_settings.values())

            # Add target_end_date if provided
            if parsed_target_end_date is not None:
                insert_cols.append('target_end_date')
                insert_values.append(parsed_target_end_date)

            # Add timezone if provided
            if timezone:
                insert_cols.append('timezone')
                insert_values.append(timezone)

            # Add daily time commitment if provided
            if daily_time_commitment is not None:
                insert_cols.append('daily_time_commitment_minutes')
                insert_values.append(daily_time_commitment)

            placeholders = ', '.join(['%s'] * len(insert_values))

            # Build the ON CONFLICT UPDATE clause
            update_clauses = [
                'learning_language = EXCLUDED.learning_language',
                'native_language = EXCLUDED.native_language',
                'user_name = EXCLUDED.user_name',
                'user_motto = EXCLUDED.user_motto'
            ]
            # Add update clauses for all test settings columns
            for col in test_settings.keys():
                update_clauses.append(f'{col} = EXCLUDED.{col}')
            # Add target_end_date update if provided
            if parsed_target_end_date is not None:
                update_clauses.append('target_end_date = EXCLUDED.target_end_date')
            # Add timezone update if provided
            if timezone:
                update_clauses.append('timezone = EXCLUDED.timezone')
            # Add daily time commitment update if provided
            if daily_time_commitment is not None:
                update_clauses.append('daily_time_commitment_minutes = EXCLUDED.daily_time_commitment_minutes')
            update_clauses.append('updated_at = CURRENT_TIMESTAMP')

            # Execute the query
            query = f"""
                INSERT INTO user_preferences ({', '.join(insert_cols)})
                VALUES ({placeholders})
                ON CONFLICT (user_id)
                DO UPDATE SET {', '.join(update_clauses)}
            """
            cur.execute(query, insert_values)
            conn.commit()
            conn.close()

            response_data = {
                "user_id": user_id,
                "learning_language": learning_lang,
                "native_language": native_lang,
                "user_name": user_name,
                "user_motto": user_motto,
                "test_prep": test_prep,
                "study_duration_days": study_duration_days,
                "updated": True
            }
            if target_end_date:
                response_data["target_end_date"] = target_end_date
            if daily_time_commitment is not None:
                response_data["daily_time_commitment_minutes"] = daily_time_commitment
            return jsonify(response_data)
    
    except Exception as e:
        logger.error(f"Error handling user preferences: {str(e)}", exc_info=True)
        return jsonify({"error": f"Failed to handle user preferences: {str(e)}"}), 500