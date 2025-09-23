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

from config.config import *
from static.privacy import PRIVACY_POLICY
from static.support import SUPPORT_HTML


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

# JSON Schema for OpenAI structured output with validation (v2)
WORD_DEFINITION_SCHEMA_V2 = {
    "type": "object",
    "properties": {
        "definition": {"type": "string", "description": "Clear definition in native language"},
        "examples": {
            "type": "array",
            "items": {"type": "string"},
            "description": "3 example sentences"
        },
        "validation": {
            "type": "object",
            "properties": {
                "confidence": {"type": "number", "minimum": 0.0, "maximum": 1.0, "description": "Confidence that input is a valid word/phrase (0.0-1.0)"},
                "suggested": {"type": ["string", "null"], "description": "Alternative suggestion if confidence < 0.9, null otherwise"}
            },
            "required": ["confidence", "suggested"]
        }
    },
    "required": ["definition", "examples", "validation"]
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

def build_definition_prompt_v2(word: str, learning_lang: str, native_lang: str) -> str:
    """Build LLM prompt for bilingual definitions with word validation"""
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

    return f"""You are a multilingual dictionary providing definitions from {learning_lang_name} to {native_lang_name}.

IMPORTANT: You must ALWAYS respond with valid JSON in this exact format:
{{
  "definition": "clear definition in {native_lang_name}",
  "examples": ["example 1", "example 2", "example 3"],
  "validation": {{
    "confidence": 0.0,
    "suggested": null
  }}
}}

Validation Rules for "{word}":
- confidence: How confident you are this is a valid {learning_lang_name} word, phrase, or proper noun (0.0-1.0)
  * 1.0 = Definitely valid (dictionary words, common phrases, well-known proper nouns like "iPhone", "New York")
  * 0.9+ = Very likely valid (less common but legitimate words/phrases/names)
  * 0.7-0.9 = Questionable but could be valid (slang, technical terms, uncommon proper nouns)
  * 0.3-0.7 = Likely invalid but might be a typo
  * 0.0-0.3 = Definitely invalid (gibberish, random characters)

- suggested: If confidence < 0.9 AND you can suggest a correction, provide it. Otherwise null.

ACCEPT as valid (confidence ≥ 0.9):
- Dictionary words: "hello", "computer", "beautiful"
- Common phrases: "how are you", "good morning", "thank you very much"
- Well-known proper nouns: "iPhone", "McDonald's", "New York", "Google"
- Brand names: "Coca-Cola", "Microsoft", "Tesla"
- Common abbreviations: "CEO", "USA", "OK"

QUESTION (confidence 0.7-0.9):
- Slang: "gonna", "wanna"
- Technical terms: "API", "blockchain"
- Less common proper nouns: "Fibonacci", "Schrödinger"

SUGGEST CORRECTIONS (confidence < 0.9 with suggestion):
- Clear typos: "helllo" → "hello", "computor" → "computer"
- Common misspellings: "definately" → "definitely"

Word/phrase to define: "{word}"
"""

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
    Uses configurable constants for easy tuning.
    """
    if days_since_start_or_failure < 7:
        return DECAY_RATE_WEEK_1
    elif days_since_start_or_failure < 14:
        return DECAY_RATE_WEEK_2
    elif days_since_start_or_failure < 28:
        return DECAY_RATE_WEEK_3_4
    elif days_since_start_or_failure < 56:
        return DECAY_RATE_WEEK_5_8
    elif days_since_start_or_failure < 112:
        return DECAY_RATE_WEEK_9_PLUS
    else:
        # Continue halving for longer periods
        period = 112
        rate = DECAY_RATE_WEEK_9_PLUS
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
        
        # Check if retention dropped below the configured threshold
        if retention <= RETENTION_THRESHOLD:
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
    app.logger.info("Save word endpoint called")
    try:
        data = request.get_json()
        app.logger.info(f"Request data: {data}")

        if not data or 'word' not in data or 'user_id' not in data:
            return jsonify({"error": "Both 'word' and 'user_id' are required"}), 400
        
        word = data['word'].strip().lower()
        user_id = data['user_id']
        learning_lang = data.get('learning_language', 'en')
        native_lang = data.get('native_language', 'zh')
        metadata = data.get('metadata', {})

        if 'learning_language' not in data or 'native_language' not in data:
            stored_learning_lang, stored_native_lang, _, _ = get_user_preferences(user_id)
            if 'learning_language' not in data:
                learning_lang = stored_learning_lang
            if 'native_language' not in data:
                native_lang = stored_native_lang
        else:
            # Validate provided languages
            if not validate_language(learning_lang):
                return jsonify({"error": f"Unsupported learning language: {learning_lang}"}), 400
            if not validate_language(native_lang):
                return jsonify({"error": f"Unsupported native language: {native_lang}"}), 400
        
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()

        app.logger.info(f"Saving word: {word}, user: {user_id}, learning: {learning_lang}, native: {native_lang}")

        # First try to find existing word
        cur.execute("""
            SELECT id, created_at FROM saved_words
            WHERE user_id = %s AND word = %s AND learning_language = %s AND native_language = %s
        """, (user_id, word, learning_lang, native_lang))

        existing = cur.fetchone()
        if existing:
            # Update existing word
            cur.execute("""
                UPDATE saved_words SET metadata = %s
                WHERE id = %s
                RETURNING id, created_at
            """, (json.dumps(metadata), existing['id']))
            result = cur.fetchone()
        else:
            # Insert new word
            cur.execute("""
                INSERT INTO saved_words (user_id, word, learning_language, native_language, metadata)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id, created_at
            """, (user_id, word, learning_lang, native_lang, json.dumps(metadata)))
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

@app.route('/unsave', methods=['POST'])
def delete_saved_word():
    """Delete a saved word - supports both v1.0.9 (word+language) and v1.0.10 (word_id) formats"""
    app.logger.info(f"UNSAVE ENDPOINT HIT - Method: {request.method}")
    try:
        data = request.get_json()

        if not data or 'user_id' not in data:
            return jsonify({"error": "'user_id' is required"}), 400

        user_id = data['user_id']

        # Validate UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # Check if this is v1.0.10 format (word_id) or v1.0.9 format (word + learning_language)
        if 'word_id' in data:
            # v1.0.10 format: use word_id directly
            word_id = data['word_id']
            try:
                word_id = int(word_id)
            except (ValueError, TypeError):
                return jsonify({"error": "Invalid word_id format. Must be an integer"}), 400

            cur.execute("""
                DELETE FROM saved_words
                WHERE id = %s AND user_id = %s
                RETURNING id, word
            """, (word_id, user_id))

        elif 'word' in data and 'learning_language' in data:
            # v1.0.9 format: lookup by word + learning_language
            word = data['word']
            learning_language = data['learning_language']

            if not validate_language(learning_language):
                return jsonify({"error": f"Unsupported learning language: {learning_language}"}), 400

            cur.execute("""
                DELETE FROM saved_words
                WHERE word = %s AND learning_language = %s AND user_id = %s
                RETURNING id, word
            """, (word, learning_language, user_id))

        else:
            return jsonify({"error": "Either 'word_id' or both 'word' and 'learning_language' are required"}), 400

        deleted = cur.fetchone()
        conn.commit()
        conn.close()

        if deleted:
            return jsonify({
                "success": True,
                "message": f"Word '{deleted['word']}' removed from saved words",
                "deleted_word_id": deleted['id']
            }), 200
        else:
            return jsonify({
                "error": "Word not found in saved words"
            }), 404

    except Exception as e:
        app.logger.error(f"Error deleting saved word: {str(e)}")
        return jsonify({"error": f"Failed to delete saved word: {str(e)}"}), 500

@app.route('/test-unsave', methods=['GET'])
def test_unsave_route():
    """Test route to verify unsave deployment"""
    return jsonify({"message": "Unsave route is deployed", "timestamp": "2025-09-17"})

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

@app.route('/v2/review_next', methods=['GET'])
def get_next_review_word_v2():
    """Get next review word with language information for v1.0.10+ clients"""
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
                sw.native_language,
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
                "word": word['word'],
                "learning_language": word['learning_language'],
                "native_language": word['native_language']
            }],
            "count": 1
        })

    except Exception as e:
        app.logger.error(f"Error getting next review word (v2): {str(e)}")
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

        # Get language preferences from URL parameters or fall back to user preferences
        learning_lang = request.args.get('learning_lang')
        native_lang = request.args.get('native_lang')

        if not learning_lang or not native_lang:
            user_learning_lang, user_native_lang, _, _ = get_user_preferences(user_id)
            learning_lang = learning_lang or user_learning_lang
            native_lang = native_lang or user_native_lang

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

@app.route('/v2/word', methods=['GET'])
def get_word_definition_v2():
    """Get word definition with validation using OpenAI integration (v2)"""
    try:
        user_id = request.args.get('user_id')
        word = request.args.get('w')

        if not word or not user_id:
            return jsonify({"error": "w and user_id parameters are required"}), 400

        word_normalized = word.strip().lower()

        # Get user preferences
        learning_lang, native_lang, _, _ = get_user_preferences(user_id)

        app.logger.info(f"Generating definition with validation for '{word_normalized}'")
        prompt = build_definition_prompt_v2(word_normalized, learning_lang, native_lang)

        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": "You are a multilingual dictionary expert with word validation capabilities. Provide definitions and assess whether the input is a valid word or phrase."
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "word_definition_with_validation",
                    "schema": WORD_DEFINITION_SCHEMA_V2
                }
            },
            temperature=0.3
        )

        definition_data = json.loads(response.choices[0].message.content)

        return jsonify({
            "word": word_normalized,
            "learning_language": learning_lang,
            "native_language": native_lang,
            "definition": definition_data["definition"],
            "examples": definition_data["examples"],
            "validation": definition_data["validation"]
        })

    except Exception as e:
        app.logger.error(f"Error getting definition v2 for word '{word_normalized}': {str(e)}")
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
                sw.native_language,
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
                "native_language": row['native_language'],
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
        
        
        cur.close()
        conn.close()
        
        return jsonify({
            "user_id": user_id,
            "total_words": total_words,
            "due_today": due_today,
            "reviews_today": reviews_today,
            "success_rate_7_days": success_rate
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

@app.route('/test-review-intervals', methods=['GET'])
def test_review_intervals():
    """
    Test endpoint to show review intervals if word is always reviewed at predicted time.
    Shows the gaps between reviews for the first 10 reviews.
    """
    try:
        from datetime import datetime, timedelta
        import math
        
        # Start from today
        created_at = datetime.now()
        review_dates = []
        intervals = []
        
        # Simulate 10 reviews where each is done exactly at the predicted time
        current_date = created_at
        review_history = []
        
        for review_num in range(10):
            # Calculate next review date using the algorithm
            next_review_date = get_next_review_date_new(review_history, created_at)
            
            # Calculate interval in days
            if review_dates:
                interval = (next_review_date - review_dates[-1]).days
            else:
                interval = (next_review_date - created_at).days
            
            intervals.append(interval)
            review_dates.append(next_review_date)
            
            # Add this review to history (assume always successful)
            review_history.append({
                'reviewed_at': next_review_date,
                'response': True  # Always successful review
            })
        
        # Format the response
        review_schedule = []
        for i, (date, interval) in enumerate(zip(review_dates, intervals)):
            review_schedule.append({
                "review_number": i + 1,
                "date": date.strftime('%Y-%m-%d'),
                "days_from_previous": interval,
                "total_days_from_creation": (date - created_at).days
            })
        
        # Also test with some failures
        review_history_with_failures = []
        failure_schedule = []
        failure_intervals = []
        failure_dates = []
        
        for review_num in range(10):
            # Calculate next review date
            next_review_date = get_next_review_date_new(review_history_with_failures, created_at)
            
            # Calculate interval
            if failure_dates:
                interval = (next_review_date - failure_dates[-1]).days
            else:
                interval = (next_review_date - created_at).days
            
            failure_intervals.append(interval)
            failure_dates.append(next_review_date)
            
            # Add review to history - fail every 3rd review
            review_history_with_failures.append({
                'reviewed_at': next_review_date,
                'response': (review_num + 1) % 3 != 0  # Fail on reviews 3, 6, 9
            })
            
            failure_schedule.append({
                "review_number": review_num + 1,
                "date": next_review_date.strftime('%Y-%m-%d'),
                "days_from_previous": interval,
                "total_days_from_creation": (next_review_date - created_at).days,
                "result": "success" if (review_num + 1) % 3 != 0 else "failure"
            })
        
        return jsonify({
            "description": "Review intervals simulation",
            "configuration": {
                "retention_threshold": RETENTION_THRESHOLD,
                "decay_rates": {
                    "week_1": DECAY_RATE_WEEK_1,
                    "week_2": DECAY_RATE_WEEK_2,
                    "week_3_4": DECAY_RATE_WEEK_3_4,
                    "week_5_8": DECAY_RATE_WEEK_5_8,
                    "week_9_plus": DECAY_RATE_WEEK_9_PLUS
                }
            },
            "perfect_reviews": {
                "description": "All reviews done successfully at predicted time",
                "schedule": review_schedule,
                "intervals_summary": {
                    "intervals_in_days": intervals,
                    "average_interval": sum(intervals) / len(intervals) if intervals else 0,
                    "max_interval": max(intervals) if intervals else 0,
                    "min_interval": min(intervals) if intervals else 0
                }
            },
            "reviews_with_failures": {
                "description": "Reviews with failures every 3rd review",
                "schedule": failure_schedule,
                "intervals_summary": {
                    "intervals_in_days": failure_intervals,
                    "average_interval": sum(failure_intervals) / len(failure_intervals) if failure_intervals else 0,
                    "max_interval": max(failure_intervals) if failure_intervals else 0,
                    "min_interval": min(failure_intervals) if failure_intervals else 0
                }
            }
        })
        
    except Exception as e:
        app.logger.error(f"Error testing review intervals: {str(e)}")
        return jsonify({"error": f"Failed to test review intervals: {str(e)}"}), 500

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
        conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
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
            SELECT r.id AS id, r.word_id AS word_id, r.user_id AS user_id, r.next_review_date AS next_review_date, r.reviewed_at AS reviewed_at
            FROM reviews r
            INNER JOIN latest_reviews lr ON 
                r.word_id = lr.word_id AND 
                r.user_id = lr.user_id AND 
                r.reviewed_at = lr.latest_reviewed_at
            ORDER BY r.word_id, r.user_id
        """)
        
        records_to_check = cur.fetchall()
        print(records_to_check)
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

            print("record:")
            print(record)
            
            try:
                # Get word creation date
                cur.execute("""
                    SELECT created_at AS created_at FROM saved_words 
                    WHERE id = %s AND user_id = %s
                """, (word_id, user_id))
                
                word_data = cur.fetchone()
                if not word_data:
                    app.logger.warning(f"Word {word_id} not found for user {user_id}")
                    continue
                
                created_at = word_data['created_at']

                print("created_at")
                
                # Get all review history for this word/user combination
                cur.execute("""
                    SELECT reviewed_at AS reviewed_at, response AS response FROM reviews 
                    WHERE word_id = %s AND user_id = %s 
                    ORDER BY reviewed_at ASC
                """, (word_id, user_id))
                
                review_history = cur.fetchall()
                
                # Convert to format expected by get_next_review_date_new
                review_list = []
                for review in review_history:
                    # Handle as tuple: (reviewed_at, response)
                    reviewed_at = review['reviewed_at']
                    response = review['response']
                    review_list.append({
                        'reviewed_at': reviewed_at,
                        'response': response
                    })
                
                # Calculate correct next_review_date
                calculated_next_review_date = get_next_review_date_new(review_list, created_at)
                
                # Compare with current value (allowing for small time differences)
                current_date = datetime.fromisoformat(current_next_review_date.replace('Z', '+00:00')) if isinstance(current_next_review_date, str) else current_next_review_date
                time_diff = abs((calculated_next_review_date - current_date).total_seconds())
                print("here 0")
                # Consider dates within 1 minute as "correct" (to account for processing time differences)
                if time_diff <= 60:
                    stats['correct_records'] += 1
                    app.logger.info(f"Record {record_id} (word_id={word_id}): CORRECT")
                    print("here 1")
                else:
                    stats['incorrect_records'] += 1
                    print("here 2")
                    # Update the record with correct next_review_date
                    cur.execute("""
                        UPDATE reviews 
                        SET next_review_date = %s 
                        WHERE id = %s
                    """, (calculated_next_review_date, record_id))
                    
                    stats['updated_records'] += 1
                    print("here 3")
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
                    print("here 4")
                    app.logger.info(f"Record {record_id} (word_id={word_id}): UPDATED - was {current_date}, now {calculated_next_review_date} (diff: {time_diff:.1f}s)")
                    print("here 5")
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
    privacy_policy = PRIVACY_POLICY
    # Replace timestamp placeholder
    privacy_policy = privacy_policy.replace('{timestamp}', datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC'))
    
    return Response(privacy_policy, mimetype='text/html')

@app.route('/support', methods=['GET'])
def support_page():
    """Support page with app information and contact details"""
    
    return Response(SUPPORT_HTML, mimetype='text/html')

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


@app.route('/feedback', methods=['POST'])
def submit_feedback():
    """Submit user feedback"""
    try:
        data = request.json
        user_id = data.get('user_id')
        feedback = data.get('feedback')

        # Validate inputs
        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        if not feedback:
            return jsonify({"error": "feedback is required"}), 400

        # Validate feedback length
        if len(feedback) > 500:
            return jsonify({"error": "Feedback must be 500 characters or less"}), 400

        # Validate UUID format
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # Insert feedback
        cur.execute("""
            INSERT INTO user_feedback (user_id, feedback)
            VALUES (%s, %s)
            RETURNING id, created_at
        """, (user_id, feedback))

        result = cur.fetchone()
        feedback_id = result['id']
        created_at = result['created_at']

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({
            "success": True,
            "message": "Thank you for your feedback!",
            "feedback_id": feedback_id,
            "created_at": created_at.isoformat()
        }), 201

    except Exception as e:
        app.logger.error(f"Error submitting feedback: {str(e)}")
        return jsonify({"error": f"Failed to submit feedback: {str(e)}"}), 500

@app.route('/reviews/progress_stats', methods=['GET'])
def get_review_progress_stats():
    """Get review progress statistics for ReviewGoalAchievedView"""
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # Get reviews in the past 24 hours
        cur.execute("""
            SELECT
                COUNT(*) as reviews_today,
                SUM(CASE WHEN response = true THEN 1 ELSE 0 END) as correct_reviews
            FROM reviews
            WHERE user_id = %s
            AND reviewed_at >= NOW() - INTERVAL '24 hours'
        """, (user_id,))

        review_stats = cur.fetchone()
        reviews_today = review_stats['reviews_today'] or 0
        correct_reviews = review_stats['correct_reviews'] or 0
        success_rate_today = (correct_reviews / reviews_today * 100) if reviews_today > 0 else 0

        # Get progression changes (words moving between familiarity levels)
        # This is a simplified version - in reality you'd need to track state changes
        # For now, we'll estimate based on review patterns
        cur.execute("""
            WITH word_reviews AS (
                SELECT
                    sw.word,
                    COUNT(r.id) as total_reviews,
                    SUM(CASE WHEN r.response = true THEN 1 ELSE 0 END) as correct_reviews,
                    MAX(r.reviewed_at) as last_reviewed
                FROM saved_words sw
                LEFT JOIN reviews r ON sw.id = r.word_id
                WHERE sw.user_id = %s
                AND r.reviewed_at >= NOW() - INTERVAL '24 hours'
                GROUP BY sw.word
            )
            SELECT
                COUNT(CASE WHEN total_reviews = 1 AND correct_reviews = 1 THEN 1 END) as acquainted_to_familiar,
                COUNT(CASE WHEN total_reviews >= 2 AND total_reviews < 5 AND correct_reviews = total_reviews THEN 1 END) as familiar_to_remembered,
                COUNT(CASE WHEN total_reviews >= 5 AND correct_reviews = total_reviews THEN 1 END) as remembered_to_unforgettable
            FROM word_reviews
        """, (user_id,))

        progression = cur.fetchone()

        # Get total review count for the user
        cur.execute("""
            SELECT COUNT(*) as total_reviews
            FROM reviews
            WHERE user_id = %s
        """, (user_id,))

        total_reviews_result = cur.fetchone()
        total_reviews = total_reviews_result['total_reviews'] or 0

        cur.close()
        conn.close()

        return jsonify({
            "reviews_today": reviews_today,
            "success_rate_today": round(success_rate_today, 1),
            "acquainted_to_familiar": progression['acquainted_to_familiar'] or 0,
            "familiar_to_remembered": progression['familiar_to_remembered'] or 0,
            "remembered_to_unforgettable": progression['remembered_to_unforgettable'] or 0,
            "total_reviews": total_reviews
        })

    except Exception as e:
        app.logger.error(f"Error getting review progress stats: {str(e)}")
        return jsonify({"error": f"Failed to get review progress stats: {str(e)}"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
