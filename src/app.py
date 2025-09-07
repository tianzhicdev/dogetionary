from flask import Flask, request, jsonify
import os
from dotenv import load_dotenv
import openai
from typing import List, Dict, Any
import json
import psycopg2
from psycopg2.extras import RealDictCursor
import uuid
from datetime import datetime, timedelta
import base64
import io
import math

load_dotenv('.env.secrets')

app = Flask(__name__)

client = openai.OpenAI(
    api_key=os.getenv('OPENAI_API_KEY'),
    base_url=os.getenv('BASE_URL', 'https://api.openai.com/v1/')
)

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')

def get_db_connection():
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)

def generate_audio_for_word(word: str) -> bytes:
    """Generate TTS audio for a word using OpenAI API and return audio bytes"""
    try:
        app.logger.info(f"Generating TTS audio for word: {word}")
        
        with client.audio.speech.with_streaming_response.create(
            model="gpt-4o-mini-tts",
            voice="alloy",
            input=word,
            response_format="mp3"
        ) as response:
            # Read the streaming response into memory
            audio_data = io.BytesIO()
            for chunk in response.iter_bytes():
                audio_data.write(chunk)
            
            audio_bytes = audio_data.getvalue()
            app.logger.info(f"Generated {len(audio_bytes)} bytes of audio for word: {word}")
            return audio_bytes
            
    except Exception as e:
        app.logger.error(f"Failed to generate audio for word '{word}': {str(e)}")
        raise

WORD_DEFINITION_SCHEMA = {
    "type": "object",
    "properties": {
        "word": {"type": "string"},
        "phonetic": {"type": "string"},
        "definitions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "type": {"type": "string"},
                    "definition": {"type": "string"},
                    "example": {"type": "string"}
                },
                "required": ["type", "definition", "example"]
            }
        }
    },
    "required": ["word", "phonetic", "definitions"]
}

@app.route('/word', methods=['GET'])
def get_word_definition():
    word = request.args.get('w')
    if not word:
        return jsonify({"error": "Parameter 'w' is required"}), 400
    
    word_normalized = word.strip()
    word_lower = word_normalized.lower()
    
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Check cache first
        cur.execute("""
            SELECT definition_data, access_count, audio_data, audio_content_type, audio_generated_at
            FROM words 
            WHERE word_lower = %s
        """, (word_lower,))
        
        cached_result = cur.fetchone()
        
        if cached_result:
            # Cache hit - update access stats
            definition_data = cached_result['definition_data']
            access_count = cached_result['access_count']
            audio_data = cached_result['audio_data']
            audio_content_type = cached_result['audio_content_type']
            audio_generated_at = cached_result['audio_generated_at']
            
            cur.execute("""
                UPDATE words 
                SET access_count = %s, last_accessed = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
                WHERE word_lower = %s
            """, (access_count + 1, word_lower))
            
            conn.commit()
            
            app.logger.info(f"Cache HIT for word: {word_normalized} (access count: {access_count + 1})")
            
            # Add cache metadata to response
            definition_data['_cache_info'] = {
                'cached': True,
                'access_count': access_count + 1
            }
            
            # Add audio data if available
            if audio_data:
                definition_data['audio'] = {
                    'data': base64.b64encode(audio_data).decode('utf-8'),
                    'content_type': audio_content_type,
                    'generated_at': audio_generated_at.isoformat() if audio_generated_at else None
                }
                app.logger.info(f"Returning cached audio data for word: {word_normalized}")
            else:
                # Generate audio if not cached
                try:
                    audio_bytes = generate_audio_for_word(word_normalized)
                    cur.execute("""
                        UPDATE words 
                        SET audio_data = %s, audio_content_type = %s, audio_generated_at = CURRENT_TIMESTAMP
                        WHERE word_lower = %s
                    """, (audio_bytes, 'audio/mpeg', word_lower))
                    conn.commit()
                    
                    definition_data['audio'] = {
                        'data': base64.b64encode(audio_bytes).decode('utf-8'),
                        'content_type': 'audio/mpeg',
                        'generated_at': datetime.now().isoformat()
                    }
                    app.logger.info(f"Generated and cached new audio for word: {word_normalized}")
                except Exception as e:
                    app.logger.error(f"Failed to generate audio for cached word '{word_normalized}': {str(e)}")
                    # Continue without audio
            
            return jsonify(definition_data)
        
        # Cache miss - call LLM
        app.logger.info(f"Cache MISS for word: {word_normalized} - calling LLM")
        
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": "You are a dictionary expert. Provide comprehensive definitions for words including different parts of speech, phonetic spelling, and example sentences."
                },
                {
                    "role": "user",
                    "content": f"Define the word '{word_normalized}'. Include phonetic spelling, definitions for different parts of speech (noun, verb, adjective, etc.), and provide example sentences for each definition."
                }
            ],
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "word_definition",
                    "schema": WORD_DEFINITION_SCHEMA
                }
            },
            temperature=0.3
        )
        
        definition_data = json.loads(response.choices[0].message.content)
        
        # Generate audio for the word
        audio_bytes = None
        try:
            audio_bytes = generate_audio_for_word(word_normalized)
            app.logger.info(f"Generated audio for new word: {word_normalized}")
        except Exception as e:
            app.logger.error(f"Failed to generate audio for new word '{word_normalized}': {str(e)}")
            # Continue without audio
        
        # Store in cache with audio
        if audio_bytes:
            cur.execute("""
                INSERT INTO words (word, word_lower, definition_data, audio_data, audio_content_type, audio_generated_at, created_at, updated_at, access_count, last_accessed)
                VALUES (%s, %s, %s, %s, %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP)
                ON CONFLICT (word) 
                DO UPDATE SET 
                    definition_data = EXCLUDED.definition_data,
                    audio_data = EXCLUDED.audio_data,
                    audio_content_type = EXCLUDED.audio_content_type,
                    audio_generated_at = EXCLUDED.audio_generated_at,
                    updated_at = CURRENT_TIMESTAMP,
                    access_count = words.access_count + 1,
                    last_accessed = CURRENT_TIMESTAMP
            """, (word_normalized, word_lower, json.dumps(definition_data), audio_bytes, 'audio/mpeg'))
        else:
            cur.execute("""
                INSERT INTO words (word, word_lower, definition_data, created_at, updated_at, access_count, last_accessed)
                VALUES (%s, %s, %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1, CURRENT_TIMESTAMP)
                ON CONFLICT (word) 
                DO UPDATE SET 
                    definition_data = EXCLUDED.definition_data,
                    updated_at = CURRENT_TIMESTAMP,
                    access_count = words.access_count + 1,
                    last_accessed = CURRENT_TIMESTAMP
            """, (word_normalized, word_lower, json.dumps(definition_data)))
        
        conn.commit()
        
        # Add cache metadata to response
        definition_data['_cache_info'] = {
            'cached': False,
            'access_count': 1
        }
        
        # Add audio data to response if available
        if audio_bytes:
            definition_data['audio'] = {
                'data': base64.b64encode(audio_bytes).decode('utf-8'),
                'content_type': 'audio/mpeg',
                'generated_at': datetime.now().isoformat()
            }
        
        return jsonify(definition_data)
        
    except Exception as e:
        app.logger.error(f"Error getting definition for word '{word_normalized}': {str(e)}")
        return jsonify({"error": f"Failed to get definition: {str(e)}"}), 500
    finally:
        if 'conn' in locals():
            conn.close()

@app.route('/save', methods=['POST'])
def save_word():
    try:
        data = request.get_json()
        
        if not data or 'word' not in data or 'user_id' not in data:
            return jsonify({"error": "Both 'word' and 'user_id' are required"}), 400
        
        word = data['word'].strip()
        user_id = data['user_id']
        metadata = data.get('metadata', {})
        
        # Validate user_id is a valid UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        if not word:
            return jsonify({"error": "Word cannot be empty"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Insert or update the saved word with initial review settings
        cur.execute("""
            INSERT INTO saved_words (user_id, word, metadata, created_at, review_count, ease_factor, interval_days, next_review_date)
            VALUES (%s, %s, %s, %s, 0, 2.5, 1, %s)
            ON CONFLICT (user_id, word) 
            DO UPDATE SET metadata = EXCLUDED.metadata, created_at = EXCLUDED.created_at
            RETURNING id, created_at
        """, (user_id, word, json.dumps(metadata), datetime.now(), datetime.now().date() + timedelta(days=1)))
        
        result = cur.fetchone()
        conn.commit()
        
        return jsonify({
            "message": "Word saved successfully",
            "id": result['id'],
            "word": word,
            "user_id": user_id,
            "created_at": result['created_at'].isoformat()
        }), 201
        
    except Exception as e:
        return jsonify({"error": f"Failed to save word: {str(e)}"}), 500
    finally:
        if 'conn' in locals():
            conn.close()

@app.route('/saved_words', methods=['GET'])
def get_saved_words():
    try:
        user_id = request.args.get('user_id')
        due_only = request.args.get('due_only', 'false').lower() == 'true'
        
        if not user_id:
            return jsonify({"error": "Parameter 'user_id' is required"}), 400
        
        # Validate user_id is a valid UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        if due_only:
            # Get only words due for review (next_review_date <= today)
            cur.execute("""
                SELECT id, word, metadata, created_at, review_count, ease_factor, interval_days, next_review_date, last_reviewed_at
                FROM saved_words
                WHERE user_id = %s AND next_review_date <= %s
                ORDER BY next_review_date ASC, created_at DESC
            """, (user_id, datetime.now().date()))
        else:
            # Get all saved words
            cur.execute("""
                SELECT id, word, metadata, created_at, review_count, ease_factor, interval_days, next_review_date, last_reviewed_at
                FROM saved_words
                WHERE user_id = %s
                ORDER BY created_at DESC
            """, (user_id,))
        
        words = cur.fetchall()
        
        # Convert to list of dictionaries and format dates
        result = []
        for word_record in words:
            result.append({
                "id": word_record['id'],
                "word": word_record['word'],
                "metadata": word_record['metadata'],
                "created_at": word_record['created_at'].isoformat(),
                "review_count": word_record['review_count'],
                "ease_factor": float(word_record['ease_factor']) if word_record['ease_factor'] else 2.5,
                "interval_days": word_record['interval_days'],
                "next_review_date": word_record['next_review_date'].isoformat() if word_record['next_review_date'] else None,
                "last_reviewed_at": word_record['last_reviewed_at'].isoformat() if word_record['last_reviewed_at'] else None
            })
        
        return jsonify({
            "user_id": user_id,
            "saved_words": result,
            "count": len(result),
            "due_only": due_only
        })
        
    except Exception as e:
        return jsonify({"error": f"Failed to retrieve saved words: {str(e)}"}), 500
    finally:
        if 'conn' in locals():
            conn.close()

def calculate_sm2_interval(review_count, ease_factor, response):
    """
    Calculate next review interval using SuperMemo SM-2 algorithm
    
    Args:
        review_count: Number of successful reviews (consecutive correct answers)
        ease_factor: Current ease factor (starts at 2.5)
        response: True if user knew the word, False otherwise
    
    Returns:
        tuple: (new_review_count, new_ease_factor, interval_days)
    """
    if response:
        # User knew the word - increment review count
        new_review_count = review_count + 1
        new_ease_factor = ease_factor
        
        if new_review_count == 1:
            interval_days = 1
        elif new_review_count == 2:
            interval_days = 6
        else:
            interval_days = int(math.ceil(review_count * ease_factor))
            # Cap maximum interval at 365 days
            interval_days = min(interval_days, 365)
    else:
        # User didn't know the word - reset review count
        new_review_count = 0
        new_ease_factor = max(1.3, ease_factor - 0.2)  # Decrease ease factor, minimum 1.3
        interval_days = 1
    
    return new_review_count, new_ease_factor, interval_days

def calculate_start_anyway_interval(last_reviewed_at, created_at):
    """
    Calculate interval using "start anyway" algorithm:
    new_interval = (current_date - last_review_date_or_created_date) * 2.5
    """
    current_date = datetime.now().date()
    
    # Use last reviewed date if available, otherwise use created date
    if last_reviewed_at:
        reference_date = last_reviewed_at.date() if isinstance(last_reviewed_at, datetime) else last_reviewed_at
    else:
        reference_date = created_at.date() if isinstance(created_at, datetime) else created_at
    
    # Calculate days since reference date
    days_since = (current_date - reference_date).days
    
    # Apply the 2.5x multiplier, with minimum 1 day
    new_interval = max(1, int(days_since * 2.5))
    
    # Cap maximum interval at 365 days
    return min(new_interval, 365)

@app.route('/reviews/submit', methods=['POST'])
def submit_review():
    try:
        data = request.get_json()
        
        if not data or 'user_id' not in data or 'word_id' not in data or 'response' not in data:
            return jsonify({"error": "user_id, word_id, and response are required"}), 400
        
        user_id = data['user_id']
        word_id = data['word_id']
        response = data['response']  # Boolean: True for "yes", False for "no"
        response_time_ms = data.get('response_time_ms')
        review_type = data.get('review_type', 'regular')  # 'regular' or 'start_anyway'
        
        # Validate user_id is a valid UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        # Validate response is boolean
        if not isinstance(response, bool):
            return jsonify({"error": "response must be a boolean"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get current review state for the word (including created_at and last_reviewed_at)
        cur.execute("""
            SELECT id, review_count, ease_factor, interval_days, created_at, last_reviewed_at
            FROM saved_words
            WHERE user_id = %s AND id = %s
        """, (user_id, word_id))
        
        word_record = cur.fetchone()
        if not word_record:
            return jsonify({"error": "Word not found for this user"}), 404
        
        current_review_count = word_record['review_count'] or 0
        current_ease_factor = float(word_record['ease_factor']) if word_record['ease_factor'] else 2.5
        
        if review_type == 'start_anyway' and response:
            # Use alternative algorithm for successful "start anyway" reviews
            interval_days = calculate_start_anyway_interval(
                word_record['last_reviewed_at'], 
                word_record['created_at']
            )
            new_review_count = current_review_count + 1
            new_ease_factor = current_ease_factor  # Keep ease factor unchanged
            
            app.logger.info(f"Start anyway review - Word ID: {word_id}, Interval: {interval_days} days")
        elif review_type == 'start_anyway' and not response:
            # For wrong answers in "start anyway", reset to 1 day (same as SM-2)
            new_review_count = 0
            new_ease_factor = max(1.3, current_ease_factor - 0.2)
            interval_days = 1
        else:
            # Use regular SM-2 algorithm
            new_review_count, new_ease_factor, interval_days = calculate_sm2_interval(
                current_review_count, current_ease_factor, response
            )
        
        # Calculate next review date
        next_review_date = datetime.now().date() + timedelta(days=interval_days)
        
        # Insert review record
        cur.execute("""
            INSERT INTO reviews (user_id, word_id, response, response_time_ms, reviewed_at)
            VALUES (%s, %s, %s, %s, %s)
        """, (user_id, word_id, response, response_time_ms, datetime.now()))
        
        # Update saved word with new review state
        cur.execute("""
            UPDATE saved_words 
            SET review_count = %s, 
                ease_factor = %s, 
                interval_days = %s, 
                next_review_date = %s, 
                last_reviewed_at = %s
            WHERE user_id = %s AND id = %s
        """, (new_review_count, new_ease_factor, interval_days, next_review_date, datetime.now(), user_id, word_id))
        
        conn.commit()
        
        app.logger.info(f"Review submitted - User: {user_id}, Word ID: {word_id}, Response: {response}, Type: {review_type}, Next review: {next_review_date}")
        
        return jsonify({
            "success": True,
            "word_id": word_id,
            "response": response,
            "review_type": review_type,
            "review_count": new_review_count,
            "ease_factor": new_ease_factor,
            "interval_days": interval_days,
            "next_review_date": next_review_date.isoformat()
        }), 200
        
    except Exception as e:
        app.logger.error(f"Error submitting review: {str(e)}")
        return jsonify({"error": f"Failed to submit review: {str(e)}"}), 500
    finally:
        if 'conn' in locals():
            conn.close()

@app.route('/reviews/stats', methods=['GET'])
def get_review_stats():
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "Parameter 'user_id' is required"}), 400
        
        # Validate user_id is a valid UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get total saved words count
        cur.execute("""
            SELECT COUNT(*) as total_words
            FROM saved_words
            WHERE user_id = %s
        """, (user_id,))
        total_words = cur.fetchone()['total_words']
        
        # Get words due today
        cur.execute("""
            SELECT COUNT(*) as due_today
            FROM saved_words
            WHERE user_id = %s AND next_review_date <= %s
        """, (user_id, datetime.now().date()))
        due_today = cur.fetchone()['due_today']
        
        # Get reviews completed today
        cur.execute("""
            SELECT COUNT(*) as reviews_today
            FROM reviews
            WHERE user_id = %s AND DATE(reviewed_at) = %s
        """, (user_id, datetime.now().date()))
        reviews_today = cur.fetchone()['reviews_today']
        
        # Get success rate for last 7 days
        week_ago = datetime.now().date() - timedelta(days=7)
        cur.execute("""
            SELECT 
                COUNT(*) as total_reviews,
                SUM(CASE WHEN response = true THEN 1 ELSE 0 END) as successful_reviews
            FROM reviews
            WHERE user_id = %s AND DATE(reviewed_at) >= %s
        """, (user_id, week_ago))
        
        week_stats = cur.fetchone()
        if week_stats['total_reviews'] > 0:
            success_rate_7_days = week_stats['successful_reviews'] / week_stats['total_reviews']
        else:
            success_rate_7_days = 0.0
        
        # Calculate streak (consecutive days with reviews)
        # This is a simple implementation - could be enhanced
        cur.execute("""
            SELECT DISTINCT DATE(reviewed_at) as review_date
            FROM reviews
            WHERE user_id = %s
            ORDER BY review_date DESC
            LIMIT 30
        """, (user_id,))
        
        review_dates = [row['review_date'] for row in cur.fetchall()]
        
        # Calculate consecutive days from today backwards
        streak_days = 0
        current_date = datetime.now().date()
        
        for review_date in review_dates:
            if review_date == current_date - timedelta(days=streak_days):
                streak_days += 1
            else:
                break
        
        return jsonify({
            "user_id": user_id,
            "total_words": total_words,
            "due_today": due_today,
            "reviews_today": reviews_today,
            "success_rate_7_days": round(success_rate_7_days, 3),
            "streak_days": streak_days
        })
        
    except Exception as e:
        app.logger.error(f"Error getting review stats: {str(e)}")
        return jsonify({"error": f"Failed to get review stats: {str(e)}"}), 500
    finally:
        if 'conn' in locals():
            conn.close()

@app.route('/saved_words/next_due', methods=['GET'])
def get_next_due_words():
    try:
        user_id = request.args.get('user_id')
        limit = request.args.get('limit', '10')
        
        if not user_id:
            return jsonify({"error": "Parameter 'user_id' is required"}), 400
        
        # Validate user_id is a valid UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        # Validate limit
        try:
            limit = int(limit)
            if limit <= 0 or limit > 50:  # Reasonable bounds
                limit = 10
        except ValueError:
            limit = 10
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get words ordered by next_review_date (soonest first)
        cur.execute("""
            SELECT id, word, metadata, created_at, review_count, ease_factor, interval_days, next_review_date, last_reviewed_at
            FROM saved_words
            WHERE user_id = %s
            ORDER BY next_review_date ASC, created_at ASC
            LIMIT %s
        """, (user_id, limit))
        
        words = cur.fetchall()
        
        # Convert to list of dictionaries and format dates
        result = []
        for word_record in words:
            result.append({
                "id": word_record['id'],
                "word": word_record['word'],
                "metadata": word_record['metadata'],
                "created_at": word_record['created_at'].isoformat(),
                "review_count": word_record['review_count'],
                "ease_factor": float(word_record['ease_factor']) if word_record['ease_factor'] else 2.5,
                "interval_days": word_record['interval_days'],
                "next_review_date": word_record['next_review_date'].isoformat() if word_record['next_review_date'] else None,
                "last_reviewed_at": word_record['last_reviewed_at'].isoformat() if word_record['last_reviewed_at'] else None
            })
        
        return jsonify({
            "user_id": user_id,
            "saved_words": result,
            "count": len(result),
            "limit": limit
        })
        
    except Exception as e:
        app.logger.error(f"Error getting next due words: {str(e)}")
        return jsonify({"error": f"Failed to get next due words: {str(e)}"}), 500
    finally:
        if 'conn' in locals():
            conn.close()

@app.route('/words/<int:word_id>/details', methods=['GET'])
def get_word_details(word_id):
    try:
        user_id = request.args.get('user_id')
        
        if not user_id:
            return jsonify({"error": "Parameter 'user_id' is required"}), 400
        
        # Validate user_id is a valid UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        # Get word details
        cur.execute("""
            SELECT id, word, metadata, created_at, review_count, ease_factor, interval_days, next_review_date, last_reviewed_at
            FROM saved_words
            WHERE id = %s AND user_id = %s
        """, (word_id, user_id))
        
        word_record = cur.fetchone()
        if not word_record:
            return jsonify({"error": "Word not found for this user"}), 404
        
        # Get review history
        cur.execute("""
            SELECT response, response_time_ms, reviewed_at
            FROM reviews
            WHERE word_id = %s AND user_id = %s
            ORDER BY reviewed_at ASC
        """, (word_id, user_id))
        
        reviews = cur.fetchall()
        
        # Format response
        word_details = {
            "id": word_record['id'],
            "word": word_record['word'],
            "metadata": word_record['metadata'],
            "created_at": word_record['created_at'].isoformat(),
            "review_count": word_record['review_count'],
            "ease_factor": float(word_record['ease_factor']) if word_record['ease_factor'] else 2.5,
            "interval_days": word_record['interval_days'],
            "next_review_date": word_record['next_review_date'].isoformat() if word_record['next_review_date'] else None,
            "last_reviewed_at": word_record['last_reviewed_at'].isoformat() if word_record['last_reviewed_at'] else None,
            "review_history": [
                {
                    "response": review['response'],
                    "response_time_ms": review['response_time_ms'],
                    "reviewed_at": review['reviewed_at'].isoformat()
                }
                for review in reviews
            ]
        }
        
        return jsonify(word_details)
        
    except Exception as e:
        app.logger.error(f"Error getting word details for ID {word_id}: {str(e)}")
        return jsonify({"error": f"Failed to get word details: {str(e)}"}), 500
    finally:
        if 'conn' in locals():
            conn.close()

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)