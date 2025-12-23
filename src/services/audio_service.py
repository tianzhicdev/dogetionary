"""
Audio Service

Provides consistent cache-first audio generation for TTS.
All audio operations should go through this service.
"""

import base64
import logging
import openai
from datetime import datetime
from typing import Optional
from utils.database import db_fetch_one, get_db_connection
from config.config import TTS_MODEL_NAME, TTS_VOICE

logger = logging.getLogger(__name__)


def audio_exists(text: str, language: str) -> bool:
    """Check if audio exists for text+language"""
    try:
        result = db_fetch_one("""
            SELECT 1 FROM audio
            WHERE text_content = %s AND language = %s
        """, (text, language))
        return result is not None
    except Exception as e:
        logger.error(f"Error checking audio existence: {str(e)}", exc_info=True)
        return False


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
        logger.error(f"Failed to generate audio: {str(e)}", exc_info=True)
        raise


def store_audio(text: str, language: str, audio_data: bytes) -> str:
    """Store audio, return the created_at timestamp"""
    from utils.database import db_cursor

    try:
        with db_cursor(commit=True) as cur:
            # First try to insert
            cur.execute("""
                INSERT INTO audio (text_content, language, audio_data, content_type)
                VALUES (%s, %s, %s, 'audio/mpeg')
                ON CONFLICT (text_content, language)
                DO UPDATE SET audio_data = EXCLUDED.audio_data, content_type = EXCLUDED.content_type
            """, (text, language, audio_data))

        # After commit, fetch the timestamp
        result = db_fetch_one("""
            SELECT created_at FROM audio
            WHERE text_content = %s AND language = %s
        """, (text, language))

        return result['created_at'].isoformat() if result else datetime.now().isoformat()

    except Exception as e:
        logger.error(f"Error storing audio: {str(e)}", exc_info=True)
        raise


def get_or_generate_audio(text: str, language: str) -> bytes:
    """
    Get or generate audio data (cache-first pattern).

    Args:
        text: The text to generate audio for
        language: Language code (e.g., 'en', 'zh')

    Returns:
        Raw audio bytes (mp3)
    """
    try:
        # Check cache
        result = db_fetch_one(
            "SELECT audio_data FROM audio WHERE text_content = %s AND language = %s",
            (text, language)
        )

        if result:
            logger.info(f"Audio cache hit for '{text[:50]}...'")
            return result['audio_data']

        # Generate
        logger.info(f"Generating audio for '{text[:50]}...' in {language}")
        audio_data = generate_audio_for_text(text)

        # Store
        store_audio(text, language, audio_data)

        return audio_data

    except Exception as e:
        logger.error(f"Error getting/generating audio: {e}", exc_info=True)
        raise


def get_or_generate_audio_base64(text: str, language: str) -> str:
    """
    Get or generate audio as base64 data URI.

    Args:
        text: The text to generate audio for
        language: Language code (e.g., 'en', 'zh')

    Returns:
        Data URI string: "data:audio/mpeg;base64,..."
    """
    try:
        audio_data = get_or_generate_audio(text, language)
        audio_base64 = base64.b64encode(audio_data).decode('utf-8')
        return f"data:audio/mpeg;base64,{audio_base64}"
    except Exception as e:
        logger.error(f"Error getting/generating audio base64: {e}", exc_info=True)
        return ""  # Return empty string on error (safe fallback)
