"""
Question Generation Service for Enhanced Review System

Generates diverse review questions (multiple choice, fill-in-blank) using LLM APIs.
Implements caching to avoid regenerating the same questions.
"""

import json
import random
import logging
from typing import Dict, Any, Optional, List
from utils.database import db_fetch_one, db_execute
from utils.llm import llm_completion
from config.config import COMPLETION_MODEL_NAME

logger = logging.getLogger(__name__)

# Language code to name mapping for prompts
LANG_NAMES = {
    'en': 'English', 'zh': 'Chinese', 'es': 'Spanish', 'fr': 'French',
    'de': 'German', 'ja': 'Japanese', 'ko': 'Korean', 'pt': 'Portuguese',
    'ru': 'Russian', 'ar': 'Arabic', 'hi': 'Hindi', 'it': 'Italian'
}

# Question type weights for random selection
QUESTION_TYPE_WEIGHTS = {
    'mc_definition': 0.40,   # Most common - tests comprehension
    'mc_word': 0.30,         # Tests word recognition from definition
    'fill_blank': 0.30,      # Tests contextual usage
}


def get_random_question_type() -> str:
    """Randomly select a question type based on weights."""
    return random.choices(
        list(QUESTION_TYPE_WEIGHTS.keys()),
        weights=list(QUESTION_TYPE_WEIGHTS.values())
    )[0]


def get_cached_question(word: str, learning_lang: str, native_lang: str, question_type: str) -> Optional[Dict]:
    """
    Check if a question for this word/language/type combination is already cached.

    Returns:
        Dict with question_data if found, None otherwise
    """
    try:
        result = db_fetch_one("""
            SELECT question_data
            FROM review_questions
            WHERE word = %s
            AND learning_language = %s
            AND native_language = %s
            AND question_type = %s
        """, (word, learning_lang, native_lang, question_type))

        if result:
            logger.info(f"Cache hit for question: {word} ({question_type})")
            return result['question_data']

        logger.info(f"Cache miss for question: {word} ({question_type})")
        return None

    except Exception as e:
        logger.error(f"Error checking question cache: {e}")
        return None


def cache_question(word: str, learning_lang: str, native_lang: str, question_type: str, question_data: Dict):
    """
    Store generated question in cache for future use.
    """
    try:
        db_execute("""
            INSERT INTO review_questions (word, learning_language, native_language, question_type, question_data)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (word, learning_language, native_language, question_type)
            DO UPDATE SET question_data = EXCLUDED.question_data, created_at = CURRENT_TIMESTAMP
        """, (word, learning_lang, native_lang, question_type, json.dumps(question_data)), commit=True)

        logger.info(f"Cached question for: {word} ({question_type})")

    except Exception as e:
        logger.error(f"Error caching question: {e}")


def generate_mc_definition_prompt(word: str, definition_data: Dict, native_lang: str) -> str:
    """Generate prompt for multiple choice definition question."""
    translations = definition_data.get('translations', [])
    definitions = definition_data.get('definitions', [])

    return f"""Generate a multiple choice question to test understanding of the word: "{word}"

Word information:
- Translations: {', '.join(translations)}
- Definitions: {json.dumps(definitions, indent=2)}

Task: Create a question asking "What does '{word}' mean?" with 4 answer options:
- Option A: The CORRECT definition (clear, concise, pedagogically sound)
- Options B, C, D: Plausible but INCORRECT distractors

Distractor requirements:
- Must be semantically related or similar-sounding concepts
- Should test real understanding, not be obviously wrong
- Similar length and style to correct answer
- Avoid negations or "none of the above"

IMPORTANT - Language Simplicity:
- Use SIMPLE, COMMON vocabulary in all answer options
- Avoid complex, obscure, or advanced words that learners might not know
- The focus is testing '{word}' - don't confuse users with difficult words in the options
- Write at a basic to intermediate English level

Return ONLY valid JSON (no markdown, no explanation):
{{
  "question_text": "What does '{word}' mean?",
  "options": [
    {{"id": "A", "text": "..."}},
    {{"id": "B", "text": "..."}},
    {{"id": "C", "text": "..."}},
    {{"id": "D", "text": "..."}}
  ],
  "correct_answer": "A"
}}"""


def generate_mc_word_prompt(word: str, definition_data: Dict, native_lang: str) -> str:
    """Generate prompt for multiple choice word selection question."""
    definitions = definition_data.get('definitions', [])
    main_definition = definitions[0]['definition'] if definitions else ""

    return f"""Generate a multiple choice question to test word recognition for: "{word}"

Definition: "{main_definition}"

Task: Create a question showing the definition and asking which word it describes.

Requirements:
- Option A: "{word}" (CORRECT)
- Options B, C, D: Similar words that DON'T match the definition
  - Should be related/similar to {word} (synonyms, near-synonyms, or words in same semantic field)
  - Must be real English words
  - Should be believable distractors

IMPORTANT - Distractor Selection:
- Choose COMMON, WELL-KNOWN words as distractors
- Avoid obscure, complex, or advanced vocabulary
- Users should recognize all the word options, even if they don't know exact meanings
- Use words at a basic to intermediate level

Return ONLY valid JSON (no markdown):
{{
  "question_text": "Which word matches this definition: '{main_definition}'?",
  "options": [
    {{"id": "A", "text": "{word}"}},
    {{"id": "B", "text": "..."}},
    {{"id": "C", "text": "..."}},
    {{"id": "D", "text": "..."}}
  ],
  "correct_answer": "A"
}}"""


def generate_fill_blank_prompt(word: str, definition_data: Dict, native_lang: str) -> str:
    """Generate prompt for fill-in-the-blank question."""
    definitions = definition_data.get('definitions', [])
    examples = []
    for d in definitions:
        examples.extend(d.get('examples', []))

    lang_name = LANG_NAMES.get(native_lang, native_lang)

    return f"""Generate a fill-in-the-blank question for the word: "{word}"

Definition data:
{json.dumps(definition_data, indent=2)}

Task: Create a sentence with a blank where "{word}" should go, plus 4 options.

Requirements:
- Create a natural, context-rich sentence (or use/adapt one of the examples)
- Option A: "{word}" (CORRECT)
- Options B, C, D: Related words that DON'T fit the context
- Include translation of the sentence to {lang_name}

IMPORTANT - Language Simplicity:
- Use SIMPLE, COMMON vocabulary in the sentence (except for the target word)
- Choose WELL-KNOWN, BASIC words as distractors
- Avoid complex or obscure words that might confuse learners
- The sentence should be easy to understand except for the blank
- Write at a basic to intermediate English level

Return ONLY valid JSON:
{{
  "sentence": "The beauty of cherry blossoms is _____, lasting only a few weeks.",
  "question_text": "Fill in the blank:",
  "options": [
    {{"id": "A", "text": "{word}"}},
    {{"id": "B", "text": "..."}},
    {{"id": "C", "text": "..."}},
    {{"id": "D", "text": "..."}}
  ],
  "correct_answer": "A",
  "sentence_translation": "..."
}}"""


def shuffle_question_options(question_data: Dict) -> Dict:
    """
    Shuffle the options in a multiple choice question to randomize answer position.

    Args:
        question_data: Question dict with 'options' list and 'correct_answer'

    Returns:
        Question dict with shuffled options and updated correct_answer
    """
    if 'options' not in question_data or 'correct_answer' not in question_data:
        return question_data

    options = question_data['options']
    correct_id = question_data['correct_answer']

    # Check if options are dicts or strings
    if not options:
        logger.warning("Options list is empty, skipping shuffle")
        return question_data

    # Check if ALL options are dicts (not just the first one)
    if not all(isinstance(opt, dict) for opt in options):
        logger.warning(f"Not all options are dicts (types: {[type(opt).__name__ for opt in options]}), skipping shuffle")
        return question_data

    # Find the correct answer text
    correct_text = None
    for opt in options:
        if opt.get('id') == correct_id:
            correct_text = opt.get('text')
            break

    if correct_text is None:
        logger.warning("Could not find correct answer in options, skipping shuffle")
        return question_data

    # Shuffle the options
    random.shuffle(options)

    # Reassign IDs (A, B, C, D) and find new correct answer position
    new_correct_id = None
    id_labels = ['A', 'B', 'C', 'D']
    for i, opt in enumerate(options):
        if opt.get('text') == correct_text:
            new_correct_id = id_labels[i]
        opt['id'] = id_labels[i]

    question_data['options'] = options
    question_data['correct_answer'] = new_correct_id

    logger.info(f"Shuffled options, correct answer moved from {correct_id} to {new_correct_id}")
    return question_data


def call_openai_for_question(prompt: str) -> Dict:
    """
    Call OpenAI API to generate question based on prompt.

    Returns:
        Dict containing the generated question data
    """
    try:
        content = llm_completion(
            messages=[
                {
                    "role": "system",
                    "content": "You are a language learning expert creating pedagogically sound review questions. Return only valid JSON without markdown formatting."
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            model_name=COMPLETION_MODEL_NAME,
            response_format={"type": "json_object"}  # Ensure JSON response
        )

        if not content:
            raise Exception("LLM completion returned empty content")

        question_data = json.loads(content)

        logger.info("Successfully generated question with LLM")
        return question_data

    except Exception as e:
        logger.error(f"Error calling LLM API: {e}")
        raise


def generate_question_with_llm(
    word: str,
    definition: Dict,
    learning_lang: str,
    native_lang: str,
    question_type: str
) -> Dict:
    """
    Generate a question using LLM based on question type.

    Args:
        word: The word to create a question for
        definition: Full definition data from definitions table
        learning_lang: Language code being learned
        native_lang: User's native language code
        question_type: Type of question to generate

    Returns:
        Dict containing question data ready to send to client
    """
    logger.info(f"Generating {question_type} question for word: {word}")

    # Select appropriate prompt generator
    if question_type == 'mc_definition':
        prompt = generate_mc_definition_prompt(word, definition, native_lang)
    elif question_type == 'mc_word':
        prompt = generate_mc_word_prompt(word, definition, native_lang)
    elif question_type == 'fill_blank':
        prompt = generate_fill_blank_prompt(word, definition, native_lang)
    else:
        raise ValueError(f"Unknown question type: {question_type}")

    # Generate with LLM
    question_data = call_openai_for_question(prompt)

    # Add metadata
    question_data['question_type'] = question_type
    question_data['word'] = word

    return question_data


def get_or_generate_question(
    word: str,
    definition: Dict,
    learning_lang: str,
    native_lang: str,
    question_type: Optional[str] = None
) -> Dict:
    """
    Get question from cache or generate new one if not cached.

    Args:
        word: The word to create a question for
        definition: Full definition data
        learning_lang: Language being learned
        native_lang: User's native language
        question_type: Specific type or None for random selection

    Returns:
        Dict containing question data with shuffled options
    """
    import copy

    # Select random question type if not specified
    if question_type is None:
        question_type = get_random_question_type()

    # Check cache first
    cached = get_cached_question(word, learning_lang, native_lang, question_type)
    if cached:
        # Make a deep copy so we don't modify the cached version
        question = copy.deepcopy(cached)
    else:
        # Generate new question
        question = generate_question_with_llm(word, definition, learning_lang, native_lang, question_type)

        # Cache for future use (before shuffling, so cache has consistent order)
        cache_question(word, learning_lang, native_lang, question_type, question)

        # Make a copy for shuffling
        question = copy.deepcopy(question)

    # Always shuffle options before returning (so correct answer isn't always A)
    question = shuffle_question_options(question)

    return question
