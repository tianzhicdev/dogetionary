"""
Test vocabulary handlers for TOEFL/IELTS/DEMO preparation features
"""

from flask import jsonify, request
from datetime import datetime, date
import logging
import sys
import os
from typing import Dict, Any, Optional

# Add parent directory to Python path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utils.database import get_db_connection, db_cursor, db_fetch_scalar

logger = logging.getLogger(__name__)

# Configuration
DAILY_TEST_WORDS = 10  # Number of words to add per day (compile-time configurable)

# Test type mapping: test_type -> (enabled_column, target_days_column, vocab_column)
TEST_TYPE_MAPPING = {
    'TOEFL_BEGINNER': ('toefl_beginner_enabled', 'toefl_beginner_target_days', 'is_toefl_beginner'),
    'TOEFL_INTERMEDIATE': ('toefl_intermediate_enabled', 'toefl_intermediate_target_days', 'is_toefl_intermediate'),
    'TOEFL_ADVANCED': ('toefl_advanced_enabled', 'toefl_advanced_target_days', 'is_toefl_advanced'),
    'IELTS_BEGINNER': ('ielts_beginner_enabled', 'ielts_beginner_target_days', 'is_ielts_beginner'),
    'IELTS_INTERMEDIATE': ('ielts_intermediate_enabled', 'ielts_intermediate_target_days', 'is_ielts_intermediate'),
    'IELTS_ADVANCED': ('ielts_advanced_enabled', 'ielts_advanced_target_days', 'is_ielts_advanced'),
    'DEMO': ('demo_enabled', 'demo_target_days', 'is_demo'),
    'BUSINESS_ENGLISH': ('business_english_enabled', 'business_english_target_days', 'business_english'),
    'EVERYDAY_ENGLISH': ('everyday_english_enabled', 'everyday_english_target_days', 'everyday_english'),
    # Legacy mappings for backward compatibility
    'TOEFL': ('toefl_advanced_enabled', 'toefl_advanced_target_days', 'is_toefl_advanced'),
    'IELTS': ('ielts_advanced_enabled', 'ielts_advanced_target_days', 'is_ielts_advanced'),
}

# All test enable columns (for disabling all tests)
ALL_TEST_ENABLE_COLUMNS = [
    'toefl_beginner_enabled', 'toefl_intermediate_enabled', 'toefl_advanced_enabled',
    'ielts_beginner_enabled', 'ielts_intermediate_enabled', 'ielts_advanced_enabled',
    'demo_enabled',
    'business_english_enabled', 'everyday_english_enabled'
]


def get_active_test_type(prefs: dict) -> str:
    """
    Determine the active test type from user preferences.

    Args:
        prefs: Dictionary of user preferences (from database row)

    Returns:
        Active test type string (e.g., 'TOEFL_BEGINNER') or None
    """
    for test_type, (enabled_col, _, _) in TEST_TYPE_MAPPING.items():
        if test_type in ['TOEFL', 'IELTS']:  # Skip legacy mappings
            continue
        if prefs.get(enabled_col):
            return test_type
    return None


def is_test_prep_enabled(prefs: dict) -> bool:
    """
    Check if any test preparation mode is enabled.

    This helper function consolidates the common pattern of checking
    all test prep boolean flags with a long OR chain.

    Args:
        prefs: Dictionary of user preferences (from database row)

    Returns:
        True if any test prep mode is enabled, False otherwise

    Example:
        prefs = {'toefl_beginner_enabled': True, ...}
        is_test_prep_enabled(prefs)  # Returns True
    """
    return any([
        prefs.get('toefl_enabled'),
        prefs.get('ielts_enabled'),
        prefs.get('demo_enabled'),
        prefs.get('toefl_beginner_enabled'),
        prefs.get('toefl_intermediate_enabled'),
        prefs.get('toefl_advanced_enabled'),
        prefs.get('ielts_beginner_enabled'),
        prefs.get('ielts_intermediate_enabled'),
        prefs.get('ielts_advanced_enabled'),
        prefs.get('business_english_enabled'),
        prefs.get('everyday_english_enabled'),
    ])


def batch_populate_test_vocabulary():
    """
    Batch populate definitions and questions for test vocabulary words.

    Request JSON:
    {
        "words": ["word1", "word2", ...],
        "learning_language": "en",
        "native_language": "zh",
        "generate_definitions": true,  // optional, default true
        "generate_questions": true,    // optional, default true
        "question_types": ["mc_definition", "fill_blank"]  // optional, defaults to all 4 types
    }

    Returns:
    {
        "success": true,
        "summary": {
            "total_words": 100,
            "definitions_generated": 85,
            "definitions_cached": 15,
            "questions_generated": 340,
            "questions_cached": 60,
            "errors": []
        },
        "processing_time_seconds": 45.2
    }
    """
    try:
        import time
        from services.definition_service import get_or_generate_definition
        from services.question_generation_service import get_or_generate_question, QUESTION_TYPE_WEIGHTS
        from utils.database import db_fetch_one

        start_time = time.time()
        data = request.get_json()

        # Extract and validate parameters
        words = data.get('words', [])
        learning_lang = data.get('learning_language', 'en')
        native_lang = data.get('native_language', 'zh')
        gen_definitions = data.get('generate_definitions', True)
        gen_questions = data.get('generate_questions', True)
        question_types = data.get('question_types', list(QUESTION_TYPE_WEIGHTS.keys()))

        if not words:
            return jsonify({"error": "words array is required and cannot be empty"}), 400

        if not isinstance(words, list):
            return jsonify({"error": "words must be an array"}), 400

        # Initialize counters
        summary = {
            "total_words": len(words),
            "definitions_generated": 0,
            "definitions_cached": 0,
            "questions_generated": 0,
            "questions_cached": 0,
            "errors": []
        }

        logger.info(f"🚀 Starting batch population for {len(words)} words (learning={learning_lang}, native={native_lang})")

        # Process each word
        for i, word in enumerate(words):
            try:
                word = word.strip().lower()

                if not word:
                    continue

                # Step 1: Generate/retrieve definition
                definition = None
                if gen_definitions:
                    # Check if already cached first
                    cached_def = db_fetch_one("""
                        SELECT definition_data FROM definitions
                        WHERE word = %s AND learning_language = %s AND native_language = %s
                    """, (word, learning_lang, native_lang))

                    if cached_def:
                        definition = cached_def['definition_data']
                        summary["definitions_cached"] += 1
                        logger.debug(f"✓ Definition cached for '{word}'")
                    else:
                        # Generate new definition
                        definition = get_or_generate_definition(word, learning_lang, native_lang)

                        if definition:
                            summary["definitions_generated"] += 1
                            logger.debug(f"✓ Generated definition for '{word}'")
                        else:
                            summary["errors"].append({
                                "word": word,
                                "error": "Failed to generate definition"
                            })
                            logger.warning(f"❌ Failed to generate definition for '{word}'")
                            continue
                else:
                    # Retrieve existing definition for question generation
                    cached_def = db_fetch_one("""
                        SELECT definition_data FROM definitions
                        WHERE word = %s AND learning_language = %s AND native_language = %s
                    """, (word, learning_lang, native_lang))

                    if cached_def:
                        definition = cached_def['definition_data']
                    else:
                        summary["errors"].append({
                            "word": word,
                            "error": "Definition not found and generation disabled"
                        })
                        logger.warning(f"❌ No definition found for '{word}' (generation disabled)")
                        continue

                # Step 2: Generate questions
                if gen_questions and definition:
                    for q_type in question_types:
                        try:
                            # Check if question already cached
                            cached_question = db_fetch_one("""
                                SELECT question_data FROM review_questions
                                WHERE word = %s AND learning_language = %s
                                AND native_language = %s AND question_type = %s
                            """, (word, learning_lang, native_lang, q_type))

                            if cached_question:
                                summary["questions_cached"] += 1
                                logger.debug(f"✓ Question cached for '{word}' ({q_type})")
                            else:
                                # Generate new question (passing definition to avoid re-fetching)
                                result = get_or_generate_question(
                                    word=word,
                                    learning_lang=learning_lang,
                                    native_lang=native_lang,
                                    question_type=q_type,
                                    definition=definition
                                )

                                if result and result.get('question'):
                                    summary["questions_generated"] += 1
                                    logger.debug(f"✓ Generated question for '{word}' ({q_type})")

                        except Exception as qe:
                            logger.warning(f"Failed to generate {q_type} for '{word}': {qe}")
                            summary["errors"].append({
                                "word": word,
                                "question_type": q_type,
                                "error": str(qe)
                            })

                # Progress logging every 10 words
                if (i + 1) % 10 == 0:
                    logger.info(f"📊 Progress: {i + 1}/{len(words)} words processed")

            except Exception as e:
                logger.error(f"Error processing word '{word}': {e}", exc_info=True)
                summary["errors"].append({
                    "word": word,
                    "error": str(e)
                })

        processing_time = time.time() - start_time

        # Final summary
        logger.info(f"""
✅ Batch population completed in {processing_time:.2f}s
   Total words: {summary['total_words']}
   Definitions - Generated: {summary['definitions_generated']}, Cached: {summary['definitions_cached']}
   Questions - Generated: {summary['questions_generated']}, Cached: {summary['questions_cached']}
   Errors: {len(summary['errors'])}
""")

        return jsonify({
            "success": True,
            "summary": summary,
            "processing_time_seconds": round(processing_time, 2)
        }), 200

    except Exception as e:
        logger.error(f"Batch population failed: {e}", exc_info=True)
        return jsonify({"error": "Internal server error", "details": str(e)}), 500