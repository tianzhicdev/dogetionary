"""
Definition Service

Utility functions for generating and caching word definitions using LLM.
"""

import json
import logging
import openai
from typing import Optional, Dict
from datetime import datetime
from utils.database import get_db_connection

logger = logging.getLogger(__name__)

# Schema version for definitions
CURRENT_SCHEMA_VERSION = 3


def generate_definition_with_llm(word: str, learning_lang: str, native_lang: str, build_prompt_fn) -> Optional[Dict]:
    """
    Generate a word definition using OpenAI and cache it in the database.

    Args:
        word: The word to define
        learning_lang: Language being learned
        native_lang: User's native language
        build_prompt_fn: Function that builds the prompt (from words.py)

    Returns:
        Dict containing definition_data or None if generation fails
    """
    try:
        # Check if definition already exists in cache
        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT definition_data FROM definitions
            WHERE word = %s AND learning_language = %s AND native_language = %s
        """, (word, learning_lang, native_lang))

        existing = cur.fetchone()
        if existing:
            logger.info(f"Definition cache hit for '{word}'")
            cur.close()
            conn.close()
            return existing['definition_data']

        # Generate definition using OpenAI
        logger.info(f"Generating definition with LLM for '{word}' ({learning_lang} → {native_lang})")

        prompt = build_prompt_fn(word, learning_lang, native_lang)

        # Call OpenAI API
        client = openai.OpenAI()
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a helpful assistant that creates dictionary definitions."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=1000,
            temperature=0.3
        )

        definition_content = response.choices[0].message.content.strip()

        # Parse the JSON response from OpenAI
        definition_data = json.loads(definition_content)

        # Ensure the word field matches the input
        definition_data['word'] = word

        # Cache the definition in database
        cur.execute("""
            INSERT INTO definitions (word, learning_language, native_language, definition_data, schema_version, created_at)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (word, learning_language, native_language)
            DO UPDATE SET definition_data = EXCLUDED.definition_data, schema_version = EXCLUDED.schema_version, updated_at = CURRENT_TIMESTAMP
        """, (word, learning_lang, native_lang, json.dumps(definition_data), CURRENT_SCHEMA_VERSION, datetime.now()))

        conn.commit()
        cur.close()
        conn.close()

        logger.info(f"Successfully generated and cached definition for '{word}'")
        return definition_data

    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse OpenAI response for word '{word}': {e}")
        return None
    except Exception as e:
        logger.error(f"Error generating definition for word '{word}': {e}", exc_info=True)
        return None
