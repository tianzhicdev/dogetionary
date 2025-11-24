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

# Get logger
import logging
logger = logging.getLogger(__name__)


def get_user_preferences(user_id: str) -> tuple[str, str, str, str]:
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            SELECT learning_language, native_language, user_name, user_motto 
            FROM user_preferences 
            WHERE user_id = %s
        """, (user_id,))
        
        result = cur.fetchone()
        cur.close()
        conn.close()
        
        if result:
            return (result['learning_language'], result['native_language'], 
                   result['user_name'] or '', result['user_motto'] or '')
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
            return 'en', 'zh', username, motto
            
    except Exception as e:
        logger.error(f"Error getting user preferences: {str(e)}")
        return 'en', 'zh', 'LearningExplorer', 'Every word is a new adventure!'



def handle_user_preferences(user_id):
    """Get or update user language preferences"""
    try:
        if request.method == 'GET':
            learning_lang, native_lang, user_name, user_motto = get_user_preferences(user_id)
            return jsonify({
                "user_id": user_id,
                "learning_language": learning_lang,
                "native_language": native_lang,
                "user_name": user_name,
                "user_motto": user_motto
            })
        
        elif request.method == 'POST':
            data = request.get_json()
            learning_lang = data.get('learning_language')
            native_lang = data.get('native_language')
            user_name = data.get('user_name', '')
            user_motto = data.get('user_motto', '')
            test_prep = data.get('test_prep')  # "TOEFL", "IELTS", or null
            study_duration_days = data.get('study_duration_days')  # 30, 40, 50, 60, 70

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
            if test_prep and test_prep not in ['TOEFL', 'IELTS']:
                return jsonify({"error": "test_prep must be 'TOEFL' or 'IELTS'"}), 400

            # Validate study duration if provided (10-100 days)
            if study_duration_days and (study_duration_days < 10 or study_duration_days > 100):
                return jsonify({"error": "study_duration_days must be between 10 and 100"}), 400

            conn = get_db_connection()
            cur = conn.cursor()

            # Determine test settings based on test_prep selection
            toefl_enabled = (test_prep == 'TOEFL')
            ielts_enabled = (test_prep == 'IELTS')
            # Always preserve the study_duration_days if provided, even when test prep is disabled
            # This ensures the "complete in" setting is always synced with what was selected in onboarding
            toefl_target_days = study_duration_days if study_duration_days else 30
            ielts_target_days = study_duration_days if study_duration_days else 30

            cur.execute("""
                INSERT INTO user_preferences (
                    user_id, learning_language, native_language, user_name, user_motto,
                    toefl_enabled, ielts_enabled, toefl_target_days, ielts_target_days
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (user_id)
                DO UPDATE SET
                    learning_language = EXCLUDED.learning_language,
                    native_language = EXCLUDED.native_language,
                    user_name = EXCLUDED.user_name,
                    user_motto = EXCLUDED.user_motto,
                    toefl_enabled = EXCLUDED.toefl_enabled,
                    ielts_enabled = EXCLUDED.ielts_enabled,
                    toefl_target_days = EXCLUDED.toefl_target_days,
                    ielts_target_days = EXCLUDED.ielts_target_days,
                    updated_at = CURRENT_TIMESTAMP
            """, (user_id, learning_lang, native_lang, user_name, user_motto,
                  toefl_enabled, ielts_enabled, toefl_target_days, ielts_target_days))
            conn.commit()
            conn.close()

            return jsonify({
                "user_id": user_id,
                "learning_language": learning_lang,
                "native_language": native_lang,
                "user_name": user_name,
                "user_motto": user_motto,
                "test_prep": test_prep,
                "study_duration_days": study_duration_days,
                "updated": True
            })
    
    except Exception as e:
        logger.error(f"Error handling user preferences: {str(e)}")
        return jsonify({"error": f"Failed to handle user preferences: {str(e)}"}), 500


def get_supported_languages():
    """Get list of supported languages"""
    lang_names = {
        'af': 'Afrikaans', 'ar': 'Arabic', 'hy': 'Armenian', 'az': 'Azerbaijani',
        'be': 'Belarusian', 'bs': 'Bosnian', 'bg': 'Bulgarian', 'ca': 'Catalan',
        'zh': 'Chinese', 'hr': 'Croatian', 'cs': 'Czech', 'da': 'Danish',
        'nl': 'Dutch', 'en': 'English', 'et': 'Estonian', 'fi': 'Finnish',
        'fr': 'French', 'gl': 'Galician', 'de': 'German', 'el': 'Greek',
        'he': 'Hebrew', 'hi': 'Hindi', 'hu': 'Hungarian', 'is': 'Icelandic',
        'id': 'Indonesian', 'it': 'Italian', 'ja': 'Japanese', 'kn': 'Kannada',
        'kk': 'Kazakh', 'ko': 'Korean', 'lv': 'Latvian', 'lt': 'Lithuanian',
        'mk': 'Macedonian', 'ms': 'Malay', 'mr': 'Marathi', 'mi': 'Maori',
        'ne': 'Nepali', 'no': 'Norwegian', 'fa': 'Persian', 'pl': 'Polish',
        'pt': 'Portuguese', 'ro': 'Romanian', 'ru': 'Russian', 'sr': 'Serbian',
        'sk': 'Slovak', 'sl': 'Slovenian', 'es': 'Spanish', 'sw': 'Swahili',
        'sv': 'Swedish', 'tl': 'Tagalog', 'ta': 'Tamil', 'th': 'Thai',
        'tr': 'Turkish', 'uk': 'Ukrainian', 'ur': 'Urdu', 'vi': 'Vietnamese',
        'cy': 'Welsh'
    }
    
    languages = [
        {"code": code, "name": lang_names[code]} 
        for code in sorted(SUPPORTED_LANGUAGES)
    ]
    
    return jsonify({
        "languages": languages,
        "count": len(languages)
    })