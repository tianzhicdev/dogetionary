"""
Question Generation Service for Enhanced Review System

Generates diverse review questions (multiple choice, fill-in-blank) using LLM APIs.
Implements caching to avoid regenerating the same questions.
"""

import json
import random
import logging
import re
from typing import Dict, Any, Optional, List
from utils.database import db_fetch_one, db_execute
from utils.llm import llm_completion_with_fallback

logger = logging.getLogger(__name__)


def clean_json_response(json_str: str) -> str:
    """
    Clean up common JSON formatting issues from LLM responses.

    Fixes:
    - Trailing commas in arrays/objects (e.g., [1, 2, 3,])
    - Leading/trailing whitespace

    Args:
        json_str: Raw JSON string from LLM

    Returns:
        Cleaned JSON string ready for parsing
    """
    # Remove trailing commas before closing brackets/braces
    # Matches: ,<optional whitespace>] or ,<optional whitespace>}
    json_str = re.sub(r',\s*([}\]])', r'\1', json_str)

    return json_str.strip()

# Language code to name mapping for prompts
LANG_NAMES = {
    'en': 'English', 'zh': 'Chinese', 'es': 'Spanish', 'fr': 'French',
    'de': 'German', 'ja': 'Japanese', 'ko': 'Korean', 'pt': 'Portuguese',
    'ru': 'Russian', 'ar': 'Arabic', 'hi': 'Hindi', 'it': 'Italian'
}

# Question type weights for random selection
# NOTE: Temporarily boosted video_mc to 90% for testing video questions
QUESTION_TYPE_WEIGHTS = {
    'mc_definition': 0.2,       # Tests comprehension
    'mc_word': 0.2,             # Tests word recognition from definition
    'fill_blank': 0.2,          # Tests contextual usage
    'pronounce_sentence': 0.4,  # Tests pronunciation with sentence context
    # 'video_mc': 0.90,            # Tests visual recognition from video (TESTING: normally 0.10)
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
        logger.error(f"Error checking question cache: {e}", exc_info=True)
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
        logger.error(f"Error caching question: {e}", exc_info=True)


def check_word_has_videos(word: str, learning_lang: str) -> Optional[Dict]:
    """
    Check if word has linked videos available (under 5MB for performance).

    Args:
        word: The vocabulary word
        learning_lang: Language of the word

    Returns:
        Dict with video_id, audio_transcript, and metadata if videos exist, None otherwise
    """
    try:
        # Only select videos under 5MB (5242880 bytes) for better performance
        result = db_fetch_one("""
            SELECT v.id, v.audio_transcript, v.metadata, v.name
            FROM word_to_video wtv
            JOIN videos v ON v.id = wtv.video_id
            WHERE LOWER(wtv.word) = LOWER(%s)
              AND wtv.learning_language = %s
              AND v.size_bytes <= 5242880
            ORDER BY wtv.relevance_score DESC NULLS LAST, RANDOM()
            LIMIT 1
        """, (word, learning_lang))

        if result:
            metadata = result.get('metadata', {}) or {}
            logger.info(f"Found video for word '{word}': video_id={result['id']}, has_audio_transcript={result['audio_transcript'] is not None}")
            return {
                'video_id': result['id'],
                'audio_transcript': result['audio_transcript'],
                'movie_title': metadata.get('movie_title'),
                'movie_year': metadata.get('movie_year'),
                'title': result.get('name')  # Fallback to video name
            }

        return None

    except Exception as e:
        logger.error(f"Error checking videos for word '{word}': {e}", exc_info=True)
        return None


def generate_video_mc_question(word: str, definition: Dict, learning_lang: str, native_lang: str) -> Dict:
    """
    Generate a video multiple-choice question.

    Uses LLM to infer the word's meaning from the video transcript and generate distractors.

    Args:
        word: The vocabulary word
        definition: Full definition data (not used for video questions)
        learning_lang: Language being learned
        native_lang: User's native language

    Returns:
        Dict containing video question data
    """
    # Check if word has videos
    video_info = check_word_has_videos(word, learning_lang)

    if not video_info:
        logger.warning(f"No videos found for word '{word}', falling back to mc_definition")
        # Fallback to mc_definition if no videos available
        return generate_question_with_llm(word, definition, learning_lang, native_lang, 'mc_definition')

    video_id = video_info['video_id']
    audio_transcript = video_info.get('audio_transcript')
    movie_title = video_info.get('movie_title')
    movie_year = video_info.get('movie_year')
    title = video_info.get('title')

    # If no transcript available, fallback to mc_definition
    if not audio_transcript:
        logger.warning(f"No audio_transcript available for video {video_id}, falling back to mc_definition")
        return generate_question_with_llm(word, definition, learning_lang, native_lang, 'mc_definition')

    # Generate meaning and distractors using LLM based on transcript context
    prompt = f"""Given this audio transcript from a video and a target word, determine the word's meaning based on how it's used in the transcript, then generate 3 plausible but incorrect alternatives.

Audio transcript: "{audio_transcript}"

Target word: "{word}"

Task:
1. Infer the meaning of "{word}" based on how it's used in the transcript
2. Generate 3 plausible but INCORRECT definitions that could confuse learners

Requirements:
- The correct meaning should be clear, concise, and pedagogically sound
- Distractors must be semantically related or describe similar concepts
- All definitions should use simple, common vocabulary
- Similar length and complexity across all options
- Avoid negations or "none of the above"

Return ONLY a JSON object with this structure:
{{
  "correct_meaning": "the correct definition inferred from transcript context",
  "distractors": ["distractor 1 text", "distractor 2 text", "distractor 3 text"]
}}"""

    try:
        # Generate meaning and distractors with LLM
        # Uses fallback chain: DeepSeek V3 -> Qwen 2.5 -> Mistral Small -> GPT-4o
        response_json = llm_completion_with_fallback(
            messages=[
                {
                    "role": "system",
                    "content": "You are a language learning expert. Analyze transcripts to infer word meanings. Return only valid JSON without markdown formatting."
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            use_case="question",
            response_format={"type": "json_object"}
        )

        # Parse the response
        parsed = json.loads(response_json.strip())

        if not isinstance(parsed, dict) or 'correct_meaning' not in parsed or 'distractors' not in parsed:
            raise ValueError("LLM response missing required fields")

        correct_meaning = parsed['correct_meaning']
        distractors = parsed['distractors']

        if not isinstance(distractors, list) or len(distractors) != 3:
            raise ValueError("LLM did not return exactly 3 distractors")

    except Exception as e:
        logger.error(f"Error generating video question with LLM: {e}", exc_info=True)
        # Don't return crap - let the error propagate
        raise

    # Build question data
    question_data = {
        'question_type': 'video_mc',
        'word': word,
        'video_id': video_id,
        'audio_transcript': audio_transcript,  # Use audio_transcript field
        'question_text': f"Which best describes the meaning of '{word}' in this scene?",
        'show_word_before_video': False,  # Hide word initially, reveal after answer
        'video_metadata': {
            'movie_title': movie_title,
            'movie_year': movie_year,
            'title': title  # Fallback if movie_title is not available
        },
        'options': [
            {'id': 'A', 'text': correct_meaning, 'is_correct': True},
            {'id': 'B', 'text': distractors[0], 'is_correct': False},
            {'id': 'C', 'text': distractors[1], 'is_correct': False},
            {'id': 'D', 'text': distractors[2], 'is_correct': False}
        ],
        'correct_answer': 'A'
    }

    logger.info(f"Generated video_mc question for word '{word}' with video_id={video_id}, movie_title={movie_title}, has_audio_transcript={audio_transcript is not None}")

    return question_data


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


def generate_pronounce_sentence_prompt(word: str, definition_data: Dict, native_lang: str) -> str:
    """Generate prompt for pronunciation sentence question."""
    definitions = definition_data.get('definitions', [])
    examples = []
    for d in definitions:
        examples.extend(d.get('examples', []))

    lang_name = LANG_NAMES.get(native_lang, native_lang)

    return f"""Generate a natural sentence containing the word "{word}" for pronunciation practice.

Definition data:
{json.dumps(definition_data, indent=2)}

Task: Create a sentence that uses "{word}" in context for the learner to pronounce aloud.

Requirements:
- Sentence should be 8-15 words long
- Use SIMPLE, COMMON vocabulary (except for the target word "{word}")
- The sentence should clearly demonstrate the word's meaning through context
- Natural, conversational tone (could be adapted from examples if suitable)
- Include translation of the complete sentence to {lang_name}
- The sentence should sound natural when spoken aloud

IMPORTANT - Language Simplicity:
- Use basic to intermediate vocabulary in the sentence
- Avoid complex grammar structures
- Make sure the sentence flows naturally for speaking practice
- The goal is pronunciation practice, not vocabulary confusion

Return ONLY valid JSON:
{{
  "sentence": "The beauty of cherry blossoms is ephemeral, lasting only a few weeks.",
  "sentence_translation": "...",
  "question_text": "Pronounce this sentence:"
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
        # Uses fallback chain: Gemini -> DeepSeek V3 -> Qwen 2.5 -> GPT-4o-mini
        # JSON validation happens automatically in llm_completion() with fallback on error
        content = llm_completion_with_fallback(
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
            use_case="question",
            response_format={"type": "json_object"}  # Ensure JSON response
        )

        if not content:
            raise Exception("LLM completion returned empty content")

        # Parse JSON (already validated and cleaned in llm_completion())
        question_data = json.loads(content)

        logger.info("Successfully generated question with LLM")
        return question_data

    except Exception as e:
        logger.error(f"Error in question generation: {e}", exc_info=True)
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

    # Handle video_mc type specially (doesn't use LLM for generation)
    if question_type == 'video_mc':
        return generate_video_mc_question(word, definition, learning_lang, native_lang)
    # Select appropriate prompt generator for LLM-based questions
    if question_type == 'mc_definition':
        prompt = generate_mc_definition_prompt(word, definition, native_lang)
    elif question_type == 'mc_word':
        prompt = generate_mc_word_prompt(word, definition, native_lang)
    elif question_type == 'fill_blank':
        prompt = generate_fill_blank_prompt(word, definition, native_lang)
    elif question_type == 'pronounce_sentence':
        prompt = generate_pronounce_sentence_prompt(word, definition, native_lang)
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
    learning_lang: str,
    native_lang: str,
    question_type: Optional[str] = None,
    definition: Optional[Dict] = None
) -> Optional[Dict]:
    """
    Self-contained function that fetches/generates definition (if not provided),
    generates question, and handles audio for pronounce_sentence questions.

    Args:
        word: The word to create a question for
        learning_lang: Language being learned
        native_lang: User's native language
        question_type: Specific type or None for random selection
        definition: Optional pre-fetched definition (for batch operations)

    Returns:
        Dict containing complete question data:
        {
            "question": {...},  # Question with audio_url if pronounce_sentence
            "definition_data": {...},  # Full definition
            "audio_references": {...}  # Audio availability map
        }
        or None if definition fetch fails
    """
    # Import here to avoid circular imports
    import base64
    from utils.database import get_db_connection

    # Step 1: Get or fetch definition (if not provided)
    if definition is None:
        from services.definition_service import get_or_generate_definition
        definition_data = get_or_generate_definition(word, learning_lang, native_lang)

        if definition_data is None:
            logger.warning(f"Could not get definition for '{word}', cannot generate question")
            return None
    else:
        # Use provided definition (for batch operations that already fetched it)
        definition_data = definition

    # Step 2: Select question type with video prioritization
    if question_type is None:
        # PRIORITY 1: Always use video_mc if word has videos
        if check_word_has_videos(word, learning_lang):
            question_type = 'video_mc'
            logger.info(f"Prioritizing video_mc for '{word}' (videos available)")
        else:
            # PRIORITY 2: Random selection from all types (including video_mc with fallback)
            question_type = get_random_question_type()

            logger.info(f"{question_type} selected for '{word}' by random")

    # Step 3: Check cache first
    cached = get_cached_question(word, learning_lang, native_lang, question_type)
    if cached:
        # DB returns fresh dict - no need to copy
        question = cached
    else:
        # Generate new question
        question = generate_question_with_llm(word, definition_data, learning_lang, native_lang, question_type)

        # Cache for future use (before shuffling, so cache has consistent order)
        cache_question(word, learning_lang, native_lang, question_type, question)

    # Step 4: Always shuffle options before returning (so correct answer isn't always A)
    question = shuffle_question_options(question)

    # Step 5: Handle audio for pronounce_sentence questions
    if question.get('question_type') == 'pronounce_sentence' and question.get('sentence'):
        from services.audio_service import get_or_generate_audio_base64
        audio_url = get_or_generate_audio_base64(question['sentence'], learning_lang)
        question['audio_url'] = audio_url

    # Step 6: Build audio references
    from handlers.words import collect_audio_references
    from services.audio_service import audio_exists
    audio_refs = collect_audio_references(definition_data, learning_lang)
    if audio_exists(word, learning_lang):
        audio_refs["word_audio"] = True

    # Step 7: Return complete package
    return {
        "question": question,
        "definition_data": definition_data,
        "audio_references": audio_refs
    }
