"""
Definition Service

Utility functions for generating and caching word definitions using LLM.
Shared logic for word definition generation used by both handlers and services.
"""

import json
import logging
from typing import Optional, Dict
from datetime import datetime
from utils.database import get_db_connection
from utils.llm import llm_completion
from config.config import COMPLETION_MODEL_NAME

logger = logging.getLogger(__name__)

# Schema version for definitions
CURRENT_SCHEMA_VERSION = 4

# V4 Schema with vocabulary learning enhancements
WORD_DEFINITION_V4_SCHEMA = {
    "type": "object",
    "properties": {
        "valid_word_score": {
            "type": "number",
            "description": "Score between 0 and 1 indicating validity (0.9+ = highly valid)"
        },
        "suggestion": {
            "type": ["string", "null"],
            "description": "Suggested correction if score < 0.9, otherwise null"
        },
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
                    "part_of_speech": {"type": "string", "description": "Part of speech: noun, verb, adjective, etc"},
                    "definition": {"type": "string", "description": "Definition in learning language"},
                    "definition_native": {"type": "string", "description": "Definition in user's native language"},
                    "examples": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "5-6 example sentences as plain text strings in the learning language"
                    },
                    "cultural_notes": {"type": ["string", "null"], "description": "Optional cultural context"}
                },
                "required": ["part_of_speech", "definition", "definition_native", "examples", "cultural_notes"],
                "additionalProperties": False
            }
        },
        "collocations": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Common word combinations (e.g., 'make a decision', 'heavy rain', 'commit a crime')"
        },
        "synonyms": {
            "type": ["array", "null"],
            "items": {"type": "string"},
            "description": "Words with similar meaning"
        },
        "antonyms": {
            "type": ["array", "null"],
            "items": {"type": "string"},
            "description": "Words with opposite meaning"
        },
        "comment": {
            "type": ["string", "null"],
            "description": "Optional natural language comment that helps the user to understand the word better, such as a trivia, common mistakes when using this word, typical situations when using this word, etc."
        },
        "source": {
            "type": ["string", "null"],
            "description": "Optional description of where the word is from or its etymological root in natural language"
        },
        "word_family": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "word": {"type": "string", "description": "Related word form"},
                    "part_of_speech": {"type": "string", "description": "Part of speech of this form"}
                },
                "required": ["word", "part_of_speech"],
                "additionalProperties": False
            },
            "description": "Related forms of the word (noun, verb, adjective, adverb variants)"
        },
        "cognates": {
            "type": ["string", "null"],
            "description": "Related words in other languages sharing etymology (null for Chinese learners)"
        },
        "famous_quote": {
            "type": ["object", "null"],
            "properties": {
                "quote": {"type": "string", "description": "The sentence or quote"},
                "source": {"type": "string", "description": "Attribution - person, book, movie, etc."}
            },
            "required": ["quote", "source"],
            "additionalProperties": False,
            "description": "One notable quote or sentence featuring this word"
        }
    },
    "required": [
        "valid_word_score",
        "suggestion",
        "word",
        "phonetic",
        "translations",
        "definitions",
        "collocations",
        "synonyms",
        "antonyms",
        "comment",
        "source",
        "word_family",
        "cognates",
        "famous_quote"
    ],
    "additionalProperties": False
}

# Language code to name mapping
LANG_NAMES = {
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
    'pt': 'Portuguese', 'pa': 'Punjabi', 'ro': 'Romanian', 'ru': 'Russian',
    'sr': 'Serbian', 'sk': 'Slovak', 'sl': 'Slovenian', 'es': 'Spanish',
    'sw': 'Swahili', 'sv': 'Swedish', 'tl': 'Tagalog', 'ta': 'Tamil',
    'te': 'Telugu', 'th': 'Thai', 'tr': 'Turkish', 'uk': 'Ukrainian',
    'ur': 'Urdu', 'vi': 'Vietnamese', 'cy': 'Welsh'
}


def build_v4_definition_prompt(word: str, learning_lang: str, native_lang: str) -> str:
    """
    Build V4 prompt for comprehensive bilingual definition with vocabulary learning enhancements.
    This is the shared prompt used across the application.
    """
    learning_lang_name = LANG_NAMES.get(learning_lang, 'English')
    native_lang_name = LANG_NAMES.get(native_lang, 'Chinese')
    word_normalized = word.strip()

    return f"""Provide a comprehensive bilingual dictionary entry for: "{word_normalized}"

IMPORTANT STRUCTURE:
- valid_word_score: float (0-1)
- suggestion: string or null
- word: "{word_normalized}"
- phonetic: IPA pronunciation
- translations: array of {native_lang_name} translations
- definitions: array of objects, each with:
  - part_of_speech: part of speech (noun, verb, etc.)
  - definition: in {learning_lang_name}
  - definition_native: in {native_lang_name}
  - examples: array of 5-6 example sentences (strings only, in {learning_lang_name})
  - cultural_notes: optional cultural context (string or null)

VOCABULARY LEARNING FIELDS:
- collocations: array of common word combinations (e.g., "make a decision", "heavy traffic")
- synonyms: array of similar words, or null if none
- antonyms: array of opposite words, or null if none
- comment: optional string in natural language describing usage notes like formality level (formal/informal/slang), frequency (very common/rare), connotation (positive/negative), common confusions with similar words, or other important learning tips. Only include if relevant and important. Use simple, clear language.
- source: optional string in natural language describing the word's origin or etymological root (e.g., "From Latin 'facere' meaning 'to make'", "Borrowed from French in the 18th century"). Only include if interesting or helpful for learning.
- word_family: array of related word forms, each with "word" and "part_of_speech" (e.g., persuade->persuasion->persuasive)
- cognates: related words in other languages sharing etymology, or null (null for Chinese speakers)
- famous_quote: single object with "quote" and "source", or null if no notable quote exists. Include only ONE memorable quote if the word appears in famous literature, movies, speeches, etc.

VALIDATION RULES:
Consider VALID (score 0.9-1.0):
- Dictionary words, common phrases, internet slang, brand names, abbreviations

Consider INVALID (score < 0.9):
- Typos (provide suggestion)
- Misspellings (provide suggestion)
- Gibberish (score 0.0-0.4, suggestion optional)

IMPORTANT - Language Simplicity:
- Use SIMPLE, COMMON vocabulary in all generated content (except for the target word itself)
- For collocations: use basic, everyday word combinations
- For confusables: explain using simple language
- For synonyms/antonyms: prefer well-known words
- For examples: use simple sentence structures
- Write at a basic to intermediate {learning_lang_name} level

CRITICAL:
- examples must be an array of plain text strings, NOT objects
- Each example should be a complete sentence in {learning_lang_name}
- For collocations, provide 3-6 common combinations
- For word_family, include all common forms (noun, verb, adjective, adverb if they exist)
- For comment: only include if there are important usage notes worth mentioning (formality, frequency, connotation, common confusions with similar words, or other learning tips). Keep it concise and natural.
- For source: only include if the etymology is interesting or helpful for remembering the word. Keep it brief and accessible."""


def generate_definition_with_llm(word: str, learning_lang: str, native_lang: str, build_prompt_fn=None) -> Optional[Dict]:
    """
    Generate a word definition using OpenAI V4 schema and cache it in the database.
    Uses the V4 schema with vocabulary learning enhancements.

    Args:
        word: The word to define
        learning_lang: Language being learned
        native_lang: User's native language
        build_prompt_fn: Deprecated - kept for backward compatibility but not used

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

        # Generate definition using OpenAI with V4 schema
        logger.info(f"Generating V4 definition with LLM for '{word}' ({learning_lang} → {native_lang})")

        # Use V4 prompt
        prompt = build_v4_definition_prompt(word, learning_lang, native_lang)

        # Call OpenAI API with V4 schema using utility function
        definition_content = llm_completion(
            messages=[
                {
                    "role": "system",
                    "content": "You are a bilingual dictionary expert who validates words and provides comprehensive vocabulary learning content using simple, accessible language."
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            model_name=COMPLETION_MODEL_NAME,
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "word_definition_v4_with_learning_features",
                    "strict": True,
                    "schema": WORD_DEFINITION_V4_SCHEMA
                }
            }
        )

        # Check if content is None or empty
        if not definition_content:
            logger.error(f"LLM completion returned empty content for word '{word}'")
            return None

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

        logger.info(f"Successfully generated and cached V4 definition for '{word}' (score: {definition_data.get('valid_word_score', 'N/A')})")
        return definition_data

    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse OpenAI response for word '{word}': {e}")
        return None
    except Exception as e:
        logger.error(f"Error generating definition for word '{word}': {e}", exc_info=True)
        return None
