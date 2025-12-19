"""
Enhanced Review Handlers

Provides API endpoints for enhanced review system with diverse question types.
"""

from flask import jsonify, request
import logging
import json
import base64
from typing import Dict, Any, Optional
from utils.database import db_fetch_one, get_db_connection
from services.question_generation_service import get_or_generate_question
from services.user_service import get_user_preferences
from services.schedule_service import get_user_timezone, get_today_in_timezone

logger = logging.getLogger(__name__)


def get_or_generate_audio_base64(text: str, language: str) -> str:
    """
    Get or generate audio for text and return as base64 encoded data URI.

    Args:
        text: The text to generate audio for
        language: Language code (e.g., 'en', 'zh')

    Returns:
        Base64 encoded audio data URI (data:audio/mpeg;base64,...)
    """
    try:
        from handlers.words import generate_audio_for_text, store_audio

        conn = get_db_connection()
        cur = conn.cursor()

        # Try to get existing audio from cache
        cur.execute("""
            SELECT audio_data
            FROM audio
            WHERE text_content = %s AND language = %s
        """, (text, language))

        result = cur.fetchone()

        if result:
            # Found cached audio
            cur.close()
            conn.close()
            audio_base64 = base64.b64encode(result['audio_data']).decode('utf-8')
            logger.info(f"Retrieved cached audio for text: '{text[:50]}...'")
            return f"data:audio/mpeg;base64,{audio_base64}"

        # Audio doesn't exist, generate it
        cur.close()
        conn.close()

        logger.info(f"Generating audio for text: '{text[:50]}...' in {language}")
        audio_data = generate_audio_for_text(text)

        # Store in database for future use
        store_audio(text, language, audio_data)

        # Return as base64 data URI
        audio_base64 = base64.b64encode(audio_data).decode('utf-8')
        return f"data:audio/mpeg;base64,{audio_base64}"

    except Exception as e:
        logger.error(f"Error getting/generating audio: {e}", exc_info=True)
        # Return None or empty string on error
        return ""


def fetch_and_cache_definition(word: str, learning_lang: str, native_lang: str) -> Optional[Dict]:
    """
    Fetch definition for a word using LLM and cache it in the database.
    Uses the shared V3 definition generation logic.
    Returns the definition_data or None if fetch fails.
    """
    try:
        # Import here to avoid circular imports
        from services.definition_service import generate_definition_with_llm

        # Generate definition using shared V3 utility (no build_prompt_fn needed)
        definition_data = generate_definition_with_llm(
            word=word,
            learning_lang=learning_lang,
            native_lang=native_lang
        )

        if definition_data:
            logger.info(f"Successfully fetched and cached V3 definition for '{word}' (score: {definition_data.get('valid_word_score', 'N/A')})")
            return definition_data
        else:
            logger.warning(f"Failed to fetch definition for '{word}'")
            return None

    except Exception as e:
        logger.error(f"Error fetching definition for '{word}': {e}", exc_info=True)
        return None


