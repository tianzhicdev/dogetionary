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

def generate_user_profile() -> tuple[str, str]:
    """Generate a proper, civil user name and motto using OpenAI with structured output"""
    try:
        response = openai.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system", 
                    "content": "You are a helpful assistant that generates appropriate, civil usernames and motivational mottos for language learning app users."
                },
                {
                    "role": "user", 
                    "content": "Generate a friendly, appropriate username and motivational motto for a language learning app user. The username should be suitable for all ages, contain no real names, and avoid numbers/special characters. The motto should be positive, motivational, related to learning or personal growth, and under 50 characters. Both should be completely appropriate, civil, and encouraging."
                }
            ],
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "user_profile",
                    "strict": True,
                    "schema": {
                        "type": "object",
                        "properties": {
                            "username": {
                                "type": "string",
                                "description": "A friendly, appropriate username suitable for all ages (max 20 characters)"
                            },
                            "motto": {
                                "type": "string", 
                                "description": "A positive, motivational motto related to learning (max 50 characters)"
                            }
                        },
                        "required": ["username", "motto"],
                        "additionalProperties": False
                    }
                }
            },
            max_tokens=150,
            temperature=0.7
        )
        
        # Parse the structured JSON response
        content = response.choices[0].message.content.strip()
        profile_data = json.loads(content)
        
        username = profile_data.get("username", "LearningExplorer")
        motto = profile_data.get("motto", "Every word is a new adventure!")
        
        # Ensure lengths are within limits
        username = username[:20] if len(username) > 20 else username
        motto = motto[:50] if len(motto) > 50 else motto
        
        app.logger.info(f"Generated user profile - Username: {username}, Motto: {motto}")
        return username, motto
        
    except Exception as e:
        app.logger.error(f"Error generating user profile: {str(e)}")
        # Provide safe fallbacks
        return "LearningExplorer", "Every word is a new adventure!"

def calculate_spaced_repetition(reviews_data, current_review_time=None):
    """
    DEPRECATED: Simple calculation for backward compatibility - SQL handles the logic now
    
    This function is deprecated and should not be used for new code.
    Use get_next_review_date_new from app.py instead.
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

def get_decay_rate(days_since_start_or_failure):
    """
    Calculate daily decay rate based on time elapsed since start or last failure.
    
    Decay schedule:
    - 0-7 days: 12.5% per day
    - 7-14 days: 6.25% per day  
    - 14-28 days: 3.125% per day
    - 28-56 days: 1.5625% per day
    - 56-112 days: 0.78125% per day
    - Continue halving every period doubling...
    """
    if days_since_start_or_failure < 7:
        return 0.125  # 12.5%
    elif days_since_start_or_failure < 14:
        return 0.0625  # 6.25%
    elif days_since_start_or_failure < 28:
        return 0.03125  # 3.125%
    elif days_since_start_or_failure < 56:
        return 0.015625  # 1.5625%
    elif days_since_start_or_failure < 112:
        return 0.0078125  # 0.78125%
    else:
        # Continue halving for longer periods
        period = 112
        rate = 0.0078125
        while days_since_start_or_failure >= period * 2:
            period *= 2
            rate /= 2
        return rate

def calculate_retention(review_history, target_date, created_at):
    """
    Calculate memory retention at a specific date using the new decay algorithm.
    
    Rules:
    - Every review sets retention to 100% regardless of success/failure
    - Failure resets decay rate to 12.5% per day (restart from week 1)
    - Success continues current decay schedule
    - Retention follows exponential decay: retention = e^(-rate * days)
    """
    import math
    from datetime import datetime, timedelta
    
    # Ensure we have datetime objects - convert if needed
    if not hasattr(target_date, 'hour'):
        target_date = datetime.combine(target_date, datetime.max.time())
    if not hasattr(created_at, 'hour'):
        created_at = datetime.combine(created_at, datetime.min.time())
    
    # If target date is before word creation, no retention
    if target_date < created_at:
        return 0.0
    
    # If target date is on the same day as creation, start at 100%
    if target_date.date() == created_at.date():
        return 1.0
    
    # If no reviews yet, start at 100% and decay from creation date
    if not review_history:
        days_since_creation = (target_date - created_at).days
        
        if days_since_creation == 0:
            return 1.0  # 100% on creation day
        
        # Calculate retention by applying decay cumulatively day by day
        retention = 1.0  # Start at 100% on creation day
        
        for day in range(1, days_since_creation + 1):
            current_day_date = created_at + timedelta(days=day)
            # Calculate days since creation for this day's decay rate
            days_since_start = (current_day_date - created_at).days
            daily_decay_rate = get_decay_rate(days_since_start)
            
            # Apply daily decay: retention = retention * e^(-daily_rate)
            retention = retention * math.exp(-daily_decay_rate)
            
        return max(0.0, min(1.0, retention))
    
    # Sort reviews by date
    sorted_reviews = sorted(review_history, key=lambda x: x['reviewed_at'])
    
    # Find the most recent review before or at target_date
    last_review = None
    last_failure_date = created_at  # Track when decay rate should reset
    
    for review in sorted_reviews:
        review_date = review['reviewed_at']
        
        # Ensure review_date is datetime for comparison
        if not hasattr(review_date, 'hour'):
            review_date = datetime.combine(review_date, datetime.min.time())
            
        if review_date <= target_date:
            last_review = review
            last_review['reviewed_at'] = review_date  # Update with datetime
            # If this review was a failure, reset the decay rate reference point
            if not review['response']:
                last_failure_date = review_date
        else:
            break
    
    # Calculate retention from the most recent review or creation
    if last_review:
        # Start from last review (always 100% immediately after any review)
        last_review_date = last_review['reviewed_at']
        days_since_review = (target_date - last_review_date).days
        
        # If same day as review, return 100%
        if target_date.date() == last_review_date.date():
            return 1.0  
        
        # Calculate retention by applying decay cumulatively day by day
        retention = 1.0  # Start at 100% after review
        
        for day in range(1, days_since_review + 1):
            current_day_date = last_review_date + timedelta(days=day)
            # Calculate days since last failure for this day's decay rate
            days_since_failure = (current_day_date - last_failure_date).days
            daily_decay_rate = get_decay_rate(days_since_failure)
            
            # Apply daily decay: retention = retention * e^(-daily_rate)
            retention = retention * math.exp(-daily_decay_rate)
            
        return max(0.0, min(1.0, retention))
    else:
        # No reviews before target date, decay from creation
        days_since_creation = (target_date - created_at).days
        
        # If same day as creation, start at 100%
        if target_date.date() == created_at.date():
            return 1.0
        
        # Calculate retention by applying decay cumulatively day by day
        retention = 1.0  # Start at 100% on creation day
        
        for day in range(1, days_since_creation + 1):
            current_day_date = created_at + timedelta(days=day)
            # Calculate days since creation for this day's decay rate
            days_since_start = (current_day_date - created_at).days
            daily_decay_rate = get_decay_rate(days_since_start)
            
            # Apply daily decay: retention = retention * e^(-daily_rate)
            retention = retention * math.exp(-daily_decay_rate)
            
        return max(0.0, min(1.0, retention))

def get_next_review_date_new(review_history, created_at):
    """
    Calculate when retention drops below 25% threshold using cumulative decay algorithm 
    that matches calculate_retention function.
    """
    import math
    from datetime import datetime, timedelta
    
    # Ensure created_at is datetime
    if not hasattr(created_at, 'hour'):
        created_at = datetime.combine(created_at, datetime.min.time())
    
    # Start from last review or creation date
    if review_history:
        sorted_reviews = sorted(review_history, key=lambda x: x['reviewed_at'])
        last_review = sorted_reviews[-1]
        start_date = last_review['reviewed_at']
        
        # Ensure start_date is datetime
        if not hasattr(start_date, 'hour'):
            start_date = datetime.combine(start_date, datetime.min.time())
            
        # Find last failure for decay rate reference point
        last_failure_date = created_at
        for review in sorted_reviews:
            review_date = review['reviewed_at']
            if not hasattr(review_date, 'hour'):
                review_date = datetime.combine(review_date, datetime.min.time())
            if not review['response']:
                last_failure_date = review_date
    else:
        start_date = created_at
        last_failure_date = created_at
    
    # Simulate retention decay day by day using same logic as calculate_retention
    current_date = start_date
    retention = 1.0  # Start at 100% after last review/creation
    max_days = 730  # Safety cap at 2 years
    
    for day in range(1, max_days + 1):
        current_date = start_date + timedelta(days=day)
        
        # Calculate days since last failure for decay rate determination
        days_since_failure = (current_date - last_failure_date).days
        daily_decay_rate = get_decay_rate(days_since_failure)
        
        # Apply daily decay: retention = retention * e^(-daily_rate)
        retention = retention * math.exp(-daily_decay_rate)
        
        # Check if retention dropped below 25%
        if retention <= 0.25:
            return current_date
    
    # If retention never drops below 25% in 2 years, return max date
    return start_date + timedelta(days=max_days)

def get_due_words_count(user_id, conn=None):
    """
    Shared function to calculate words due for review today (including overdue).
    
    Logic:
    - Words that have never been reviewed are due 1 day after being saved
    - Words with reviews are due based on their latest next_review_date
    - Uses consistent timestamp comparison (NOW() for precision)
    
    Returns dict with 'total_count' and 'due_count'
    """
    should_close_conn = conn is None
    if conn is None:
        conn = get_db_connection()
    
    try:
        cur = conn.cursor()
        
        # Single query to get both total and due counts using consistent logic
        cur.execute("""
            SELECT 
                COUNT(*) as total_count,
                COUNT(CASE 
                    WHEN COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= NOW() 
                    THEN 1 
                END) as due_count
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
        
        return {
            'total_count': result['total_count'] or 0,
            'due_count': result['due_count'] or 0
        }
        
    finally:
        if should_close_conn:
            conn.close()

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
        app.logger.error(f"Error getting user preferences: {str(e)}")
        return 'en', 'zh', 'LearningExplorer', 'Every word is a new adventure!'

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
            stored_learning_lang, _, _, _ = get_user_preferences(user_id)
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
            -- Exclude words reviewed in the past 24 hours
            AND (latest_review.last_reviewed_at IS NULL OR latest_review.last_reviewed_at <= NOW() - INTERVAL '24 hours')
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
        
        # Use shared function for consistent calculation
        result = get_due_words_count(user_id)
        
        return jsonify({
            "user_id": user_id,
            "overdue_count": result['due_count'],
            "total_count": result['total_count']
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
        
        # Get existing review data and word creation date
        cur.execute("""
            SELECT sw.created_at
            FROM saved_words sw
            WHERE sw.id = %s AND sw.user_id = %s
        """, (word_id, user_id))
        
        word_data = cur.fetchone()
        if not word_data:
            return jsonify({"error": "Word not found"}), 404
            
        created_at = word_data['created_at']
        
        cur.execute("""
            SELECT response, reviewed_at FROM reviews 
            WHERE user_id = %s AND word_id = %s 
            ORDER BY reviewed_at ASC
        """, (user_id, word_id))
        
        existing_reviews = [{"response": row['response'], "reviewed_at": row['reviewed_at']} for row in cur.fetchall()]
        
        # Add current review to history for next review calculation
        all_reviews = existing_reviews + [{"response": response, "reviewed_at": current_review_time}]
        
        # Calculate next review date using new algorithm
        next_review_date = get_next_review_date_new(all_reviews, created_at)
        
        # Insert the new review with calculated next_review_date
        cur.execute("""
            INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date)
            VALUES (%s, %s, %s, %s, %s)
        """, (user_id, word_id, response, current_review_time, next_review_date))
        
        conn.commit()
        
        # Calculate simple stats for response
        review_count = len(all_reviews)
        interval_days = (next_review_date - current_review_time).days if next_review_date else 1
        
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
        learning_lang, native_lang, _, _ = get_user_preferences(user_id)
        
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
        
        # Get saved words with their latest review next_review_date and correct review count
        cur.execute("""
            SELECT 
                sw.id, 
                sw.word, 
                sw.learning_language, 
                sw.metadata, 
                sw.created_at,
                COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') as next_review_date,
                COALESCE(review_counts.total_reviews, 0) as review_count,
                latest_review.last_reviewed_at
            FROM saved_words sw
            LEFT JOIN (
                SELECT 
                    word_id,
                    next_review_date,
                    reviewed_at as last_reviewed_at,
                    ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
                FROM reviews
            ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
            LEFT JOIN (
                SELECT 
                    word_id,
                    COUNT(*) as total_reviews
                FROM reviews
                GROUP BY word_id
            ) review_counts ON sw.id = review_counts.word_id
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
                "next_review_date": next_review_date.strftime('%Y-%m-%d') if next_review_date else None,
                "last_reviewed_at": last_reviewed_at.strftime('%Y-%m-%d %H:%M:%S') if last_reviewed_at else None
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
        
        # Calculate words due today using shared function for consistency
        due_result = get_due_words_count(user_id, conn)
        due_today = due_result['due_count']
        
        # Calculate streak days (consecutive days with reviews)
        cur.execute("""
            WITH daily_reviews AS (
                SELECT DISTINCT DATE(reviewed_at) as review_date
                FROM reviews
                WHERE user_id = %s
                AND reviewed_at >= CURRENT_DATE - INTERVAL '365 days'
                ORDER BY review_date DESC
            ),
            date_series AS (
                SELECT 
                    review_date,
                    CURRENT_DATE - review_date as days_ago,
                    ROW_NUMBER() OVER (ORDER BY review_date DESC) as row_num
                FROM daily_reviews
            )
            SELECT 
                COUNT(*) as streak_days
            FROM date_series
            WHERE days_ago = row_num - 1
            AND days_ago >= 0
        """, (user_id,))
        
        streak_result = cur.fetchone()
        streak_days = streak_result['streak_days'] if streak_result else 0
        
        cur.close()
        conn.close()
        
        return jsonify({
            "user_id": user_id,
            "total_words": total_words,
            "due_today": due_today,
            "reviews_today": reviews_today,
            "success_rate_7_days": success_rate,
            "streak_days": streak_days
        })
        
    except Exception as e:
        app.logger.error(f"Error getting review stats: {str(e)}")
        return jsonify({"error": f"Failed to get review stats: {str(e)}"}), 500

@app.route('/words/<int:word_id>/forgetting-curve', methods=['GET'])
def get_forgetting_curve(word_id):
    """Get forgetting curve data for a specific word"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get word details
        cur.execute("""
            SELECT id, word, learning_language, created_at
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
            ORDER BY reviewed_at ASC
        """, (word_id, user_id))
        
        review_history = []
        for review in cur.fetchall():
            review_history.append({
                "response": review['response'],
                "reviewed_at": review['reviewed_at']
            })
        
        cur.close()
        conn.close()
        
        # Calculate curve data points
        created_at = word['created_at']
        
        # Calculate next review date first
        next_review_date = get_next_review_date_new(review_history, created_at)
        
        # Determine time range: from creation to next review date (or 30 days if no reviews)
        if review_history:
            # Extend the curve to the next review date for complete visualization
            end_date = next_review_date if next_review_date else max([r['reviewed_at'] for r in review_history])
        else:
            # For words with no reviews, show until next review or 30 days
            end_date = next_review_date if next_review_date else (created_at + timedelta(days=30))
        
        # Generate curve points (one per day) - use datetime throughout
        curve_points = []
        
        # Ensure we have datetime objects
        current_datetime = created_at
        end_datetime = end_date
        
        # Start from beginning of creation day
        if hasattr(current_datetime, 'date'):
            current_datetime = datetime.combine(current_datetime.date(), datetime.min.time())
        else:
            current_datetime = datetime.combine(current_datetime, datetime.min.time())
            
        # End at end of last review day
        if hasattr(end_datetime, 'date'):
            end_datetime = datetime.combine(end_datetime.date(), datetime.max.time())
        else:
            end_datetime = datetime.combine(end_datetime, datetime.max.time())
        
        # Find last review date for determining solid vs dotted line
        last_review_date = None
        if review_history:
            last_review_date = max([r['reviewed_at'] for r in review_history])
            if hasattr(last_review_date, 'date'):
                last_review_date = last_review_date.date()
        
        # Generate points for each day
        while current_datetime <= end_datetime:
            # Use end of day for retention calculation (to include same-day reviews)
            end_of_day = datetime.combine(current_datetime.date(), datetime.max.time())
            retention = calculate_retention(review_history, end_of_day, created_at)
            
            # Determine if this point is part of the solid line (historical) or dotted line (projection)
            is_projection = False
            if last_review_date and current_datetime.date() > last_review_date:
                is_projection = True
            
            curve_points.append({
                "date": current_datetime.strftime('%Y-%m-%d'),  # Display as date string
                "retention": retention * 100,  # Convert to percentage
                "is_projection": is_projection  # Flag for UI to render as dotted line
            })
            
            # Move to next day (start of day)
            current_datetime = datetime.combine((current_datetime + timedelta(days=1)).date(), datetime.min.time())
        
        # Prepare all markers including creation and next review
        all_markers = []
        
        # Add creation marker
        all_markers.append({
            "date": created_at.strftime('%Y-%m-%d'),
            "type": "creation",
            "success": None
        })
        
        # Add review markers
        for r in review_history:
            all_markers.append({
                "date": r['reviewed_at'].strftime('%Y-%m-%d'),
                "type": "review",
                "success": r['response']
            })
        
        # Add next review marker if available
        if next_review_date:
            all_markers.append({
                "date": next_review_date.strftime('%Y-%m-%d'),
                "type": "next_review",
                "success": None
            })

        return jsonify({
            "word_id": word_id,
            "word": word['word'],
            "created_at": created_at.strftime('%Y-%m-%d'),
            "forgetting_curve": curve_points,
            "next_review_date": next_review_date.strftime('%Y-%m-%d') if next_review_date else None,
            "review_markers": [
                {
                    "date": r['reviewed_at'].strftime('%Y-%m-%d'),
                    "success": r['response']
                }
                for r in review_history
            ],
            "all_markers": all_markers
        })
        
    except Exception as e:
        app.logger.error(f"Error getting forgetting curve: {str(e)}")
        return jsonify({"error": f"Failed to get forgetting curve: {str(e)}"}), 500

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
                "reviewed_at": review['reviewed_at'].strftime('%Y-%m-%d %H:%M:%S')
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
            "created_at": word['created_at'].strftime('%Y-%m-%d %H:%M:%S'),
            "review_count": review_count,
            "ease_factor": 2.5,
            "interval_days": interval_days,
            "next_review_date": next_review_date.strftime('%Y-%m-%d %H:%M:%S') if next_review_date else None,
            "last_reviewed_at": last_reviewed_at.strftime('%Y-%m-%d %H:%M:%S') if last_reviewed_at else None,
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
    Fix existing review records by calculating proper next_review_date using get_next_review_date_new
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
                # Get word creation date
                cur.execute("""
                    SELECT created_at FROM saved_words 
                    WHERE id = %s AND user_id = %s
                """, (word_id, user_id))
                
                word_data = cur.fetchone()
                if not word_data:
                    app.logger.warning(f"Word {word_id} not found for user {user_id}")
                    continue
                
                created_at = word_data['created_at']
                
                # Get all review history for this word/user combination
                cur.execute("""
                    SELECT reviewed_at, response FROM reviews 
                    WHERE word_id = %s AND user_id = %s 
                    ORDER BY reviewed_at ASC
                """, (word_id, user_id))
                
                review_history = cur.fetchall()
                
                # Convert to format expected by get_next_review_date_new
                numeric_reviews = []
                for review in review_history:
                    numeric_score = 1 if review['response'] else 0
                    numeric_reviews.append((review['reviewed_at'], numeric_score))
                
                # Calculate correct next_review_date
                calculated_next_review_date = get_next_review_date_new(numeric_reviews, created_at)
                
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

@app.route('/privacy', methods=['GET'])
def privacy_agreement():
    """Display comprehensive privacy agreement and terms of service"""
    
    privacy_policy = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Unforgettable Dictionary Privacy Policy and Terms of Service</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 20px; color: #333; }
            h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
            h2 { color: #34495e; margin-top: 30px; border-left: 4px solid #3498db; padding-left: 15px; }
            h3 { color: #2c3e50; margin-top: 25px; }
            .effective-date { background: #ecf0f1; padding: 10px; border-radius: 5px; margin-bottom: 20px; font-weight: bold; }
            .warning { background: #fff3cd; border: 1px solid #ffeaa7; padding: 15px; border-radius: 5px; margin: 20px 0; }
            .important { background: #d1ecf1; border: 1px solid #bee5eb; padding: 15px; border-radius: 5px; margin: 20px 0; }
            ul { margin-left: 20px; }
            li { margin-bottom: 8px; }
            .contact { background: #f8f9fa; padding: 15px; border-radius: 5px; margin-top: 30px; }
        </style>
    </head>
    <body>
        <h1>Unforgettable Dictionary Privacy Policy and Terms of Service</h1>
        
        <div class="effective-date">
            Effective Date: September 10, 2025<br>
            Last Updated: September 10, 2025<br>
            Version: 1.0
        </div>

        <div class="warning">
            <strong>IMPORTANT NOTICE:</strong> This service is powered by artificial intelligence technologies. While we strive for accuracy, AI-generated content may contain errors, inaccuracies, or inappropriate material. Users acknowledge that they use this service at their own discretion and risk.
        </div>

        <h2>1. ACCEPTANCE OF TERMS AND PRIVACY POLICY</h2>
        <p>By accessing, downloading, installing, or using the Unforgettable Dictionary application ("Service", "App", "Platform"), you ("User", "You", "Your") hereby acknowledge that you have read, understood, and agree to be bound by this Privacy Policy and Terms of Service Agreement ("Agreement") in its entirety. If you do not agree with any provision of this Agreement, you must immediately discontinue use of the Service.</p>

        <h2>2. DEFINITIONS AND INTERPRETATIONS</h2>
        <h3>2.1 Key Definitions</h3>
        <ul>
            <li><strong>"Personal Data"</strong> means any information relating to an identified or identifiable natural person;</li>
            <li><strong>"Processing"</strong> means any operation performed on personal data, including collection, recording, organization, structuring, storage, adaptation, retrieval, consultation, use, disclosure, dissemination, or erasure;</li>
            <li><strong>"Data Controller"</strong> means Unforgettable Dictionary and its affiliated entities;</li>
            <li><strong>"Third Parties"</strong> means any individual, company, or organization that is not directly affiliated with Unforgettable Dictionary;</li>
            <li><strong>"AI Technology"</strong> refers to artificial intelligence, machine learning, and automated systems used to provide dictionary, translation, and language learning services;</li>
        </ul>

        <h2>3. INFORMATION COLLECTION AND USAGE</h2>
        <h3>3.1 Types of Information Collected</h3>
        <p>We may collect and process the following categories of information:</p>
        <ul>
            <li><strong>Account Information:</strong> User identification data, language preferences, learning progress</li>
            <li><strong>Usage Data:</strong> Word searches, review responses, study patterns, application interaction metrics</li>
            <li><strong>Device Information:</strong> Device type, operating system, application version, unique device identifiers</li>
            <li><strong>Performance Data:</strong> Response times, error logs, crash reports for service improvement</li>
            <li><strong>User-Generated Content:</strong> Saved words, personal notes, study materials</li>
        </ul>

        <h3>3.2 Purposes of Data Processing</h3>
        <p>Your information is processed for the following legitimate purposes:</p>
        <ul>
            <li>Providing personalized language learning experiences</li>
            <li>Maintaining spaced repetition algorithms for optimal learning</li>
            <li>Generating audio pronunciations and definitions</li>
            <li>Improving AI accuracy and service quality</li>
            <li>Technical support and troubleshooting</li>
            <li>Analytics for product development and enhancement</li>
            <li>Ensuring security and preventing misuse</li>
        </ul>

        <h2>4. DATA PROTECTION AND PRIVACY RIGHTS</h2>
        
        <div class="important">
            <strong>FUNDAMENTAL COMMITMENT:</strong> We solemnly commit that your personal data will NOT be shared, sold, leased, or otherwise disclosed to any third parties for commercial, marketing, or any other purposes without your explicit consent.
        </div>

        <h3>4.1 Data Security Measures</h3>
        <ul>
            <li>Industry-standard encryption for data transmission and storage</li>
            <li>Regular security audits and vulnerability assessments</li>
            <li>Access controls and authentication mechanisms</li>
            <li>Data backup and recovery procedures</li>
            <li>Incident response and breach notification protocols</li>
        </ul>

        <h3>4.2 Your Privacy Rights</h3>
        <p>Subject to applicable laws, you have the following rights regarding your personal data:</p>
        <ul>
            <li><strong>Right of Access:</strong> Request information about personal data we process</li>
            <li><strong>Right to Rectification:</strong> Correct inaccurate or incomplete data</li>
            <li><strong>Right to Erasure:</strong> Request deletion of your personal data</li>
            <li><strong>Right to Portability:</strong> Receive your data in a structured, machine-readable format</li>
            <li><strong>Right to Restriction:</strong> Limit processing of your personal data</li>
            <li><strong>Right to Object:</strong> Object to processing based on legitimate interests</li>
        </ul>

        <h2>5. ARTIFICIAL INTELLIGENCE DISCLAIMER</h2>
        
        <div class="warning">
            <strong>AI-POWERED SERVICE LIMITATIONS:</strong> This service utilizes advanced artificial intelligence and machine learning technologies to provide definitions, translations, pronunciations, and language learning content. Users must understand and acknowledge the following:
        </div>

        <h3>5.1 AI Content Limitations</h3>
        <ul>
            <li>AI-generated content may contain factual errors, inaccuracies, or misleading information</li>
            <li>Translations and definitions may not always be contextually appropriate</li>
            <li>Cultural nuances and regional variations may not be accurately represented</li>
            <li>Generated audio pronunciations may contain accent variations or pronunciation errors</li>
            <li>The AI system continuously learns and improves, but perfection cannot be guaranteed</li>
        </ul>

        <h3>5.2 User Responsibility</h3>
        <p>Users acknowledge that:</p>
        <ul>
            <li>They use AI-generated content at their own discretion and risk</li>
            <li>They should verify important information through additional sources</li>
            <li>The service is intended for educational purposes and general language learning</li>
            <li>Critical or professional language needs should be verified by qualified human experts</li>
        </ul>

        <h2>6. DATA RETENTION AND DELETION</h2>
        <h3>6.1 Retention Periods</h3>
        <ul>
            <li><strong>Account Data:</strong> Retained while account is active plus 12 months after deactivation</li>
            <li><strong>Learning Progress:</strong> Retained for 24 months to maintain learning continuity</li>
            <li><strong>Usage Analytics:</strong> Aggregated and anonymized data retained for 36 months</li>
            <li><strong>Technical Logs:</strong> Retained for 6 months for troubleshooting purposes</li>
        </ul>

        <h3>6.2 Data Deletion Procedures</h3>
        <p>Upon request or account termination, we will securely delete your personal data within 30 days, except where retention is required by law or for legitimate business purposes.</p>

        <h2>7. COOKIES AND TRACKING TECHNOLOGIES</h2>
        <p>We may use cookies, local storage, and similar technologies to:</p>
        <ul>
            <li>Maintain user sessions and preferences</li>
            <li>Analyze usage patterns and improve user experience</li>
            <li>Provide personalized content and recommendations</li>
            <li>Ensure security and prevent fraud</li>
        </ul>

        <h2>8. INTERNATIONAL DATA TRANSFERS</h2>
        <p>Your data may be processed in countries other than your country of residence. We ensure appropriate safeguards are in place for international transfers, including:</p>
        <ul>
            <li>Adequacy decisions by relevant data protection authorities</li>
            <li>Standard contractual clauses approved by the European Commission</li>
            <li>Binding corporate rules for intra-group transfers</li>
            <li>Other legally recognized transfer mechanisms</li>
        </ul>

        <h2>9. CHILDREN'S PRIVACY</h2>
        <p>Our service is not directed to children under 13 years of age. We do not knowingly collect personal information from children under 13. If we become aware that we have collected personal data from a child under 13, we will take steps to delete such information.</p>

        <h2>10. THIRD-PARTY SERVICES AND INTEGRATIONS</h2>
        <p>While we do not share your personal data with third parties for their own purposes, our service may integrate with:</p>
        <ul>
            <li>Cloud infrastructure providers (for hosting and storage)</li>
            <li>Analytics services (for aggregated usage statistics)</li>
            <li>AI and machine learning platforms (for content generation)</li>
            <li>Audio synthesis services (for pronunciation generation)</li>
        </ul>
        <p>These integrations are governed by strict data processing agreements that prohibit unauthorized use of your data.</p>

        <h2>11. LEGAL BASIS FOR PROCESSING</h2>
        <p>We process your personal data based on the following legal grounds:</p>
        <ul>
            <li><strong>Consent:</strong> Where you have given clear consent for specific processing activities</li>
            <li><strong>Contract Performance:</strong> To provide the language learning services you requested</li>
            <li><strong>Legitimate Interests:</strong> For service improvement, security, and analytics</li>
            <li><strong>Legal Obligation:</strong> To comply with applicable laws and regulations</li>
        </ul>

        <h2>12. UPDATES TO THIS PRIVACY POLICY</h2>
        <p>We may update this Privacy Policy periodically to reflect changes in our practices, technology, legal requirements, or other factors. We will notify users of material changes through:</p>
        <ul>
            <li>In-app notifications</li>
            <li>Email notifications (if applicable)</li>
            <li>Website announcements</li>
            <li>Updated version numbers and effective dates</li>
        </ul>

        <h2>13. CONTACT INFORMATION AND DATA PROTECTION OFFICER</h2>
        <div class="contact">
            <h3>Privacy Inquiries and Data Subject Requests</h3>
            <p>For any privacy-related questions, concerns, or to exercise your data protection rights, please contact us:</p>
            <ul>
                <li><strong>Email:</strong> privacy@unforgettabledictionary.com</li>
                <li><strong>Data Protection Officer:</strong> dpo@unforgettabledictionary.com</li>
                <li><strong>Mailing Address:</strong> Unforgettable Dictionary Privacy Office, [Address to be determined]</li>
                <li><strong>Response Time:</strong> We will respond to all inquiries within 30 days</li>
            </ul>
        </div>

        <h2>14. GOVERNING LAW AND JURISDICTION</h2>
        <p>This Privacy Policy and Terms of Service shall be governed by and construed in accordance with applicable data protection laws, including but not limited to the General Data Protection Regulation (GDPR), California Consumer Privacy Act (CCPA), and other relevant privacy legislation.</p>

        <h2>15. SEVERABILITY AND ENFORCEABILITY</h2>
        <p>If any provision of this Agreement is found to be unenforceable or invalid, that provision will be limited or eliminated to the minimum extent necessary so that this Agreement will otherwise remain in full force and effect and enforceable.</p>

        <div class="important">
            <h3>ACKNOWLEDGMENT</h3>
            <p>By using Unforgettable Dictionary, you acknowledge that you have read this Privacy Policy and Terms of Service, understand its contents, and agree to be bound by its terms. You also acknowledge the AI-powered nature of our service and accept the associated limitations and risks.</p>
        </div>

        <hr style="margin-top: 40px;">
        <p style="text-align: center; color: #7f8c8d; font-size: 14px;">
            © 2025 Unforgettable Dictionary. All rights reserved. Generated on {timestamp}
        </p>
    </body>
    </html>
    """
    
    # Replace timestamp placeholder
    privacy_policy = privacy_policy.replace('{timestamp}', datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC'))
    
    return Response(privacy_policy, mimetype='text/html')

@app.route('/support', methods=['GET'])
def support_page():
    """Support page with app information and contact details"""
    support_html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Support - Unforgettable Dictionary</title>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
                line-height: 1.6;
                color: #333;
                max-width: 800px;
                margin: 0 auto;
                padding: 20px;
                background-color: #f8f9fa;
            }
            .container {
                background: white;
                padding: 40px;
                border-radius: 12px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            h1 {
                color: #2c3e50;
                text-align: center;
                margin-bottom: 30px;
                font-size: 2.5em;
            }
            h2 {
                color: #3498db;
                border-bottom: 2px solid #ecf0f1;
                padding-bottom: 10px;
                margin-top: 30px;
            }
            .hero {
                text-align: center;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 30px;
                border-radius: 8px;
                margin-bottom: 30px;
            }
            .hero h2 {
                border: none;
                color: white;
                margin: 0;
                font-size: 1.8em;
            }
            .hero p {
                font-size: 1.2em;
                margin: 15px 0 0 0;
                opacity: 0.9;
            }
            .feature {
                background: #f8f9fa;
                padding: 20px;
                border-radius: 8px;
                margin: 15px 0;
                border-left: 4px solid #3498db;
            }
            .feature h3 {
                color: #2c3e50;
                margin-top: 0;
            }
            .contact {
                background: #e8f5e8;
                padding: 25px;
                border-radius: 8px;
                text-align: center;
                margin-top: 30px;
                border: 2px solid #27ae60;
            }
            .contact h3 {
                color: #27ae60;
                margin-top: 0;
            }
            .email {
                background: #3498db;
                color: white;
                padding: 12px 24px;
                border-radius: 6px;
                text-decoration: none;
                display: inline-block;
                margin-top: 10px;
                transition: background-color 0.3s;
            }
            .email:hover {
                background: #2980b9;
                color: white;
                text-decoration: none;
            }
            ul {
                padding-left: 20px;
            }
            li {
                margin-bottom: 8px;
            }
            .algorithm-box {
                background: #fff3cd;
                border: 1px solid #ffeaa7;
                padding: 20px;
                border-radius: 8px;
                margin: 15px 0;
            }
            .algorithm-box h3 {
                color: #856404;
                margin-top: 0;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="hero">
                <h2>📚 Unforgettable Dictionary</h2>
                <p>Making every lookup truly unforgettable</p>
            </div>

            <h2>🎯 What is Unforgettable Dictionary?</h2>
            <p>Unforgettable Dictionary is an intelligent vocabulary building app designed to help you learn and retain new words effectively. Instead of traditional memorization methods, our app uses scientifically-proven spaced repetition techniques to optimize your learning experience.</p>

            <div class="feature">
                <h3>🧠 Smart Learning System</h3>
                <p>Our app helps you build your vocabulary over time by leveraging small pieces of your day. Whether you have 2 minutes or 20 minutes, you can make meaningful progress in expanding your word knowledge.</p>
            </div>

            <div class="algorithm-box">
                <h3>⚡ SuperMemo Algorithm</h3>
                <p>We use the renowned <strong>SuperMemo spaced repetition algorithm</strong> to determine the optimal timing for reviewing each word. This algorithm:</p>
                <ul>
                    <li>Analyzes your performance on each word</li>
                    <li>Calculates the ideal review intervals</li>
                    <li>Schedules reviews just before you're likely to forget</li>
                    <li>Adapts to your individual learning pace</li>
                </ul>
                <p>This scientific approach ensures maximum retention with minimum effort, making your vocabulary growth both efficient and sustainable.</p>
            </div>

            <h2>✨ Key Features</h2>
            <div class="feature">
                <h3>🔍 Intelligent Word Lookup</h3>
                <p>Search for any word and get comprehensive definitions, translations, pronunciations, and example sentences powered by AI.</p>
            </div>

            <div class="feature">
                <h3>💾 Personal Vocabulary Collection</h3>
                <p>Save words that interest you and build your personal vocabulary library. Track your progress and see how your knowledge grows.</p>
            </div>

            <div class="feature">
                <h3>🎯 Spaced Repetition Reviews</h3>
                <p>Review saved words at scientifically optimized intervals. The app knows exactly when to show you each word for maximum retention.</p>
            </div>

            <div class="feature">
                <h3>🔊 Audio Pronunciation</h3>
                <p>Hear correct pronunciations for words and examples to improve your speaking and listening skills.</p>
            </div>

            <div class="feature">
                <h3>🌍 Multi-language Support</h3>
                <p>Learn vocabulary in over 50 languages with native language translations and cultural context.</p>
            </div>

            <div class="feature">
                <h3>📊 Progress Tracking</h3>
                <p>Monitor your learning journey with detailed statistics, success rates, and review streaks.</p>
            </div>

            <h2>🚀 How It Works</h2>
            <ol>
                <li><strong>Discover:</strong> Look up new words as you encounter them in reading, conversations, or daily life</li>
                <li><strong>Save:</strong> Add interesting words to your personal vocabulary collection</li>
                <li><strong>Review:</strong> Use the review mode to practice your saved words</li>
                <li><strong>Master:</strong> The algorithm schedules reviews at optimal intervals until words become unforgettable</li>
            </ol>

            <h2>💡 Tips for Success</h2>
            <ul>
                <li>Review consistently, even if just for a few minutes daily</li>
                <li>Be honest during reviews - the algorithm learns from your responses</li>
                <li>Save words that are personally relevant or interesting to you</li>
                <li>Use the audio features to improve pronunciation</li>
                <li>Don't worry about forgetting - that's part of the learning process!</li>
            </ul>

            <div class="contact">
                <h3>📧 Need Help?</h3>
                <p>Have questions, suggestions, or need technical support?<br>
                We're here to help make your vocabulary journey successful!</p>
                <a href="mailto:tianzhic.dev@gmail.com" class="email">
                    Contact Support: tianzhic.dev@gmail.com
                </a>
                <p style="margin-top: 15px; font-size: 0.9em; opacity: 0.8;">
                    We typically respond within 24 hours
                </p>
            </div>

            <hr style="margin: 40px 0; border: none; border-top: 1px solid #ecf0f1;">
            <p style="text-align: center; color: #7f8c8d; font-size: 14px;">
                © 2025 Unforgettable Dictionary. Making vocabulary learning efficient and enjoyable.
            </p>
        </div>
    </body>
    </html>
    """
    
    return Response(support_html, mimetype='text/html')

@app.route('/review_statistics', methods=['GET'])
def get_review_statistics():
    """Get comprehensive review statistics"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Total reviews
        cur.execute("SELECT COUNT(*) as count FROM reviews WHERE user_id = %s", (user_id,))
        total_reviews = cur.fetchone()['count'] or 0
        
        # Streak days (continuous days with reviews)
        cur.execute("""
            WITH review_days AS (
                SELECT DISTINCT DATE(reviewed_at) as review_date
                FROM reviews
                WHERE user_id = %s
                ORDER BY review_date DESC
            ),
            streaks AS (
                SELECT review_date,
                       review_date - INTERVAL '1 day' * ROW_NUMBER() OVER (ORDER BY review_date DESC) as grp
                FROM review_days
            )
            SELECT COUNT(*) as streak_length
            FROM streaks
            WHERE grp = (SELECT MAX(grp) FROM streaks WHERE review_date >= CURRENT_DATE - INTERVAL '1 day')
        """, (user_id,))
        result = cur.fetchone()
        streak_days = result['streak_length'] if result and result['streak_length'] else 0
        
        # Average reviews per week (since first review)
        cur.execute("""
            SELECT 
                MIN(reviewed_at) as first_review,
                COUNT(*) as total_count
            FROM reviews
            WHERE user_id = %s
        """, (user_id,))
        result = cur.fetchone()
        if result and result['first_review']:
            weeks_since_start = max(1, (datetime.now() - result['first_review']).days / 7)
            avg_reviews_per_week = result['total_count'] / weeks_since_start
        else:
            avg_reviews_per_week = 0
        
        # Average reviews per active day
        cur.execute("""
            SELECT COUNT(DISTINCT DATE(reviewed_at)) as active_days
            FROM reviews
            WHERE user_id = %s
        """, (user_id,))
        active_days = cur.fetchone()['active_days'] or 1
        avg_reviews_per_active_day = total_reviews / active_days if active_days > 0 else 0
        
        # Week over week change
        cur.execute("""
            WITH week_counts AS (
                SELECT 
                    COUNT(CASE WHEN reviewed_at >= NOW() - INTERVAL '7 days' THEN 1 END) as this_week,
                    COUNT(CASE WHEN reviewed_at >= NOW() - INTERVAL '14 days' 
                               AND reviewed_at < NOW() - INTERVAL '7 days' THEN 1 END) as last_week
                FROM reviews
                WHERE user_id = %s
            )
            SELECT this_week, last_week FROM week_counts
        """, (user_id,))
        result = cur.fetchone()
        this_week = result['this_week'] or 0
        last_week = result['last_week'] or 1
        week_over_week_change = ((this_week - last_week) / last_week * 100) if last_week > 0 else 0
        
        cur.close()
        conn.close()
        
        return jsonify({
            "total_reviews": total_reviews,
            "streak_days": streak_days,
            "avg_reviews_per_week": round(avg_reviews_per_week, 1),
            "avg_reviews_per_active_day": round(avg_reviews_per_active_day, 1),
            "week_over_week_change": round(week_over_week_change)
        })
        
    except Exception as e:
        app.logger.error(f"Error getting review statistics: {str(e)}")
        return jsonify({"error": f"Failed to get review statistics: {str(e)}"}), 500

@app.route('/weekly_review_counts', methods=['GET'])
def get_weekly_review_counts():
    """Get daily review counts for the past 7 days"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get counts for past 7 days
        cur.execute("""
            WITH date_series AS (
                SELECT generate_series(
                    CURRENT_DATE - INTERVAL '6 days',
                    CURRENT_DATE,
                    '1 day'::interval
                )::date as date
            )
            SELECT 
                ds.date,
                COALESCE(COUNT(r.id), 0) as count
            FROM date_series ds
            LEFT JOIN reviews r ON DATE(r.reviewed_at) = ds.date AND r.user_id = %s
            GROUP BY ds.date
            ORDER BY ds.date ASC
        """, (user_id,))
        
        daily_counts = []
        for row in cur.fetchall():
            daily_counts.append({
                "date": row['date'].strftime('%Y-%m-%d'),
                "count": row['count']
            })
        
        cur.close()
        conn.close()
        
        return jsonify({
            "daily_counts": daily_counts
        })
        
    except Exception as e:
        app.logger.error(f"Error getting weekly review counts: {str(e)}")
        return jsonify({"error": f"Failed to get weekly review counts: {str(e)}"}), 500

@app.route('/progress_funnel', methods=['GET'])
def get_progress_funnel():
    """Get progress funnel data showing words at different memorization stages"""
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Stage 1: Words with any successful review
        cur.execute("""
            SELECT COUNT(DISTINCT sw.id) as count
            FROM saved_words sw
            JOIN reviews r ON sw.id = r.word_id
            WHERE sw.user_id = %s AND r.response = true
        """, (user_id,))
        stage1_count = cur.fetchone()['count'] or 0
        
        # Stage 2: Words with 2+ continuous successful reviews in past 7 days
        cur.execute("""
            WITH recent_reviews AS (
                SELECT 
                    sw.id as word_id,
                    r.response,
                    r.reviewed_at,
                    LAG(r.response) OVER (PARTITION BY sw.id ORDER BY r.reviewed_at DESC) as prev_response
                FROM saved_words sw
                JOIN reviews r ON sw.id = r.word_id
                WHERE sw.user_id = %s 
                    AND r.reviewed_at >= NOW() - INTERVAL '7 days'
            )
            SELECT COUNT(DISTINCT word_id) as count
            FROM recent_reviews
            WHERE response = true AND prev_response = true
        """, (user_id,))
        stage2_count = cur.fetchone()['count'] or 0
        
        # Stage 3: Words with 3+ successful reviews in past 14 days
        cur.execute("""
            SELECT COUNT(DISTINCT sw.id) as count
            FROM saved_words sw
            JOIN reviews r ON sw.id = r.word_id
            WHERE sw.user_id = %s 
                AND r.reviewed_at >= NOW() - INTERVAL '14 days'
                AND r.response = true
            GROUP BY sw.id
            HAVING COUNT(*) >= 3
        """, (user_id,))
        result = cur.fetchall()
        stage3_count = len(result)
        
        # Stage 4: Words with 4+ successful reviews in past 28 days
        cur.execute("""
            SELECT COUNT(DISTINCT sw.id) as count
            FROM saved_words sw
            JOIN reviews r ON sw.id = r.word_id
            WHERE sw.user_id = %s 
                AND r.reviewed_at >= NOW() - INTERVAL '28 days'
                AND r.response = true
            GROUP BY sw.id
            HAVING COUNT(*) >= 4
        """, (user_id,))
        result = cur.fetchall()
        stage4_count = len(result)
        
        # Get total saved words count
        cur.execute("""
            SELECT COUNT(*) as count
            FROM saved_words
            WHERE user_id = %s
        """, (user_id,))
        total_words = cur.fetchone()['count'] or 0
        
        cur.close()
        conn.close()
        
        app.logger.info(f"Progress funnel for user {user_id}: Stage1={stage1_count}, Stage2={stage2_count}, Stage3={stage3_count}, Stage4={stage4_count}")
        
        return jsonify({
            "stage1_count": stage1_count,
            "stage2_count": stage2_count,
            "stage3_count": stage3_count,
            "stage4_count": stage4_count,
            "total_words": total_words
        })
        
    except Exception as e:
        app.logger.error(f"Error getting progress funnel: {str(e)}")
        return jsonify({"error": f"Failed to get progress funnel: {str(e)}"}), 500

@app.route('/review_activity', methods=['GET'])
def get_review_activity():
    """Get review activity dates for calendar display"""
    try:
        user_id = request.args.get('user_id')
        start_date = request.args.get('start_date')
        end_date = request.args.get('end_date')
        
        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400
        if not start_date or not end_date:
            return jsonify({"error": "start_date and end_date parameters are required"}), 400
        
        # Parse ISO date strings
        try:
            start_dt = datetime.fromisoformat(start_date.replace('Z', '+00:00'))
            end_dt = datetime.fromisoformat(end_date.replace('Z', '+00:00'))
        except ValueError as e:
            return jsonify({"error": f"Invalid date format: {e}"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get unique dates where user had reviews
        cur.execute("""
            SELECT DISTINCT DATE(reviewed_at) as review_date
            FROM reviews 
            WHERE user_id = %s 
            AND reviewed_at >= %s 
            AND reviewed_at <= %s
            ORDER BY review_date ASC
        """, (user_id, start_dt, end_dt))
        
        review_dates = []
        for row in cur.fetchall():
            # Format as YYYY-MM-DD string
            review_dates.append(row['review_date'].strftime('%Y-%m-%d'))
        
        cur.close()
        conn.close()
        
        app.logger.info(f"Found {len(review_dates)} review dates for user {user_id} between {start_date} and {end_date}")
        
        return jsonify({
            "user_id": user_id,
            "review_dates": review_dates,
            "start_date": start_date,
            "end_date": end_date
        })
        
    except Exception as e:
        app.logger.error(f"Error getting review activity: {str(e)}")
        return jsonify({"error": f"Failed to get review activity: {str(e)}"}), 500

@app.route('/leaderboard', methods=['GET'])
def get_leaderboard():
    """Get leaderboard with all users ranked by total review count"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get all users with their review counts, name, and motto
        cur.execute("""
            SELECT 
                up.user_id,
                COALESCE(up.user_name, 'Anonymous') as user_name,
                COALESCE(up.user_motto, '') as user_motto,
                COALESCE(COUNT(r.id), 0) as total_reviews
            FROM user_preferences up
            LEFT JOIN saved_words sw ON up.user_id = sw.user_id
            LEFT JOIN reviews r ON sw.id = r.word_id
            GROUP BY up.user_id, up.user_name, up.user_motto
            ORDER BY total_reviews DESC, up.user_name ASC
        """)
        
        leaderboard = []
        rank = 1
        for row in cur.fetchall():
            leaderboard.append({
                "rank": rank,
                "user_id": row['user_id'],
                "user_name": row['user_name'],
                "user_motto": row['user_motto'], 
                "total_reviews": row['total_reviews']
            })
            rank += 1
        
        cur.close()
        conn.close()
        
        return jsonify({
            "leaderboard": leaderboard,
            "total_users": len(leaderboard)
        })
        
    except Exception as e:
        app.logger.error(f"Error getting leaderboard: {str(e)}")
        return jsonify({"error": f"Failed to get leaderboard: {str(e)}"}), 500

@app.route('/generate-illustration', methods=['POST'])
def generate_illustration():
    """Generate AI illustration for a word"""
    try:
        data = request.get_json()
        word = data.get('word')
        language = data.get('language')
        
        if not word or not language:
            return jsonify({"error": "Both 'word' and 'language' are required"}), 400
        
        word_normalized = word.strip().lower()
        
        # Check if illustration already exists
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT scene_description, image_data, content_type, created_at
            FROM illustrations 
            WHERE word = %s AND language = %s
        """, (word_normalized, language))
        
        existing = cur.fetchone()
        if existing:
            cur.close()
            conn.close()
            return jsonify({
                "word": word_normalized,
                "language": language,
                "scene_description": existing['scene_description'],
                "image_data": base64.b64encode(existing['image_data']).decode('utf-8'),
                "content_type": existing['content_type'],
                "cached": True,
                "created_at": existing['created_at'].isoformat()
            })
        
        # Get word definition to help with scene generation
        cur.execute("""
            SELECT definition_data
            FROM definitions 
            WHERE word = %s AND learning_language = %s
            LIMIT 1
        """, (word_normalized, language))
        
        definition_row = cur.fetchone()
        definition_context = ""
        if definition_row:
            try:
                definition_data = definition_row['definition_data']
                if isinstance(definition_data, str):
                    definition_data = json.loads(definition_data)
                
                # Extract main definition for context
                if definition_data.get('definitions'):
                    definition_context = definition_data['definitions'][0].get('definition', '')
            except:
                pass
        
        # Generate scene description using OpenAI
        scene_prompt = f"""Create a vivid, detailed scene description that would best illustrate the word "{word}" in {language}. 
        
        Word definition context: {definition_context}
        
        The scene should be:
        - Visual and concrete (avoid abstract concepts)
        - Culturally appropriate and universal
        - Suitable for illustration/artwork
        - Engaging and memorable for language learning
        
        Describe the scene in 2-3 sentences, focusing on visual elements, setting, and actions that clearly represent the meaning of "{word}".
        
        Scene description:"""
        
        app.logger.info(f"Generating scene description for word: {word}")
        
        scene_response = openai.chat.completions.create(
            model="gpt-4",
            messages=[
                {"role": "system", "content": "You are a creative director helping create visual scenes for language learning illustrations."},
                {"role": "user", "content": scene_prompt}
            ],
            max_tokens=200,
            temperature=0.7
        )
        
        scene_description = scene_response.choices[0].message.content.strip()
        app.logger.info(f"Generated scene: {scene_description}")
        
        # Generate image using DALL-E
        image_prompt = f"Create a clear, educational illustration showing: {scene_description}. Style: clean, colorful, suitable for language learning, no text in image."
        
        app.logger.info(f"Generating image for: {word}")
        
        image_response = openai.images.generate(
            model="dall-e-3",
            prompt=image_prompt,
            size="1024x1024",
            quality="standard",
            n=1,
            response_format="b64_json"
        )
        
        image_data = base64.b64decode(image_response.data[0].b64_json)
        content_type = "image/png"
        
        # Store in database
        cur.execute("""
            INSERT INTO illustrations (word, language, scene_description, image_data, content_type)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (word, language) 
            DO UPDATE SET 
                scene_description = EXCLUDED.scene_description,
                image_data = EXCLUDED.image_data,
                content_type = EXCLUDED.content_type,
                created_at = CURRENT_TIMESTAMP
        """, (word_normalized, language, scene_description, image_data, content_type))
        
        conn.commit()
        cur.close()
        conn.close()
        
        app.logger.info(f"Successfully generated and cached illustration for: {word}")
        
        return jsonify({
            "word": word_normalized,
            "language": language,
            "scene_description": scene_description,
            "image_data": base64.b64encode(image_data).decode('utf-8'),
            "content_type": content_type,
            "cached": False,
            "created_at": datetime.now().isoformat()
        })
        
    except Exception as e:
        app.logger.error(f"Error generating illustration: {str(e)}")
        return jsonify({"error": f"Failed to generate illustration: {str(e)}"}), 500

@app.route('/illustration', methods=['GET'])
def get_illustration():
    """Get existing AI illustration for a word"""
    try:
        word = request.args.get('word')
        language = request.args.get('lang')
        
        if not word or not language:
            return jsonify({"error": "Both 'word' and 'lang' parameters are required"}), 400
        
        word_normalized = word.strip().lower()
        
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT scene_description, image_data, content_type, created_at
            FROM illustrations 
            WHERE word = %s AND language = %s
        """, (word_normalized, language))
        
        result = cur.fetchone()
        cur.close()
        conn.close()
        
        if not result:
            return jsonify({"error": "Illustration not found"}), 404
        
        return jsonify({
            "word": word_normalized,
            "language": language,
            "scene_description": result['scene_description'],
            "image_data": base64.b64encode(result['image_data']).decode('utf-8'),
            "content_type": result['content_type'],
            "created_at": result['created_at'].isoformat()
        })
        
    except Exception as e:
        app.logger.error(f"Error getting illustration: {str(e)}")
        return jsonify({"error": f"Failed to get illustration: {str(e)}"}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
