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
from review import get_next_review_datetime
import io
import math
import threading
import queue
import time
import base64
import logging
import sys

# SM-2 SuperMemo spaced repetition algorithm
DEFAULT_EASE_FACTOR = 2.5
INITIAL_INTERVALS = [1, 6]  # First review: 1 day, Second review: 6 days

# Supported languages
SUPPORTED_LANGUAGES = {
    'af', 'ar', 'hy', 'az', 'be', 'bs', 'bg', 'ca', 'zh', 'hr', 'cs', 'da',
    'nl', 'en', 'et', 'fi', 'fr', 'gl', 'de', 'el', 'he', 'hi', 'hu', 'is',
    'id', 'it', 'ja', 'kn', 'kk', 'ko', 'lv', 'lt', 'mk', 'ms', 'mr', 'mi',
    'ne', 'no', 'fa', 'pl', 'pt', 'ro', 'ru', 'sr', 'sk', 'sl', 'es', 'sw',
    'sv', 'tl', 'ta', 'th', 'tr', 'uk', 'ur', 'vi', 'cy'
}

def validate_language(lang: str) -> bool:
    """Validate if language code is supported"""
    return lang in SUPPORTED_LANGUAGES

def calculate_spaced_repetition(reviews_data, current_review_time=None):
    """
    DEPRECATED: Simple calculation for backward compatibility - SQL handles the logic now
    
    This function is deprecated and should not be used for new code.
    Use get_next_review_datetime from review.py instead.
    This function is maintained only for get_word_review_data compatibility.
    """
    if not reviews_data:
        return 0, 1, datetime.now() + timedelta(days=1), None
    
    reviews_data.sort(key=lambda r: r['reviewed_at'])
    review_count = len(reviews_data)
    last_reviewed_at = reviews_data[-1]['reviewed_at']
    current_time = current_review_time or datetime.now()
    
    # Simple interval calculation for API compatibility
    # Actual logic is now in SQL
    consecutive_correct = 0
    for review in reversed(reviews_data):
        if review['response']:
            consecutive_correct += 1
        else:
            break
    
    if not reviews_data[-1]['response']:
        interval_days = 1
    elif consecutive_correct == 1:
        interval_days = 5  # Updated to match new logic
    elif consecutive_correct >= 2 and len(reviews_data) >= 2:
        # Calculate based on time difference like SQL does
        previous_review_time = reviews_data[-2]['reviewed_at']
        time_diff_days = (last_reviewed_at - previous_review_time).total_seconds() / 86400
        interval_days = max(1, int(2.5 * time_diff_days))
    else:
        interval_days = 1
    
    next_review_date = current_time + timedelta(days=interval_days)
    return review_count, interval_days, next_review_date, last_reviewed_at

def get_word_review_data(user_id: str, word_id: int):
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            SELECT response, reviewed_at FROM reviews 
            WHERE user_id = %s AND word_id = %s 
            ORDER BY reviewed_at ASC
        """, (user_id, word_id))
        
        reviews = [{"response": row['response'], "reviewed_at": row['reviewed_at']} for row in cur.fetchall()]
        cur.close()
        conn.close()
        
        return calculate_spaced_repetition(reviews)
        
    except Exception as e:
        app.logger.error(f"Error getting review data: {str(e)}")
        return 0, 1, datetime.now() + timedelta(days=1), None

load_dotenv('.env.secrets')

app = Flask(__name__)

# Configure comprehensive logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

# Set Flask app logger level and handler
app.logger.setLevel(logging.INFO)
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
app.logger.addHandler(handler)

# Test log to verify logging is working
app.logger.info("=== DOGETIONARY LOGGING INITIALIZED ===")

@app.before_request
def log_request_info():
    """Log all incoming requests with full details"""
    g.start_time = time.time()
    
    # Log request details
    request_data = {
        'method': request.method,
        'url': request.url,
        'remote_addr': request.remote_addr,
        'user_agent': request.headers.get('User-Agent', ''),
        'content_type': request.headers.get('Content-Type', ''),
        'content_length': request.headers.get('Content-Length', ''),
        'headers': dict(request.headers),
        'args': dict(request.args),
    }
    
    # Only log request body for non-GET requests and if it's not too large
    if request.method != 'GET' and request.content_length and request.content_length < 10000:
        try:
            if request.is_json:
                request_data['json_body'] = request.get_json()
            elif request.form:
                request_data['form_data'] = dict(request.form)
            else:
                request_data['raw_body'] = request.get_data(as_text=True)[:1000]  # Limit to 1000 chars
        except Exception as e:
            request_data['body_error'] = str(e)
    
    app.logger.info(f"REQUEST: {json.dumps(request_data, default=str, indent=2)}")

@app.after_request
def log_response_info(response):
    """Log all outgoing responses with full details"""
    duration = time.time() - getattr(g, 'start_time', time.time())
    
    response_data = {
        'status_code': response.status_code,
        'status': response.status,
        'content_type': response.content_type,
        'content_length': response.content_length,
        'headers': dict(response.headers),
        'duration_ms': round(duration * 1000, 2)
    }
    
    # Log response body if it's not too large and is text-based
    if response.content_length and response.content_length < 10000:
        try:
            if response.content_type and 'json' in response.content_type:
                response_data['json_body'] = response.get_json()
            elif response.content_type and response.content_type.startswith('text/'):
                response_data['text_body'] = response.get_data(as_text=True)[:1000]  # Limit to 1000 chars
        except Exception as e:
            response_data['body_error'] = str(e)
    
    app.logger.info(f"RESPONSE: {json.dumps(response_data, default=str, indent=2)}")
    
    return response

client = openai.OpenAI(
    api_key=os.getenv('OPENAI_API_KEY'),
    base_url=os.getenv('BASE_URL', 'https://api.openai.com/v1/')
)

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')

# Audio generation queue for async processing
audio_generation_queue = queue.Queue()
audio_generation_status = {}

# JSON Schema for OpenAI structured output
WORD_DEFINITION_SCHEMA = {
    "type": "object",
    "properties": {
        "word": {"type": "string"},
        "phonetic": {"type": "string"},
        "translations": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Direct translations from learning language to native language"
        },
        "definitions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "type": {"type": "string"},
                    "definition": {"type": "string"},
                    "definition_native": {"type": "string", "description": "Definition in user's native language"},
                    "examples": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Example sentences in the learning language"
                    },
                    "cultural_notes": {"type": "string", "description": "Optional cultural context"}
                },
                "required": ["type", "definition", "definition_native", "examples"]
            }
        }
    },
    "required": ["word", "phonetic", "translations", "definitions"]
}

def generate_audio_for_text(text: str) -> bytes:
    """Generate TTS audio for text using OpenAI"""
    try:
        response = client.audio.speech.create(
            model="tts-1",
            voice="alloy", 
            input=text,
            response_format="mp3"
        )
        
        return response.content
        
    except Exception as e:
        app.logger.error(f"Failed to generate audio: {str(e)}")
        raise

def audio_exists(text: str, language: str) -> bool:
    """Check if audio exists for text+language"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            SELECT 1 FROM audio 
            WHERE text_content = %s AND language = %s
        """, (text, language))
        
        result = cur.fetchone()
        conn.close()
        
        return result is not None
    except Exception as e:
        app.logger.error(f"Error checking audio existence: {str(e)}")
        return False

def store_audio(text: str, language: str, audio_data: bytes) -> str:
    """Store audio, return the created_at timestamp"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # First try to insert
        cur.execute("""
            INSERT INTO audio (text_content, language, audio_data, content_type)
            VALUES (%s, %s, %s, 'audio/mpeg')
            ON CONFLICT (text_content, language) 
            DO UPDATE SET audio_data = EXCLUDED.audio_data, content_type = EXCLUDED.content_type
        """, (text, language, audio_data))
        
        # Then get the actual timestamp from database
        cur.execute("""
            SELECT created_at FROM audio 
            WHERE text_content = %s AND language = %s
        """, (text, language))
        
        result = cur.fetchone()
        conn.commit()
        conn.close()
        
        return result['created_at'].isoformat() if result else datetime.now().isoformat()
        
    except Exception as e:
        app.logger.error(f"Error storing audio: {str(e)}")
        raise

def get_cached_definition(word: str, learning_lang: str, native_lang: str) -> Optional[dict]:
    """Get cached definition with smart fallback"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Try exact match first
        cur.execute("""
            SELECT definition_data FROM definitions 
            WHERE word = %s AND learning_language = %s AND native_language = %s
        """, (word, learning_lang, native_lang))
        
        exact_match = cur.fetchone()
        if exact_match:
            conn.close()
            return {'definition_data': exact_match['definition_data'], 'cache_type': 'exact'}
        conn.close()
        return None
        
    except Exception as e:
        app.logger.error(f"Error getting cached definition: {str(e)}")
        return None

def build_definition_prompt(word: str, learning_lang: str, native_lang: str) -> str:
    """Build LLM prompt for bilingual definitions"""
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
    
    learning_lang_name = lang_names.get(learning_lang, learning_lang)
    native_lang_name = lang_names.get(native_lang, native_lang)
    
    if learning_lang == native_lang:
        raise ValueError("Learning language and native language cannot be the same")
    else:
        # Different languages - bilingual approach
        return f"""Define the word '{word}' for a learner studying {learning_lang_name} whose native language is {native_lang_name}. Provide:
        - A list of direct translations in {native_lang_name} (in 'translations' field)
        - Phonetic spelling
        - Detailed definitions with different parts of speech
        
        For each definition:
        - Provide definition in {learning_lang_name} (in 'definition' field)
        - Provide translation/explanation in {native_lang_name} (in 'definition_native' field)  
        - Include 2-3 example sentences in {learning_lang_name} only (in 'examples' field)
        - Add cultural context and usage notes
        
        Examples should always be in {learning_lang_name} since that's what the user is learning."""

def collect_audio_references(definition_data: dict, learning_lang: str) -> dict:
    """Collect all audio references for a definition - now just returns available texts"""
    audio_refs = {"example_audio": {}, "word_audio": None}
    
    # Collect all examples that have audio available
    for def_group in definition_data.get('definitions', []):
        for example in def_group.get('examples', []):
            if audio_exists(example, learning_lang):
                audio_refs["example_audio"][example] = True  # Just mark as available
    
    return audio_refs

def queue_missing_audio(word: str, definition_data: dict, learning_lang: str, existing_audio_refs: dict):
    """Queue missing audio for generation - simplified to just text and language"""
    audio_status_key = f"{word}:{learning_lang}"
    
    # Collect all texts that need audio
    texts_to_generate = []
    
    # Add word if missing
    if not audio_exists(word, learning_lang):
        texts_to_generate.append(word)
    
    # Add examples that are missing
    for def_group in definition_data.get('definitions', []):
        for example in def_group.get('examples', []):
            if example not in existing_audio_refs["example_audio"]:
                texts_to_generate.append(example)
    
    if texts_to_generate:
        # Queue each text individually for simpler processing
        for text in texts_to_generate:
            audio_generation_queue.put((text, learning_lang))
        audio_generation_status[audio_status_key] = "queued"
        return "queued"
    
    return "complete"

def audio_generation_worker():
    """Background worker for processing audio generation - simplified"""
    while True:
        try:
            task = audio_generation_queue.get(timeout=1)
            if task is None:
                break
                
            text, language = task
            
            try:
                app.logger.info(f"Generating audio for: '{text}' in {language}")
                audio_data = generate_audio_for_text(text)
                store_audio(text, language, audio_data)
                app.logger.info(f"Successfully generated audio for: '{text}'")
            except Exception as e:
                app.logger.error(f"Failed to generate audio for '{text}': {str(e)}")
                
            audio_generation_queue.task_done()
            
        except queue.Empty:
            continue
        except Exception as e:
            app.logger.error(f"Error in audio generation worker: {str(e)}")

# Start audio generation worker thread
audio_worker_thread = threading.Thread(target=audio_generation_worker, daemon=True)
audio_worker_thread.start()

def get_db_connection():
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)

def get_user_preferences(user_id: str) -> tuple[str, str]:
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            SELECT learning_language, native_language 
            FROM user_preferences 
            WHERE user_id = %s
        """, (user_id,))
        
        result = cur.fetchone()
        cur.close()
        conn.close()
        
        if result:
            return result['learning_language'], result['native_language']
        else:
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO user_preferences (user_id, learning_language, native_language)
                VALUES (%s, 'en', 'zh')
                ON CONFLICT (user_id) DO NOTHING
            """, (user_id,))
            conn.commit()
            conn.close()
            return 'en', 'zh'
            
    except Exception as e:
        app.logger.error(f"Error getting user preferences: {str(e)}")
        return 'en', 'zh'

@app.route('/save', methods=['POST'])
def save_word():
    try:
        data = request.get_json()
        
        if not data or 'word' not in data or 'user_id' not in data:
            return jsonify({"error": "Both 'word' and 'user_id' are required"}), 400
        
        word = data['word'].strip().lower()
        user_id = data['user_id']
        learning_lang = data.get('learning_language', 'en')
        metadata = data.get('metadata', {})
        
        if 'learning_language' not in data:
            stored_learning_lang, _ = get_user_preferences(user_id)
            learning_lang = stored_learning_lang
        else:
            # Validate provided learning language
            if not validate_language(learning_lang):
                return jsonify({"error": f"Unsupported learning language: {learning_lang}"}), 400
        
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            INSERT INTO saved_words (user_id, word, learning_language, metadata)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (user_id, word, learning_language)
            DO UPDATE SET metadata = EXCLUDED.metadata
            RETURNING id, created_at
        """, (user_id, word, learning_lang, json.dumps(metadata)))
        
        result = cur.fetchone()
        conn.commit()
        conn.close()
        
        return jsonify({
            "success": True,
            "message": f"Word '{word}' saved successfully",
            "word_id": result['id'],
            "created_at": result['created_at'].isoformat()
        }), 201
    
    except Exception as e:
        app.logger.error(f"Error saving word: {str(e)}")
        return jsonify({"error": f"Failed to save word: {str(e)}"}), 500

@app.route('/review_next', methods=['GET'])
def get_next_review_word():
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Find word with earliest next review date (due now or overdue)
        cur.execute("""
            SELECT 
                sw.id, 
                sw.word, 
                sw.learning_language, 
                sw.metadata, 
                sw.created_at,
                COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') as next_review_date,
                COALESCE(latest_review.review_count, 0) as review_count,
                latest_review.last_reviewed_at,
                CASE 
                    WHEN latest_review.last_reviewed_at IS NOT NULL AND latest_review.next_review_date IS NOT NULL 
                    THEN EXTRACT(epoch FROM (latest_review.next_review_date - latest_review.last_reviewed_at)) / 86400
                    WHEN latest_review.next_review_date IS NOT NULL
                    THEN EXTRACT(epoch FROM (latest_review.next_review_date - sw.created_at)) / 86400
                    ELSE 1
                END as interval_days
            FROM saved_words sw
            LEFT JOIN (
                SELECT 
                    word_id,
                    next_review_date,
                    reviewed_at as last_reviewed_at,
                    COUNT(*) as review_count,
                    ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                FROM reviews
                GROUP BY word_id, next_review_date, reviewed_at
            ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
            WHERE sw.user_id = %s 
            -- AND COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= NOW()
            ORDER BY COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') ASC
            LIMIT 1
        """, (user_id,))
        
        word = cur.fetchone()
        cur.close()
        conn.close()
        
        if not word:
            return jsonify({
                "user_id": user_id,
                "saved_words": [],
                "count": 0
            })
        
        return jsonify({
            "user_id": user_id,
            "saved_words": [{
                "id": word['id'],
                "word": word['word']
            }],
            "count": 1
        })
        
    except Exception as e:
        app.logger.error(f"Error getting next review word: {str(e)}")
        return jsonify({"error": f"Failed to get next review word: {str(e)}"}), 500

@app.route('/due_counts', methods=['GET'])
def get_due_counts():
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Count total and overdue words using stored next_review_date
        cur.execute("""
            SELECT 
                COUNT(*) as total_count,
                COUNT(CASE WHEN COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= NOW() THEN 1 END) as overdue_count
            FROM saved_words sw
            LEFT JOIN (
                SELECT 
                    word_id,
                    next_review_date,
                    ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                FROM reviews
            ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
            WHERE sw.user_id = %s
        """, (user_id,))
        
        result = cur.fetchone()
        cur.close()
        conn.close()
        
        return jsonify({
            "user_id": user_id,
            "overdue_count": result['overdue_count'] or 0,
            "total_count": result['total_count'] or 0
        })
        
    except Exception as e:
        app.logger.error(f"Error getting due counts: {str(e)}")
        return jsonify({"error": f"Failed to get due counts: {str(e)}"}), 500

@app.route('/reviews/submit', methods=['POST'])
def submit_review():
    try:
        data = request.get_json()
        
        user_id = data.get('user_id')
        word_id = data.get('word_id')
        response = data.get('response')
        
        if not all([user_id, word_id is not None, response is not None]):
            return jsonify({"error": "user_id, word_id, and response are required"}), 400
        
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Record the current review time
        current_review_time = datetime.now()
        
        # Get existing review data before inserting new review
        cur.execute("""
            SELECT response, reviewed_at FROM reviews 
            WHERE user_id = %s AND word_id = %s 
            ORDER BY reviewed_at ASC
        """, (user_id, word_id))
        
        existing_reviews = [{"response": row['response'], "reviewed_at": row['reviewed_at']} for row in cur.fetchall()]
        
        # Convert boolean responses to numeric values (0.1 for false, 0.9 for true) for calculation
        numeric_reviews = []
        for review in existing_reviews:
            numeric_score = 0.9 if review['response'] else 0.1
            numeric_reviews.append((review['reviewed_at'], numeric_score))
        
        # Add current review
        current_numeric_score = 0.9 if response else 0.1
        numeric_reviews.append((current_review_time, current_numeric_score))
        
        # Calculate next review date using review.py
        next_review_date = get_next_review_datetime(numeric_reviews)
        
        # Insert the new review with calculated next_review_date
        cur.execute("""
            INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date)
            VALUES (%s, %s, %s, %s, %s)
        """, (user_id, word_id, response, current_review_time, next_review_date))
        
        conn.commit()
        
        # Calculate simple stats for response
        review_count = len(numeric_reviews)
        if len(numeric_reviews) >= 2:
            interval_days = (next_review_date - current_review_time).days
        else:
            interval_days = 1
        
        conn.close()
        
        return jsonify({
            "success": True,
            "word_id": word_id,
            "response": response,
            "review_count": review_count,
            "ease_factor": 2.5,
            "interval_days": interval_days,
            "next_review_date": next_review_date.isoformat()
        })
        
    except Exception as e:
        app.logger.error(f"Error submitting review: {str(e)}")
        return jsonify({"error": f"Failed to submit review: {str(e)}"}), 500

@app.route('/word', methods=['GET'])
def get_word_definition():
    """Get word definition with OpenAI integration"""
    try:
        user_id = request.args.get('user_id')
        word = request.args.get('w')
        
        if not word or not user_id:
            return jsonify({"error": "w and user_id parameters are required"}), 400
            
        word_normalized = word.strip().lower()
        
        # Get user preferences
        learning_lang, native_lang = get_user_preferences(user_id)
        
        # Try to get cached definition first
        cached = get_cached_definition(word_normalized, learning_lang, native_lang)
        
        if cached:
            app.logger.info(f"Using cached definition for '{word_normalized}' ({cached['cache_type']})")
            definition_data = cached['definition_data']
        else:
            # Generate new definition using OpenAI
            app.logger.info(f"Generating new definition for '{word_normalized}'")
            prompt = build_definition_prompt(word_normalized, learning_lang, native_lang)
            
            response = client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {
                        "role": "system",
                        "content": "You are a dictionary expert. Provide comprehensive definitions for words including different parts of speech, phonetic spelling, and example sentences."
                    },
                    {
                        "role": "user",
                        "content": prompt
                    }
                ],
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": "word_definition",
                        "schema": WORD_DEFINITION_SCHEMA
                    }
                },
                temperature=0.9
            )
            
            definition_data = json.loads(response.choices[0].message.content)
            
            # Store in cache
            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO definitions (word, learning_language, native_language, definition_data)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (word, learning_language, native_language) 
                DO UPDATE SET 
                    definition_data = EXCLUDED.definition_data,
                    updated_at = CURRENT_TIMESTAMP
            """, (word_normalized, learning_lang, native_lang, json.dumps(definition_data)))
            conn.commit()
            conn.close()
        
        # Collect audio references
        audio_refs = collect_audio_references(definition_data, learning_lang)
        
        # Add word audio if available  
        if audio_exists(word_normalized, learning_lang):
            audio_refs["word_audio"] = True
        
        # Queue missing audio generation
        audio_status = queue_missing_audio(word_normalized, definition_data, learning_lang, audio_refs)
        
        return jsonify({
            "word": word_normalized,
            "learning_language": learning_lang,
            "native_language": native_lang,
            "definition_data": definition_data,
            "audio_references": audio_refs,
            "audio_generation_status": audio_status
        })
        
    except Exception as e:
        app.logger.error(f"Error getting definition for word '{word_normalized}': {str(e)}")
        return jsonify({"error": f"Failed to get definition: {str(e)}"}), 500

@app.route('/saved_words', methods=['GET'])
def get_saved_words():
    """Get user's saved words with calculated review data"""
    try:
        user_id = request.args.get('user_id')
        due_only = request.args.get('due_only', 'false').lower() == 'true'
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get saved words with their latest review next_review_date
        cur.execute("""
            SELECT 
                sw.id, 
                sw.word, 
                sw.learning_language, 
                sw.metadata, 
                sw.created_at,
                COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') as next_review_date,
                COALESCE(latest_review.review_count, 0) as review_count,
                latest_review.last_reviewed_at
            FROM saved_words sw
            LEFT JOIN (
                SELECT 
                    word_id,
                    next_review_date,
                    reviewed_at as last_reviewed_at,
                    COUNT(*) as review_count,
                    ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                FROM reviews
                GROUP BY word_id, next_review_date, reviewed_at
            ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
            WHERE sw.user_id = %s
            ORDER BY COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') ASC
        """, (user_id,))
        
        rows = cur.fetchall()
        saved_words = []
        
        for row in rows:
            # Use values directly from the query
            review_count = row['review_count']
            last_reviewed_at = row['last_reviewed_at']
            next_review_date = row['next_review_date']
            
            # Calculate interval_days from next_review_date and last_reviewed_at (or created_at if no reviews)
            if last_reviewed_at and next_review_date:
                interval_days = (next_review_date.date() - last_reviewed_at.date()).days
            elif next_review_date:
                interval_days = (next_review_date.date() - row['created_at'].date()).days
            else:
                interval_days = 1
            
            # Filter by due_only if requested
            if due_only and next_review_date > datetime.now():
                continue
                
            saved_words.append({
                "id": row['id'],
                "word": row['word'],
                "learning_language": row['learning_language'],
                "metadata": row['metadata'],
                "created_at": row['created_at'].isoformat(),
                "review_count": review_count,
                "ease_factor": DEFAULT_EASE_FACTOR,  # Hardcoded as requested
                "interval_days": int(float(interval_days)) if interval_days else 1,
                "next_review_date": next_review_date.isoformat() if next_review_date else None,
                "last_reviewed_at": last_reviewed_at.isoformat() if last_reviewed_at else None
            })
        
        cur.close()
        conn.close()
        
        return jsonify({
            "user_id": user_id,
            "saved_words": saved_words,
            "count": len(saved_words),
            "due_only": due_only
        })
        
    except Exception as e:
        app.logger.error(f"Error getting saved words for user {user_id}: {str(e)}")
        return jsonify({"error": f"Failed to get saved words: {str(e)}"}), 500

@app.route('/users/<user_id>/preferences', methods=['GET', 'POST'])
def handle_user_preferences(user_id):
    """Get or update user language preferences"""
    try:
        if request.method == 'GET':
            learning_lang, native_lang = get_user_preferences(user_id)
            return jsonify({
                "user_id": user_id,
                "learning_language": learning_lang,
                "native_language": native_lang
            })
        
        elif request.method == 'POST':
            data = request.get_json()
            learning_lang = data.get('learning_language')
            native_lang = data.get('native_language')
            
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
                INSERT INTO user_preferences (user_id, learning_language, native_language)
                VALUES (%s, %s, %s)
                ON CONFLICT (user_id) 
                DO UPDATE SET 
                    learning_language = EXCLUDED.learning_language,
                    native_language = EXCLUDED.native_language,
                    updated_at = CURRENT_TIMESTAMP
            """, (user_id, learning_lang, native_lang))
            conn.commit()
            conn.close()
            
            return jsonify({
                "user_id": user_id,
                "learning_language": learning_lang,
                "native_language": native_lang,
                "updated": True
            })
    
    except Exception as e:
        app.logger.error(f"Error handling user preferences: {str(e)}")
        return jsonify({"error": f"Failed to handle user preferences: {str(e)}"}), 500

@app.route('/reviews/stats', methods=['GET'])
def get_review_stats():
    """Get review statistics for a user"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get basic stats
        cur.execute("""
            SELECT COUNT(*) as total_words FROM saved_words WHERE user_id = %s
        """, (user_id,))
        total_words = cur.fetchone()['total_words']
        
        # Get reviews today
        cur.execute("""
            SELECT COUNT(*) as reviews_today 
            FROM reviews 
            WHERE user_id = %s AND DATE(reviewed_at) = CURRENT_DATE
        """, (user_id,))
        reviews_today = cur.fetchone()['reviews_today']
        
        # Get success rate last 7 days
        cur.execute("""
            SELECT 
                COUNT(*) as total_reviews,
                SUM(CASE WHEN response = true THEN 1 ELSE 0 END) as correct_reviews
            FROM reviews 
            WHERE user_id = %s AND reviewed_at >= CURRENT_DATE - INTERVAL '7 days'
        """, (user_id,))
        
        week_stats = cur.fetchone()
        success_rate = 0.0
        if week_stats['total_reviews'] > 0:
            success_rate = float(week_stats['correct_reviews']) / float(week_stats['total_reviews'])
        
        cur.close()
        conn.close()
        
        return jsonify({
            "user_id": user_id,
            "total_words": total_words,
            "due_today": 0,  # Simplified - not calculating due today
            "reviews_today": reviews_today,
            "success_rate_7_days": success_rate,
            "streak_days": 1  # Simplified - not calculating streak
        })
        
    except Exception as e:
        app.logger.error(f"Error getting review stats: {str(e)}")
        return jsonify({"error": f"Failed to get review stats: {str(e)}"}), 500

@app.route('/words/<int:word_id>/details', methods=['GET'])
def get_word_details(word_id):
    """Get detailed information about a saved word"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get word details
        cur.execute("""
            SELECT id, word, learning_language, metadata, created_at
            FROM saved_words 
            WHERE id = %s AND user_id = %s
        """, (word_id, user_id))
        
        word = cur.fetchone()
        if not word:
            return jsonify({"error": "Word not found"}), 404
        
        # Get review history
        cur.execute("""
            SELECT response, reviewed_at
            FROM reviews
            WHERE word_id = %s AND user_id = %s
            ORDER BY reviewed_at DESC
        """, (word_id, user_id))
        
        review_history = []
        for review in cur.fetchall():
            review_history.append({
                "response": review['response'],
                "response_time_ms": None,  # Simplified
                "reviewed_at": review['reviewed_at'].isoformat()
            })
        
        # Calculate review data
        review_count, interval_days, next_review_date, last_reviewed_at = get_word_review_data(user_id, word_id)
        
        cur.close()
        conn.close()
        
        return jsonify({
            "id": word['id'],
            "word": word['word'],
            "learning_language": word['learning_language'],
            "metadata": word['metadata'],
            "created_at": word['created_at'].isoformat(),
            "review_count": review_count,
            "ease_factor": 2.5,
            "interval_days": interval_days,
            "next_review_date": next_review_date.isoformat() if next_review_date else None,
            "last_reviewed_at": last_reviewed_at.isoformat() if last_reviewed_at else None,
            "review_history": review_history
        })
        
    except Exception as e:
        app.logger.error(f"Error getting word details: {str(e)}")
        return jsonify({"error": f"Failed to get word details: {str(e)}"}), 500

@app.route('/audio/<path:text>/<language>')
def get_audio(text, language):
    """Get or generate audio for text+language"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Try to get existing audio
        cur.execute("""
            SELECT audio_data, content_type, created_at
            FROM audio 
            WHERE text_content = %s AND language = %s
        """, (text, language))
        
        result = cur.fetchone()
        
        if result:
            # Return existing audio
            conn.close()
            audio_base64 = base64.b64encode(result['audio_data']).decode('utf-8')
            
            return jsonify({
                "audio_data": audio_base64,
                "content_type": result['content_type'],
                "created_at": result['created_at'].isoformat() if result['created_at'] else None,
                "generated": False
            })
        
        # Audio doesn't exist, generate it
        conn.close()
        app.logger.info(f"Generating audio on-demand for text: '{text}' in {language}")
        
        try:
            audio_data = generate_audio_for_text(text)
            created_at = store_audio(text, language, audio_data)
            
            # Return the generated audio
            audio_base64 = base64.b64encode(audio_data).decode('utf-8')
            
            return jsonify({
                "audio_data": audio_base64,
                "content_type": "audio/mpeg",
                "created_at": created_at,
                "generated": True
            })
            
        except Exception as audio_error:
            app.logger.error(f"Failed to generate audio: {str(audio_error)}")
            return jsonify({"error": "Failed to generate audio"}), 500
        
    except Exception as e:
        app.logger.error(f"Error getting audio: {str(e)}")
        return jsonify({"error": f"Failed to get audio: {str(e)}"}), 500

@app.route('/languages', methods=['GET'])
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

@app.route('/fix_next_review_dates', methods=['POST'])
def fix_next_review_dates():
    """
    Fix existing review records by calculating proper next_review_date using get_next_review_datetime
    Reports statistics on correct vs incorrect records
    """
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        app.logger.info("Starting next_review_date fix process...")
        
        # Get all review records that have next_review_date (newest first per word)
        cur.execute("""
            WITH latest_reviews AS (
                SELECT word_id, user_id, MAX(reviewed_at) as latest_reviewed_at
                FROM reviews 
                WHERE next_review_date IS NOT NULL
                GROUP BY word_id, user_id
            )
            SELECT r.id, r.word_id, r.user_id, r.next_review_date, r.reviewed_at
            FROM reviews r
            INNER JOIN latest_reviews lr ON 
                r.word_id = lr.word_id AND 
                r.user_id = lr.user_id AND 
                r.reviewed_at = lr.latest_reviewed_at
            ORDER BY r.word_id, r.user_id
        """)
        
        records_to_check = cur.fetchall()
        app.logger.info(f"Found {len(records_to_check)} latest review records to check")
        
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
            
            try:
                # Get all review history for this word/user combination
                cur.execute("""
                    SELECT reviewed_at, response FROM reviews 
                    WHERE word_id = %s AND user_id = %s 
                    ORDER BY reviewed_at ASC
                """, (word_id, user_id))
                
                review_history = cur.fetchall()
                
                # Convert to format expected by get_next_review_datetime
                numeric_reviews = []
                for review in review_history:
                    numeric_score = 0.9 if review['response'] else 0.1
                    numeric_reviews.append((review['reviewed_at'], numeric_score))
                
                # Calculate correct next_review_date
                calculated_next_review_date = get_next_review_datetime(numeric_reviews)
                
                # Compare with current value (allowing for small time differences)
                current_date = datetime.fromisoformat(current_next_review_date.replace('Z', '+00:00')) if isinstance(current_next_review_date, str) else current_next_review_date
                time_diff = abs((calculated_next_review_date - current_date).total_seconds())
                
                # Consider dates within 1 minute as "correct" (to account for processing time differences)
                if time_diff <= 60:
                    stats['correct_records'] += 1
                    app.logger.info(f"Record {record_id} (word_id={word_id}): CORRECT")
                else:
                    stats['incorrect_records'] += 1
                    
                    # Update the record with correct next_review_date
                    cur.execute("""
                        UPDATE reviews 
                        SET next_review_date = %s 
                        WHERE id = %s
                    """, (calculated_next_review_date, record_id))
                    
                    stats['updated_records'] += 1
                    
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
                    
                    app.logger.info(f"Record {record_id} (word_id={word_id}): UPDATED - was {current_date}, now {calculated_next_review_date} (diff: {time_diff:.1f}s)")
                
            except Exception as e:
                stats['error_records'] += 1
                app.logger.error(f"Error processing record {record_id}: {str(e)}")
                
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
        
        app.logger.info(f"Fix process completed: {stats['updated_records']} records updated, {stats['correct_records']} were already correct")
        
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
        app.logger.error(f"Error in fix_next_review_dates: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
