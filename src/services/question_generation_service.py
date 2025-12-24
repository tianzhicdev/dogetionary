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
# NOTE: Set to 0 for all types - relying on video_mc prioritization and mc_def_native
QUESTION_TYPE_WEIGHTS = {
    'mc_definition': 0.0,       # Disabled
    'mc_word': 0.0,             # Disabled
    'fill_blank': 0.0,          # Disabled
    'pronounce_sentence': 0.0,  # Disabled
    'mc_def_native': 1.0,       # Native language definition MC (used when no videos available)
    # video_mc is prioritized separately via check_word_has_videos() on line 715
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
        definition: Full definition data (used to get native language translations)
        learning_lang: Language being learned
        native_lang: User's native language

    Returns:
        Dict containing video question data with native language translations in options
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

    # Get native language name for prompt
    lang_name = LANG_NAMES.get(native_lang, native_lang)

    # Generate pedagogically-sound question using enhanced prompt
    prompt = f"""You are generating a vocabulary question for English learners whose native language is {lang_name}.

INPUT:
- TRANSCRIPT: "{audio_transcript}"
- KEYWORD: "{word}"
- NATIVE LANGUAGE: {lang_name}

TASK:
1. Analyze how KEYWORD is used in this transcript
2. Choose the most appropriate question type
3. Generate the question with answer options in BOTH English and {lang_name}

QUESTION TYPES (choose one):

MEANING_IN_CONTEXT
- Use when: the word has multiple meanings and context clarifies which one
- Example: "right" (correct vs. direction), "fire" (flames vs. terminate)

SYNONYM
- Use when: testing if learner can recognize equivalent expressions
- Example: "enormous" → "huge", "vanished" → "disappeared"

COLLOCATION
- Use when: the word pairs naturally with specific other words
- Example: "make" + decision, "heavy" + rain, "commit" + crime

IDIOM_COMPONENT
- Use when: the word is part of an idiomatic expression in the transcript
- Example: "break" in "break the ice", "hit" in "hit the road"

REGISTER
- Use when: the word signals formality level (slang, casual, formal)
- Example: "gonna", "ain't", "commence", "dude"

GRAMMAR_PATTERN
- Use when: the word's form reveals tense, aspect, or structure worth noting
- Example: "been" (present perfect), "would" (conditional), "-ing" vs "-ed"

OUTPUT FORMAT (JSON):
{{
  "question_type": "MEANING_IN_CONTEXT",
  "analysis": "Brief explanation of why this type fits",
  "question": "What does 'X' mean in this scene?",
  "options": [
    {{"text": "...", "text_native": "... ({lang_name} translation)", "correct": true}},
    {{"text": "...", "text_native": "... ({lang_name} translation)", "correct": false}}
  ],
  "explanation": "One sentence explaining the correct answer"
}}

RULES:
- Always exactly 2 options, exactly 1 correct
- Each option MUST have both "text" (English) and "text_native" ({lang_name})
- Distractors must be plausible (common misunderstandings, literal readings, similar words)
- All options similar length and grammatical structure
- Question must be answerable from transcript alone
- Use simple, common vocabulary in all text
- If the keyword usage is too ambiguous to generate a reliable question, return {{"error": "reason"}}"""

    try:
        # Generate pedagogical question with LLM (enhanced format with 2 options)
        # Uses fallback chain: DeepSeek V3 -> Qwen 2.5 -> Mistral Small -> GPT-4o
        response_json = llm_completion_with_fallback(
            messages=[
                {
                    "role": "system",
                    "content": "You are a language learning expert. Analyze transcripts to create pedagogically sound vocabulary questions. Return only valid JSON without markdown formatting."
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            use_case="question",
            schema_name="video_mc_enhanced"  # Use enhanced schema with question types
        )

        # Parse JSON response (strict validation happens in llm_completion)
        parsed = json.loads(response_json.strip())

        # Handle error case (LLM couldn't generate reliable question)
        if 'error' in parsed:
            logger.warning(f"LLM returned error for video question: {parsed['error']}, falling back to mc_definition")
            # Fall back to definition-based question instead
            return generate_question_with_llm(word, definition, learning_lang, native_lang, 'mc_definition')

        # Extract fields from enhanced format
        question_type_detail = parsed['question_type']
        analysis = parsed['analysis']
        question_text = parsed['question']
        options = parsed['options']
        explanation = parsed['explanation']

        # Validate we have exactly 2 options with correct flags
        if len(options) != 2:
            raise ValueError(f"Expected 2 options, got {len(options)}")

        correct_options = [opt for opt in options if opt['correct']]
        if len(correct_options) != 1:
            raise ValueError(f"Expected exactly 1 correct option, got {len(correct_options)}")

        # Extract correct and incorrect options
        correct_option = correct_options[0]
        incorrect_option = next(opt for opt in options if not opt['correct'])

        # Randomize order to avoid pattern learning (correct answer not always A)
        if random.random() < 0.5:
            # Correct answer is A
            ios_options = [
                {'id': 'A', 'text': correct_option['text'], 'text_native': correct_option.get('text_native')},
                {'id': 'B', 'text': incorrect_option['text'], 'text_native': incorrect_option.get('text_native')}
            ]
            correct_answer = 'A'
        else:
            # Correct answer is B
            ios_options = [
                {'id': 'A', 'text': incorrect_option['text'], 'text_native': incorrect_option.get('text_native')},
                {'id': 'B', 'text': correct_option['text'], 'text_native': correct_option.get('text_native')}
            ]
            correct_answer = 'B'

    except Exception as e:
        logger.error(f"Error generating video question with LLM: {e}", exc_info=True)
        # Don't return crap - let the error propagate
        raise

    # Build question data in iOS-compatible format
    question_data = {
        'question_type': 'video_mc',
        'word': word,
        'video_id': video_id,
        'audio_transcript': audio_transcript,  # Use audio_transcript field
        'question_text': question_text,  # Dynamic question from LLM
        'show_word_before_video': False,  # Hide word initially, reveal after answer
        'video_metadata': {
            'movie_title': movie_title,
            'movie_year': movie_year,
            'title': title  # Fallback if movie_title is not available
        },
        'options': ios_options,
        'correct_answer': correct_answer,
        'meta': {  # Store pedagogical metadata for future analytics
            'question_type_detail': question_type_detail,
            'analysis': analysis,
            'explanation': explanation
        }
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

Task: Create a question asking "What does '{word}' mean?" with 2 answer options:
- Option A: The CORRECT definition (clear, concise, pedagogically sound)
- Option B: A plausible but INCORRECT distractor

Distractor requirements:
- Must be semantically related or similar-sounding concept
- Should test real understanding, not be obviously wrong
- Similar length and style to correct answer
- Avoid negations or "none of the above"
- Focus on creating ONE high-quality distractor

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
    {{"id": "B", "text": "..."}}
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
- Option B: A similar word that DOESN'T match the definition
  - Should be related/similar to {word} (synonym, near-synonym, or word in same semantic field)
  - Must be a real English word
  - Should be a believable distractor

IMPORTANT - Distractor Selection:
- Choose a COMMON, WELL-KNOWN word as the distractor
- Avoid obscure, complex, or advanced vocabulary
- Users should recognize the word, even if they don't know exact meaning
- Use a word at a basic to intermediate level
- Focus on creating ONE high-quality distractor

Return ONLY valid JSON (no markdown):
{{
  "question_text": "Which word matches this definition: '{main_definition}'?",
  "options": [
    {{"id": "A", "text": "{word}"}},
    {{"id": "B", "text": "..."}}
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

Task: Create a sentence with a blank where "{word}" should go, plus 2 options.

Requirements:
- Create a natural, context-rich sentence (or use/adapt one of the examples)
- Option A: "{word}" (CORRECT)
- Option B: A related word that DOESN'T fit the context
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
    {{"id": "B", "text": "..."}}
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


def generate_mc_def_native_prompt(word: str, definition_data: Dict, native_lang: str) -> str:
    """Generate prompt for multiple choice native language definition question."""
    definitions = definition_data.get('definitions', [])

    # Extract native language definitions
    native_definitions = []
    for d in definitions:
        if 'definition_native' in d:
            native_definitions.append(d['definition_native'])

    lang_name = LANG_NAMES.get(native_lang, native_lang)

    return f"""Generate a multiple choice question testing understanding of the word "{word}" using {lang_name} definitions.

Word: "{word}"
Available {lang_name} definitions:
{json.dumps(native_definitions, indent=2, ensure_ascii=False)}

Task: Create a question asking "What does '{word}' mean?" with 2 answer options in {lang_name}:
- Option A: The CORRECT definition in {lang_name} (clear, concise, pedagogically sound)
- Option B: A plausible but INCORRECT distractor in {lang_name}

Distractor requirements:
- Must be semantically related or similar concept
- Should test real understanding, not be obviously wrong
- Similar length and style to correct answer
- Avoid negations or "none of the above"
- Focus on creating ONE high-quality distractor in {lang_name}

IMPORTANT - Language Quality:
- Use natural, idiomatic {lang_name}
- Avoid overly literal or awkward translations
- The correct definition should match one of the provided native definitions
- Write at an appropriate level for language learners

Return ONLY valid JSON (no markdown, no explanation):
{{
  "question_text": "What does '{word}' mean?",
  "options": [
    {{"id": "A", "text": "... ({lang_name})"}},
    {{"id": "B", "... ({lang_name})"}}
  ],
  "correct_answer": "A"
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


def call_openai_for_question(prompt: str, schema_name: str) -> Dict:
    """
    Call OpenAI API to generate question based on prompt.

    Args:
        prompt: The prompt for question generation
        schema_name: Name of JSON schema to use (e.g., 'mc_definition', 'mc_fillin')

    Returns:
        Dict containing the generated question data
    """
    try:
        # Uses fallback chain: Gemini -> DeepSeek V3 -> Qwen 2.5 -> GPT-4o-mini
        # JSON validation happens automatically with strict schemas for supported models
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
            schema_name=schema_name  # Use strict JSON schema for type safety
        )

        if not content:
            raise Exception("LLM completion returned empty content")

        # Parse JSON response (strict validation happens in llm_completion)
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

    # Select appropriate prompt generator and schema for LLM-based questions
    if question_type == 'mc_definition':
        prompt = generate_mc_definition_prompt(word, definition, native_lang)
        schema_name = 'mc_definition'
    elif question_type == 'mc_word':
        prompt = generate_mc_word_prompt(word, definition, native_lang)
        schema_name = 'mc_definition'  # Same schema as mc_definition
    elif question_type == 'mc_def_native':
        prompt = generate_mc_def_native_prompt(word, definition, native_lang)
        schema_name = 'mc_definition'  # Same schema as mc_definition
    elif question_type == 'fill_blank':
        prompt = generate_fill_blank_prompt(word, definition, native_lang)
        schema_name = 'mc_fillin'
    elif question_type == 'pronounce_sentence':
        prompt = generate_pronounce_sentence_prompt(word, definition, native_lang)
        schema_name = 'pronounce_sentence'
    else:
        raise ValueError(f"Unknown question type: {question_type}")

    # Generate with LLM using appropriate schema
    question_data = call_openai_for_question(prompt, schema_name)

    # Randomize answer position for MC questions (prevents pattern learning)
    # LLM always returns correct answer as "A", we randomize it here
    if question_type in ['mc_definition', 'mc_word', 'mc_def_native', 'fill_blank']:
        if 'options' in question_data and len(question_data['options']) == 2:
            # Extract option texts (LLM returns: A=correct, B=incorrect)
            option_a = question_data['options'][0]
            option_b = question_data['options'][1]

            # 50/50 chance to swap positions
            if random.random() < 0.5:
                # Keep correct answer as A
                question_data['options'] = [
                    {'id': 'A', 'text': option_a['text']},
                    {'id': 'B', 'text': option_b['text']}
                ]
                question_data['correct_answer'] = 'A'
            else:
                # Swap: correct answer becomes B
                question_data['options'] = [
                    {'id': 'A', 'text': option_b['text']},
                    {'id': 'B', 'text': option_a['text']}
                ]
                question_data['correct_answer'] = 'B'

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
