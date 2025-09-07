from flask import Flask, request, jsonify
import os
from dotenv import load_dotenv
import openai
from typing import List, Dict, Any
import json
import psycopg2
from psycopg2.extras import RealDictCursor
import uuid
from datetime import datetime

load_dotenv('.env.secrets')

app = Flask(__name__)

client = openai.OpenAI(
    api_key=os.getenv('OPENAI_API_KEY'),
    base_url=os.getenv('BASE_URL', 'https://api.openai.com/v1/')
)

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')

def get_db_connection():
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)

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
            SELECT definition_data, access_count 
            FROM words 
            WHERE word_lower = %s
        """, (word_lower,))
        
        cached_result = cur.fetchone()
        
        if cached_result:
            # Cache hit - update access stats
            definition_data = cached_result['definition_data']
            access_count = cached_result['access_count']
            
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
        
        # Store in cache
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
        
        # Insert or update the saved word
        cur.execute("""
            INSERT INTO saved_words (user_id, word, metadata, created_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (user_id, word) 
            DO UPDATE SET metadata = EXCLUDED.metadata, created_at = EXCLUDED.created_at
            RETURNING id, created_at
        """, (user_id, word, json.dumps(metadata), datetime.now()))
        
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
        
        if not user_id:
            return jsonify({"error": "Parameter 'user_id' is required"}), 400
        
        # Validate user_id is a valid UUID
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
        
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            SELECT id, word, metadata, created_at
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
                "created_at": word_record['created_at'].isoformat()
            })
        
        return jsonify({
            "user_id": user_id,
            "saved_words": result,
            "count": len(result)
        })
        
    except Exception as e:
        return jsonify({"error": f"Failed to retrieve saved words: {str(e)}"}), 500
    finally:
        if 'conn' in locals():
            conn.close()

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)