"""
Pronunciation evaluation service using OpenAI Whisper and GPT-4
"""

import openai
import json
import logging
import tempfile
import os
from utils.llm import llm_completion_with_fallback
from typing import Dict, Any
from config.config import WHISPER_MODEL_NAME

logger = logging.getLogger(__name__)

class PronunciationService:
    def __init__(self):
        self.client = openai.OpenAI(api_key=os.environ.get('OPENAI_API_KEY'))

    def evaluate_pronunciation(self, original_text: str, audio_data: bytes,
                              user_id: str, metadata: Dict[str, Any],
                              language: str = 'en') -> Dict[str, Any]:
        """
        Evaluate user pronunciation using OpenAI Whisper and GPT-4

        Args:
            original_text: Text the user is trying to pronounce
            audio_data: Audio recording in bytes
            user_id: User ID (for logging purposes)
            metadata: Additional metadata (for logging purposes)
            language: Language code for speech recognition (e.g. 'en', 'zh', 'es')

        Returns:
            Dict with success, result, similarity_score, recognized_text, feedback
        """
        try:
            # Step 1: Speech-to-text using Whisper
            recognized_text = self._speech_to_text(audio_data, language)

            if not recognized_text:
                return {
                    'success': False,
                    'error': 'Could not recognize speech. Please speak clearly and try again.'
                }

            # Step 2: Compare similarity using LLM
            comparison_result = self._compare_pronunciation(original_text, recognized_text)

            logger.info(f"Pronunciation evaluated for user {user_id}: {comparison_result['similar']}")

            return {
                'success': True,
                'result': comparison_result['similar'],
                'similarity_score': comparison_result['score'],
                'recognized_text': recognized_text,
                'feedback': comparison_result['feedback']
            }

        except Exception as e:
            logger.error(f"Error evaluating pronunciation: {str(e)}", exc_info=True)
            return {
                'success': False,
                'error': f'Failed to process pronunciation: {str(e)}'
            }

    def _speech_to_text(self, audio_data: bytes, language: str = 'en') -> str:
        """
        Convert audio to text using OpenAI Whisper

        Args:
            audio_data: Audio recording in bytes
            language: Language code for speech recognition (ISO 639-1 code)
        """
        try:
            # Save audio data to temporary file
            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp_file:
                tmp_file.write(audio_data)
                tmp_file_path = tmp_file.name

            # Use Whisper API for transcription
            with open(tmp_file_path, 'rb') as audio_file:
                transcript = self.client.audio.transcriptions.create(
                    model=WHISPER_MODEL_NAME,
                    file=audio_file,
                    language=language  # Use user's learning language
                )

            # Clean up temp file
            os.unlink(tmp_file_path)

            recognized_text = transcript.text.strip()
            logger.info(f"Whisper recognized (language={language}): '{recognized_text}'")

            return recognized_text

        except Exception as e:
            logger.error(f"Speech-to-text error: {str(e)}", exc_info=True)
            return ""

    def _compare_pronunciation(self, original: str, spoken: str) -> Dict[str, Any]:
        """
        Compare original text with spoken text using GPT-4
        """
        try:
            prompt = f"""Compare these two texts for pronunciation accuracy:
Original text: "{original}"
Spoken text (from speech recognition): "{spoken}"

Consider:
- Phonetic similarity
- Common pronunciation variations and accents
- Minor recognition errors that don't affect pronunciation quality
- Word order and completeness

Return JSON with:
1. "similar": true if pronunciation is acceptable (>70% accurate), false otherwise
2. "score": similarity score from 0.0 to 1.0
3. "feedback": brief, encouraging feedback for the user

Examples:
- Original: "hello world", Spoken: "hello world" → similar: true, score: 1.0
- Original: "hello world", Spoken: "helo world" → similar: true, score: 0.85
- Original: "hello world", Spoken: "bye world" → similar: false, score: 0.5

Respond with valid JSON only."""

            # Uses fallback chain: DeepSeek V3 -> Mistral Small -> GPT-4o
            content = llm_completion_with_fallback(
                messages=[
                    {
                        "role": "system",
                        "content": "You are a pronunciation evaluator. Be encouraging but honest."
                    },
                    {
                        "role": "user",
                        "content": prompt
                    }
                ],
                use_case="pronunciation",
                schema_name="pronunciation"  # Use strict JSON schema for type safety
            )

            if not content:
                return {
                    'similar': False,
                    'score': 0.0,
                    'feedback': 'Unable to evaluate pronunciation. Please try again.'
                }

            # Validate JSON response (handles list-instead-of-dict errors)
            from utils.llm import validate_json_response
            result = validate_json_response(content, "pronunciation")

            # Ensure all required fields are present with correct types
            return {
                'similar': result.get('similar', False),
                'score': float(result.get('score', 0.0)),
                'feedback': result.get('feedback', 'Please try again.')
            }

        except Exception as e:
            logger.error(f"Pronunciation comparison error: {str(e)}", exc_info=True)
            # Default to lenient comparison if GPT-4 fails
            similar = original.lower().replace(" ", "") == spoken.lower().replace(" ", "")
            return {
                'similar': similar,
                'score': 1.0 if similar else 0.5,
                'feedback': 'Great job!' if similar else 'Keep practicing!'
            }

