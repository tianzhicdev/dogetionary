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
            
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO user_preferences (user_id, learning_language, native_language, user_name, user_motto)
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (user_id) 
                DO UPDATE SET 
                    learning_language = EXCLUDED.learning_language,
                    native_language = EXCLUDED.native_language,
                    user_name = EXCLUDED.user_name,
                    user_motto = EXCLUDED.user_motto,
                    updated_at = CURRENT_TIMESTAMP
            """, (user_id, learning_lang, native_lang, user_name, user_motto))
            conn.commit()
            conn.close()
            
            return jsonify({
                "user_id": user_id,
                "learning_language": learning_lang,
                "native_language": native_lang,
                "user_name": user_name,
                "user_motto": user_motto,
                "updated": True
            })
    
    except Exception as e:
        logger.error(f"Error handling user preferences: {str(e)}")
        return jsonify({"error": f"Failed to handle user preferences: {str(e)}"}), 500