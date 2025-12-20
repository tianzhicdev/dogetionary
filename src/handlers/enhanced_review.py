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
from services.audio_service import get_or_generate_audio_base64

logger = logging.getLogger(__name__)


def fetch_and_cache_definition(word: str, learning_lang: str, native_lang: str) -> Optional[Dict]:
    """
    Fetch definition for a word using LLM and cache it in the database.
    Uses the shared V3 definition generation logic.
    Returns the definition_data or None if fetch fails.
    """
    try:
        # Import here to avoid circular imports
        from services.definition_service import get_or_generate_definition

        # Generate definition using shared V3 utility (no build_prompt_fn needed)
        definition_data = get_or_generate_definition(
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


