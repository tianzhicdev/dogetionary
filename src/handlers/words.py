from flask import Flask, request, jsonify, Response, g
import os
from dotenv import load_dotenv
from typing import Optional, Dict, Any
import json
from utils.llm import llm_completion
import openai
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
from utils.database import validate_language, get_db_connection, db_fetch_one
from services.user_service import generate_user_profile, get_user_preferences
from utils.timezone_utils import get_user_timezone

# Get logger
import logging
logger = logging.getLogger(__name__)

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')

# Audio generation queue for async processing
audio_generation_queue = queue.Queue()
audio_generation_status = {}


def get_next_review_word_v2():
    """
    Get next review word with language information for v1.0.10+ clients.

    Returns ONLY overdue words (next_review_date <= NOW, not reviewed in past 24h).
    When all overdue words are reviewed, returns empty response = "today's tasks complete".
    """
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        # Get user's timezone for correct "today" calculation
        user_timezone = get_user_timezone(user_id)

        # Find word with earliest next review date (due now or overdue)
        # FIXED: Use user's timezone instead of UTC for "due" check
        word = db_fetch_one("""
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
            -- Exclude known words from practice
            AND (sw.is_known IS NULL OR sw.is_known = FALSE)
            -- Exclude words reviewed in the past 24 hours
            AND (latest_review.last_reviewed_at IS NULL OR latest_review.last_reviewed_at <= NOW() - INTERVAL '24 hours')
            -- ONLY include words that are actually DUE (overdue or due now)
            -- FIXED: Use user timezone instead of UTC
            AND COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= (NOW() AT TIME ZONE %s)::date
            ORDER BY COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') ASC
            LIMIT 1
        """, (user_id, user_timezone))

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
        logger.error(f"Error getting next review word (v2): {str(e)}")
        return jsonify({"error": f"Failed to get next review word: {str(e)}"}), 500

def audio_generation_worker():
    """Background worker for processing audio generation - simplified"""
    while True:
        try:
            task = audio_generation_queue.get(timeout=1)
            if task is None:
                break
                
            text, language = task
            
            try:
                logger.info(f"Generating audio for: '{text}' in {language}")
                audio_data = generate_audio_for_text(text)
                store_audio(text, language, audio_data)
                logger.info(f"Successfully generated audio for: '{text}'")
            except Exception as e:
                logger.error(f"Failed to generate audio for '{text}': {str(e)}")
                
            audio_generation_queue.task_done()
            
        except queue.Empty:
            continue
        except Exception as e:
            logger.error(f"Error in audio generation worker: {str(e)}")

# Old schemas and helper functions removed - now using centralized services/definition_service.py

# get_cached_definition removed - caching now handled by centralized services/definition_service.py

def get_word_review_data(user_id: str, word_id: int):
    """Get review history data for a specific word using real spaced repetition algorithm"""
    from services.spaced_repetition_service import get_next_review_date_new

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # Get word creation date
        cur.execute("""
            SELECT created_at FROM saved_words
            WHERE id = %s AND user_id = %s
        """, (word_id, user_id))

        word_row = cur.fetchone()
        if not word_row:
            cur.close()
            conn.close()
            return 0, 1, datetime.now() + timedelta(days=1), None

        created_at = word_row['created_at']

        # Get review history
        cur.execute("""
            SELECT response, reviewed_at FROM reviews
            WHERE user_id = %s AND word_id = %s
            ORDER BY reviewed_at ASC
        """, (user_id, word_id))

        reviews = [{"response": row['response'], "reviewed_at": row['reviewed_at']} for row in cur.fetchall()]
        cur.close()
        conn.close()

        # Calculate next review date using the real algorithm
        next_review_date = get_next_review_date_new(reviews, created_at)

        # Calculate other return values
        review_count = len(reviews)
        last_reviewed_at = reviews[-1]['reviewed_at'] if reviews else None

        if last_reviewed_at:
            interval_days = (next_review_date - last_reviewed_at).days
        else:
            interval_days = (next_review_date - created_at).days

        return review_count, interval_days, next_review_date, last_reviewed_at

    except Exception as e:
        logger.error(f"Error getting review data: {str(e)}")
        return 0, 1, datetime.now() + timedelta(days=1), None


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
        logger.error(f"Error checking audio existence: {str(e)}")
        return False

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


# Old get_word_definition() removed - use get_word_definition_v4() instead

def get_word_definition_v4():
    """
    V4 word definition with validation, suggestion, and vocabulary learning enhancements.
    Uses centralized definition generation service.

    Returns:
    - valid_word_score: float between 0 and 1 (0.9+ = highly valid)
    - suggestion: alternative word/phrase if score < 0.9
    - definition_data: full V4 definition with learning features (always provided)

    Frontend should prompt user if valid_word_score < 0.9
    """
    try:
        from services.definition_service import generate_definition_with_llm

        user_id = request.args.get('user_id')
        word = request.args.get('w')

        if not word or not user_id:
            return jsonify({"error": "w and user_id parameters are required"}), 400

        word_normalized = word.strip().lower()

        # Get language preferences
        learning_lang = request.args.get('learning_lang')
        native_lang = request.args.get('native_lang')

        if not learning_lang or not native_lang:
            user_learning_lang, user_native_lang, _, _ = get_user_preferences(user_id)
            learning_lang = learning_lang or user_learning_lang
            native_lang = native_lang or user_native_lang

        # Generate or retrieve cached definition using centralized service
        definition_data = generate_definition_with_llm(
            word=word_normalized,
            learning_lang=learning_lang,
            native_lang=native_lang
        )

        if not definition_data:
            return jsonify({"error": "Failed to generate definition"}), 500

        # Extract validation data
        valid_word_score = definition_data.get('valid_word_score', 1.0)
        suggestion = definition_data.get('suggestion')

        logger.info(f"V4: Definition for '{word_normalized}': score={valid_word_score}, suggestion={suggestion}")

        # Auto-save word to user's vocabulary (idempotent)
        try:
            from utils.database import db_execute
            db_execute("""
                INSERT INTO saved_words (user_id, word, learning_language, native_language)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT ON CONSTRAINT saved_words_user_id_word_learning_language_native_language_key
                DO NOTHING
            """, (user_id, word_normalized, learning_lang, native_lang), commit=True)
            logger.info(f"Auto-saved word '{word_normalized}' for user {user_id}")
        except Exception as e:
            # Log but don't fail the request if auto-save fails
            logger.warning(f"Failed to auto-save word '{word_normalized}': {e}")

        # Collect audio references
        audio_refs = collect_audio_references(definition_data, learning_lang)

        if audio_exists(word_normalized, learning_lang):
            audio_refs["word_audio"] = True

        # Queue missing audio
        audio_status = queue_missing_audio(word_normalized, definition_data, learning_lang, audio_refs)

        # Return response with multiple formats for backward compatibility
        return jsonify({
            "word": word_normalized,
            "learning_language": learning_lang,
            "native_language": native_lang,
            "validation": {  # For v2.7.2 iOS clients
                "confidence": valid_word_score,
                "suggested": suggestion
            },
            "valid_word_score": valid_word_score,  # For v2.7.3+ iOS clients
            "suggestion": suggestion,              # For v2.7.3+ iOS clients
            "definition_data": definition_data,
            "audio_references": audio_refs,
            "audio_generation_status": audio_status
        })

    except Exception as e:
        logger.error(f"V4: Error getting definition for word '{word}': {str(e)}")
        return jsonify({"error": f"Failed to get definition: {str(e)}"}), 500


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
        cur = conn.cursor(cursor_factory=RealDictCursor)

        # Get saved words with review statistics (correct/incorrect counts and progress level)
        # Progress level logic:
        # - Level 7: >= 7 correct reviews in past 84 days with no errors
        # - Level 6: >= 6 correct reviews in past 41 days with no errors
        # - Level 5: >= 5 correct reviews in past 22 days with no errors
        # - Level 4: >= 4 correct reviews in past 12 days with no errors
        # - Level 3: >= 3 correct reviews in past 6 days with no errors
        # - Level 2: >= 2 correct reviews in past 3 days with no errors
        # - Level 1: >= 1 correct review
        cur.execute("""
            WITH recent_reviews AS (
                SELECT
                    word_id,
                    COUNT(*) FILTER (WHERE response = TRUE AND reviewed_at >= NOW() - INTERVAL '84 days') as correct_84d,
                    COUNT(*) FILTER (WHERE response = TRUE AND reviewed_at >= NOW() - INTERVAL '41 days') as correct_41d,
                    COUNT(*) FILTER (WHERE response = TRUE AND reviewed_at >= NOW() - INTERVAL '22 days') as correct_22d,
                    COUNT(*) FILTER (WHERE response = TRUE AND reviewed_at >= NOW() - INTERVAL '12 days') as correct_12d,
                    COUNT(*) FILTER (WHERE response = TRUE AND reviewed_at >= NOW() - INTERVAL '6 days') as correct_6d,
                    COUNT(*) FILTER (WHERE response = TRUE AND reviewed_at >= NOW() - INTERVAL '3 days') as correct_3d,
                    COUNT(*) FILTER (WHERE response = FALSE AND reviewed_at >= NOW() - INTERVAL '84 days') as errors_84d,
                    COUNT(*) FILTER (WHERE response = FALSE AND reviewed_at >= NOW() - INTERVAL '41 days') as errors_41d,
                    COUNT(*) FILTER (WHERE response = FALSE AND reviewed_at >= NOW() - INTERVAL '22 days') as errors_22d,
                    COUNT(*) FILTER (WHERE response = FALSE AND reviewed_at >= NOW() - INTERVAL '12 days') as errors_12d,
                    COUNT(*) FILTER (WHERE response = FALSE AND reviewed_at >= NOW() - INTERVAL '6 days') as errors_6d,
                    COUNT(*) FILTER (WHERE response = FALSE AND reviewed_at >= NOW() - INTERVAL '3 days') as errors_3d
                FROM reviews
                GROUP BY word_id
            )
            SELECT
                sw.id,
                sw.word,
                sw.learning_language,
                sw.native_language,
                sw.metadata,
                sw.created_at,
                sw.is_known,
                COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') as next_review_date,
                COALESCE(review_counts.total_reviews, 0) as review_count,
                COALESCE(review_counts.correct_reviews, 0) as correct_reviews,
                COALESCE(review_counts.incorrect_reviews, 0) as incorrect_reviews,
                latest_review.last_reviewed_at,
                tv.is_toefl,
                tv.is_ielts,
                -- Calculate progress level based on recent correct reviews and no errors
                CASE
                    WHEN rr.correct_84d >= 7 AND rr.errors_84d = 0 THEN 7
                    WHEN rr.correct_41d >= 6 AND rr.errors_41d = 0 THEN 6
                    WHEN rr.correct_22d >= 5 AND rr.errors_22d = 0 THEN 5
                    WHEN rr.correct_12d >= 4 AND rr.errors_12d = 0 THEN 4
                    WHEN rr.correct_6d >= 3 AND rr.errors_6d = 0 THEN 3
                    WHEN rr.correct_3d >= 2 AND rr.errors_3d = 0 THEN 2
                    WHEN review_counts.correct_reviews >= 1 THEN 1
                    ELSE 0
                END as word_progress_level
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
                    COUNT(*) as total_reviews,
                    COUNT(*) FILTER (WHERE response = TRUE) as correct_reviews,
                    COUNT(*) FILTER (WHERE response = FALSE) as incorrect_reviews
                FROM reviews
                GROUP BY word_id
            ) review_counts ON sw.id = review_counts.word_id
            LEFT JOIN recent_reviews rr ON sw.id = rr.word_id
            LEFT JOIN test_vocabularies tv ON tv.word = sw.word AND tv.language = sw.learning_language
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
                "correct_reviews": row['correct_reviews'],
                "incorrect_reviews": row['incorrect_reviews'],
                "word_progress_level": row['word_progress_level'],
                "interval_days": int(float(interval_days)) if interval_days else 1,
                "next_review_date": next_review_date.strftime('%Y-%m-%d') if next_review_date else None,
                "last_reviewed_at": last_reviewed_at.strftime('%Y-%m-%d %H:%M:%S') if last_reviewed_at else None,
                "is_toefl": row['is_toefl'],
                "is_ielts": row['is_ielts'],
                "is_known": row['is_known'] or False
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
        logger.error(f"Error getting saved words for user {user_id}: {str(e)}")
        return jsonify({"error": f"Failed to get saved words: {str(e)}"}), 500



def generate_audio_for_text(text: str) -> bytes:
    """Generate TTS audio for text using OpenAI"""
    try:
        client = openai.OpenAI()
        response = client.audio.speech.create(
            model=TTS_MODEL_NAME,
            voice=TTS_VOICE,
            input=text,
            response_format="mp3"
        )

        return response.content

    except Exception as e:
        logger.error(f"Failed to generate audio: {str(e)}")
        raise

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
        logger.error(f"Error storing audio: {str(e)}")
        raise

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
        logger.info(f"Generating audio on-demand for text: '{text}' in {language}")
        
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
            logger.error(f"Failed to generate audio: {str(audio_error)}")
            return jsonify({"error": "Failed to generate audio"}), 500
        
    except Exception as e:
        logger.error(f"Error getting audio: {str(e)}")
        return jsonify({"error": f"Failed to get audio: {str(e)}"}), 500


def get_illustration():
    """Get AI illustration for a word - returns cached if exists, generates if not"""
    try:
        # Support both GET parameters and POST JSON body
        if request.method == 'GET':
            word = request.args.get('word')
            language = request.args.get('lang')
        else:  # POST
            data = request.get_json()
            word = data.get('word') if data else None
            language = data.get('language') if data else None

        if not word or not language:
            if request.method == 'GET':
                return jsonify({"error": "Both 'word' and 'lang' parameters are required"}), 400
            else:
                return jsonify({"error": "Both 'word' and 'language' are required"}), 400

        word_normalized = word.strip().lower()

        # Check if illustration already exists (cache-first)
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

        # No cached illustration found - generate new one
        logger.info(f"No cached illustration found for {word} in {language}, generating new one")

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

        logger.info(f"Generating scene description for word: {word}")

        scene_description = llm_completion(
            messages=[
                {"role": "system", "content": "You are a creative director helping create visual scenes for language learning illustrations."},
                {"role": "user", "content": scene_prompt}
            ],
            model_name=COMPLETION_MODEL_NAME_ADVANCED,
            max_completion_tokens=200
        )

        if not scene_description:
            return jsonify({"error": "Failed to generate scene description"}), 500
        logger.info(f"Generated scene: {scene_description}")

        # Generate image using DALL-E
        image_prompt = f"Create a clear, educational illustration showing: {scene_description}. Style: clean, colorful, suitable for language learning, no text in image."

        logger.info(f"Generating image for: {word}")

        # Create OpenAI client for image generation
        client = openai.OpenAI()
        image_response = client.images.generate(
            model=IMAGE_MODEL_NAME,
            prompt=image_prompt,
            size=IMAGE_MODEL_SIZE,
            quality=IMAGE_MODEL_QUALITY,
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

        logger.info(f"Successfully generated and cached illustration for: {word}")

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
        logger.error(f"Error getting/generating illustration: {str(e)}")
        return jsonify({"error": f"Failed to get/generate illustration: {str(e)}"}), 500



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
        logger.error(f"Error getting word details: {str(e)}")
        return jsonify({"error": f"Failed to get word details: {str(e)}"}), 500


def generate_word_definition():
    """Generate and store a word definition using V4 schema with centralized service

    This endpoint generates word definitions using OpenAI and stores them in the database.
    Perfect for bulk generating definitions for SEO content.

    Expected JSON payload:
    {
        "word": "hello",
        "learning_language": "en",
        "native_language": "zh"
    }

    Returns the generated V4 definition data without audio or images.
    """
    try:
        from services.definition_service import generate_definition_with_llm

        # Get JSON data from request
        data = request.get_json()
        if not data:
            return jsonify({"error": "No JSON data provided"}), 400

        # Validate required fields
        required_fields = ['word', 'learning_language', 'native_language']
        for field in required_fields:
            if field not in data:
                return jsonify({"error": f"Missing required field: {field}"}), 400

        word = data['word'].strip().lower()
        learning_lang = data['learning_language']
        native_lang = data['native_language']

        # Validate languages
        if not validate_language(learning_lang) or not validate_language(native_lang):
            return jsonify({"error": "Invalid language code"}), 400

        # Use centralized service to generate or retrieve definition
        definition_data = generate_definition_with_llm(
            word=word,
            learning_lang=learning_lang,
            native_lang=native_lang
        )

        if not definition_data:
            return jsonify({"error": "Failed to generate definition"}), 500

        logger.info(f"Successfully generated and stored V4 definition for word: {word} ({learning_lang}->{native_lang})")

        return jsonify({
            "message": "Definition generated and stored successfully",
            "word": word,
            "learning_language": learning_lang,
            "native_language": native_lang,
            "definition_data": definition_data
        }), 201

    except Exception as e:
        logger.error(f"Error generating word definition: {str(e)}")
        return jsonify({"error": f"Failed to generate definition: {str(e)}"}), 500


def is_word_saved():
    """Check if a specific word is saved for a user - efficient single-word check

    GET /v3/is-word-saved?user_id=XXX&word=XXX&learning_lang=XX&native_lang=XX

    Returns:
        {
            "is_saved": true/false,
            "saved_word_id": 123 or null
        }
    """
    try:
        user_id = request.args.get('user_id')
        word = request.args.get('word')
        learning_lang = request.args.get('learning_lang')
        native_lang = request.args.get('native_lang')

        if not user_id or not word:
            return jsonify({"error": "user_id and word parameters are required"}), 400

        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400

        word_normalized = word.strip().lower()

        conn = get_db_connection()
        cur = conn.cursor()

        # Build query based on whether language params are provided
        if learning_lang and native_lang:
            cur.execute("""
                SELECT id FROM saved_words
                WHERE user_id = %s
                  AND LOWER(word) = %s
                  AND learning_language = %s
                  AND native_language = %s
                LIMIT 1
            """, (user_id, word_normalized, learning_lang, native_lang))
        else:
            cur.execute("""
                SELECT id FROM saved_words
                WHERE user_id = %s AND LOWER(word) = %s
                LIMIT 1
            """, (user_id, word_normalized))

        result = cur.fetchone()
        cur.close()
        conn.close()

        if result:
            return jsonify({
                "is_saved": True,
                "saved_word_id": result['id']
            })
        else:
            return jsonify({
                "is_saved": False,
                "saved_word_id": None
            })

    except Exception as e:
        logger.error(f"Error checking if word is saved: {str(e)}")
        return jsonify({"error": f"Failed to check word status: {str(e)}"}), 500


def get_all_words_for_language_pair(learning_lang, native_lang):
    """Get all words for a specific language pair

    Returns a simple list of words that have definitions in the database
    for the given learning_language and native_language combination.

    Args:
        learning_lang: Learning language code (e.g., 'en', 'de', 'zh')
        native_lang: Native language code (e.g., 'zh', 'en')

    Returns:
        JSON array of word strings
    """
    try:
        # Validate language codes
        if not validate_language(learning_lang) or not validate_language(native_lang):
            return jsonify({"error": "Invalid language code"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # Get all distinct words for this language pair
        cur.execute("""
            SELECT DISTINCT word
            FROM definitions
            WHERE learning_language = %s AND native_language = %s
            ORDER BY word ASC
        """, (learning_lang, native_lang))

        words = [row['word'] for row in cur.fetchall()]

        cur.close()
        conn.close()

        logger.info(f"Retrieved {len(words)} words for {learning_lang}->{native_lang}")

        return jsonify(words)

    except Exception as e:
        logger.error(f"Error getting all words for {learning_lang}->{native_lang}: {str(e)}")
        return jsonify({"error": f"Failed to get words: {str(e)}"}), 500

def toggle_exclude_from_practice():
    """
    Toggle whether a word is excluded from practice.
    POST /v3/words/toggle-exclude

    Request JSON:
    {
        "user_id": "uuid",
        "word": "string",
        "excluded": true/false
    }

    Response:
    {
        "success": true,
        "word_id": "uuid",
        "word": "string",
        "is_excluded": true/false,
        "message": "Word excluded from practice"
    }
    """
    try:
        from services.user_service import toggle_word_exclusion

        data = request.get_json()

        # Validate required fields
        if not data:
            return jsonify({"error": "Request body required"}), 400

        user_id = data.get('user_id')
        word = data.get('word')
        excluded = data.get('excluded')
        learning_language = data.get('learning_language')  # Optional
        native_language = data.get('native_language')  # Optional

        if not user_id or not word or excluded is None:
            return jsonify({
                "error": "Missing required fields",
                "required": ["user_id", "word", "excluded"]
            }), 400

        # Validate UUID format
        try:
            import uuid
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({"error": "Invalid user_id format"}), 400

        # Validate excluded is boolean
        if not isinstance(excluded, bool):
            return jsonify({"error": "excluded must be a boolean"}), 400

        # Call service function with optional language parameters
        result = toggle_word_exclusion(user_id, word, excluded, learning_language, native_language)

        if not result.get('success'):
            error_msg = result.get('message', 'Unknown error')
            logger.warning(f"Failed to toggle exclusion for word='{word}', user_id={user_id}: {error_msg}")
            return jsonify(result), 400

        logger.info(f"Toggled exclusion for word='{word}', user_id={user_id}, excluded={excluded}")
        return jsonify(result), 200

    except Exception as e:
        logger.error(f"Error in toggle_exclude_from_practice: {str(e)}", exc_info=True)
        return jsonify({
            "error": "Internal server error",
            "message": str(e)
        }), 500