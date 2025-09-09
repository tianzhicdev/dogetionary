from flask import Flask, request, jsonify, Response
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

# Simplified spaced repetition using Fibonacci sequence
FIBONACCI_INTERVALS = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144]  # days

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

def calculate_spaced_repetition(reviews_data):
    if not reviews_data:
        return 0, 1, datetime.now() + timedelta(days=1), None
    
    reviews_data.sort(key=lambda r: r['reviewed_at'])
    review_count = len(reviews_data)
    last_reviewed_at = reviews_data[-1]['reviewed_at']
    
    consecutive_correct = 0
    for review in reversed(reviews_data):
        if review['response']:
            consecutive_correct += 1
        else:
            break
    
    if reviews_data[-1]['response']:
        interval_index = min(consecutive_correct, len(FIBONACCI_INTERVALS) - 1)
        interval_days = FIBONACCI_INTERVALS[interval_index]
    else:
        interval_days = 1
    
    next_review_date = last_reviewed_at + timedelta(days=interval_days)
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
        
        # SQL query to find word with earliest calculated next review date
        cur.execute("""
            WITH word_reviews AS (
                SELECT 
                    sw.id,
                    sw.word,
                    sw.learning_language,
                    sw.metadata,
                    sw.created_at,
                    COUNT(r.id) as review_count,
                    MAX(r.reviewed_at) as last_reviewed_at,
                    -- Count consecutive correct responses from the end
                    COALESCE((
                        SELECT COUNT(*)
                        FROM reviews r2 
                        WHERE r2.user_id = sw.user_id 
                        AND r2.word_id = sw.id 
                        AND r2.reviewed_at >= COALESCE((
                            SELECT MAX(r3.reviewed_at)
                            FROM reviews r3
                            WHERE r3.user_id = sw.user_id 
                            AND r3.word_id = sw.id 
                            AND r3.response = false
                        ), '1900-01-01'::timestamp)
                        AND r2.response = true
                    ), 0) as consecutive_correct,
                    -- Get last response
                    (
                        SELECT r4.response
                        FROM reviews r4
                        WHERE r4.user_id = sw.user_id 
                        AND r4.word_id = sw.id
                        ORDER BY r4.reviewed_at DESC
                        LIMIT 1
                    ) as last_response
                FROM saved_words sw
                LEFT JOIN reviews r ON r.user_id = sw.user_id AND r.word_id = sw.id
                WHERE sw.user_id = %s
                GROUP BY sw.id, sw.word, sw.learning_language, sw.metadata, sw.created_at, sw.user_id
            ),
            word_intervals AS (
                SELECT *,
                    CASE 
                        WHEN review_count = 0 THEN 1
                        WHEN last_response = false THEN 1
                        ELSE (ARRAY[1,1,2,3,5,8,13,21,34,55,89,144])[LEAST(consecutive_correct + 1, 12)]
                    END as interval_days,
                    CASE
                        WHEN last_reviewed_at IS NULL THEN created_at + INTERVAL '1 day'
                        WHEN last_response = false THEN last_reviewed_at + INTERVAL '1 day'
                        ELSE last_reviewed_at + (ARRAY[1,1,2,3,5,8,13,21,34,55,89,144])[LEAST(consecutive_correct + 1, 12)] * INTERVAL '1 day'
                    END as next_review_date
                FROM word_reviews
            )
            SELECT 
                id, word, learning_language, metadata, created_at,
                review_count, interval_days, next_review_date, last_reviewed_at
            FROM word_intervals
            ORDER BY next_review_date ASC
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
                "metadata": word['metadata'],
                "created_at": word['created_at'].isoformat(),
                "review_count": word['review_count'],
                "ease_factor": 2.5,
                "interval_days": word['interval_days'],
                "next_review_date": word['next_review_date'].isoformat() if word['next_review_date'] else None,
                "last_reviewed_at": word['last_reviewed_at'].isoformat() if word['last_reviewed_at'] else None
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
        
        # SQL query to count total and overdue words
        cur.execute("""
            WITH word_reviews AS (
                SELECT 
                    sw.id,
                    sw.created_at,
                    COUNT(r.id) as review_count,
                    MAX(r.reviewed_at) as last_reviewed_at,
                    -- Count consecutive correct responses from the end
                    COALESCE((
                        SELECT COUNT(*)
                        FROM reviews r2 
                        WHERE r2.user_id = sw.user_id 
                        AND r2.word_id = sw.id 
                        AND r2.reviewed_at >= COALESCE((
                            SELECT MAX(r3.reviewed_at)
                            FROM reviews r3
                            WHERE r3.user_id = sw.user_id 
                            AND r3.word_id = sw.id 
                            AND r3.response = false
                        ), '1900-01-01'::timestamp)
                        AND r2.response = true
                    ), 0) as consecutive_correct,
                    -- Get last response
                    (
                        SELECT r4.response
                        FROM reviews r4
                        WHERE r4.user_id = sw.user_id 
                        AND r4.word_id = sw.id
                        ORDER BY r4.reviewed_at DESC
                        LIMIT 1
                    ) as last_response
                FROM saved_words sw
                LEFT JOIN reviews r ON r.user_id = sw.user_id AND r.word_id = sw.id
                WHERE sw.user_id = %s
                GROUP BY sw.id, sw.created_at, sw.user_id
            ),
            word_intervals AS (
                SELECT *,
                    CASE
                        WHEN last_reviewed_at IS NULL THEN created_at + INTERVAL '1 day'
                        WHEN last_response = false THEN last_reviewed_at + INTERVAL '1 day'
                        ELSE last_reviewed_at + (ARRAY[1,1,2,3,5,8,13,21,34,55,89,144])[LEAST(consecutive_correct + 1, 12)] * INTERVAL '1 day'
                    END as next_review_date
                FROM word_reviews
            )
            SELECT 
                COUNT(*) as total_count,
                COUNT(CASE WHEN next_review_date <= NOW() THEN 1 END) as overdue_count
            FROM word_intervals
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
        
        cur.execute("""
            INSERT INTO reviews (user_id, word_id, response)
            VALUES (%s, %s, %s)
        """, (user_id, word_id, response))
        
        review_count, interval_days, next_review_date, last_reviewed_at = get_word_review_data(user_id, word_id)
        
        conn.commit()
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
        
        # Get all saved words
        cur.execute("""
            SELECT id, word, learning_language, metadata, created_at
            FROM saved_words 
            WHERE user_id = %s
            ORDER BY created_at DESC
        """, (user_id,))
        
        rows = cur.fetchall()
        saved_words = []
        
        for row in rows:
            # Calculate review data for each word
            review_count, interval_days, next_review_date, last_reviewed_at = get_word_review_data(user_id, row['id'])
            
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
                "ease_factor": 2.5,  # Hardcoded as requested
                "interval_days": interval_days,
                "next_review_date": next_review_date.isoformat() if next_review_date else None,
                "last_reviewed_at": last_reviewed_at.isoformat() if last_reviewed_at else None
            })
        
        # Sort by next_review_date if due_only is requested
        if due_only:
            saved_words.sort(key=lambda w: w['next_review_date'] or '9999-12-31')
        
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

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
