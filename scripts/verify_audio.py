#!/usr/bin/env python3
"""
Audio Verification Script

Uses speech-to-text to verify TTS-generated audio matches the source text.
Compares transcribed text with original text using fuzzy matching.
Generates a CSV report of verification results.

Usage:
    python verify_audio.py [--limit N] [--output report.csv]
"""

import argparse
import csv
import io
import json
import logging
import os
import sys
import tempfile
from datetime import datetime
from difflib import SequenceMatcher
from typing import Optional, Tuple, Dict, List

import psycopg2
from psycopg2.extras import RealDictCursor
import openai

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Similarity threshold for passing (0.0 to 1.0)
SIMILARITY_THRESHOLD = 0.85

# Maximum regeneration attempts
MAX_FIX_ATTEMPTS = 3


def get_db_connection():
    """Get database connection from environment or default."""
    db_url = os.environ.get(
        'DATABASE_URL',
        'postgresql://dogeuser:dogepass@localhost:5432/dogetionary'
    )
    return psycopg2.connect(db_url, cursor_factory=RealDictCursor)


def normalize_text(text: str) -> str:
    """Normalize text for comparison (lowercase, strip punctuation)."""
    import re
    # Convert to lowercase
    text = text.lower()
    # Remove punctuation except apostrophes in words
    text = re.sub(r"[^\w\s']", '', text)
    # Normalize whitespace
    text = ' '.join(text.split())
    return text


def calculate_similarity(text1: str, text2: str) -> float:
    """Calculate similarity ratio between two strings."""
    norm1 = normalize_text(text1)
    norm2 = normalize_text(text2)
    return SequenceMatcher(None, norm1, norm2).ratio()


def transcribe_audio_with_whisper(audio_bytes: bytes, language: str) -> Tuple[Optional[str], Optional[str]]:
    """
    Transcribe audio using OpenAI Whisper API.

    Returns:
        Tuple of (transcribed_text, error_message)
    """
    try:
        client = openai.OpenAI()

        # Create a temporary file for the audio
        with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as tmp_file:
            tmp_file.write(audio_bytes)
            tmp_file_path = tmp_file.name

        try:
            with open(tmp_file_path, 'rb') as audio_file:
                response = client.audio.transcriptions.create(
                    model="whisper-1",
                    file=audio_file,
                    language=language if language != 'en' else None,  # Let Whisper auto-detect for English
                    response_format="text"
                )

            return response.strip(), None

        finally:
            # Clean up temp file
            os.unlink(tmp_file_path)

    except openai.APIError as e:
        logger.error(f"Whisper API error: {e}")
        return None, f"Whisper API error: {str(e)}"
    except Exception as e:
        logger.error(f"Error transcribing audio: {e}")
        return None, f"Transcription error: {str(e)}"


def verify_audio(text_content: str, audio_bytes: bytes, language: str) -> Tuple[bool, str, float]:
    """
    Verify audio by transcribing and comparing to source text.

    Returns:
        Tuple of (is_valid, comment, similarity_score)
    """
    # Check for empty or very small audio
    if len(audio_bytes) < 1000:  # Less than 1KB is suspicious
        return False, "Audio file too small (possibly empty or corrupt)", 0.0

    # Transcribe audio
    transcribed_text, error = transcribe_audio_with_whisper(audio_bytes, language)

    if error:
        return False, error, 0.0

    if not transcribed_text:
        return False, "Transcription returned empty text", 0.0

    # Calculate similarity
    similarity = calculate_similarity(text_content, transcribed_text)

    if similarity >= SIMILARITY_THRESHOLD:
        comment = f"Similarity: {similarity:.2%} | Transcribed: '{transcribed_text}'"
        return True, comment, similarity
    else:
        comment = f"[major] Low similarity: {similarity:.2%} | Expected: '{text_content}' | Got: '{transcribed_text}'"
        return False, comment, similarity


def regenerate_audio_with_tts(text_content: str, language: str) -> Optional[bytes]:
    """
    Regenerate audio using OpenAI TTS API.

    Returns:
        Audio bytes or None if generation fails
    """
    try:
        client = openai.OpenAI()

        response = client.audio.speech.create(
            model="tts-1",
            voice="alloy",  # Could be configurable
            input=text_content,
            response_format="mp3"
        )

        # Read the audio content
        audio_bytes = response.content
        return audio_bytes

    except openai.APIError as e:
        logger.error(f"TTS API error: {e}")
        return None
    except Exception as e:
        logger.error(f"Error generating audio: {e}")
        return None


def get_unverified_audio(conn, limit: Optional[int] = None):
    """Get audio entries where ai_verified is explicitly FALSE."""
    cur = conn.cursor()

    query = """
        SELECT text_content, language, audio_data, content_type, version, created_at
        FROM audio
        WHERE ai_verified = FALSE
        ORDER BY created_at DESC
    """

    if limit:
        query += f" LIMIT {limit}"

    cur.execute(query)
    return cur.fetchall()


def update_audio_in_db(conn, text_content: str, language: str, audio_data: bytes,
                        verified: bool, comment: Optional[str] = None,
                        increment_version: bool = False):
    """Update the audio and verification status in database."""
    cur = conn.cursor()
    if increment_version:
        cur.execute("""
            UPDATE audio
            SET audio_data = %s,
                ai_verified = %s,
                ai_verification_comment = %s,
                version = version + 1
            WHERE text_content = %s
              AND language = %s
        """, (psycopg2.Binary(audio_data), verified, comment, text_content, language))
    else:
        cur.execute("""
            UPDATE audio
            SET audio_data = %s,
                ai_verified = %s,
                ai_verification_comment = %s
            WHERE text_content = %s
              AND language = %s
        """, (psycopg2.Binary(audio_data), verified, comment, text_content, language))
    conn.commit()


def generate_csv_report(events: List[Dict], output_path: str):
    """Generate a CSV report of all verification events."""
    if not events:
        logger.info("No events to report")
        return

    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow([
            'text_content',
            'language',
            'attempt',
            'event_type',
            'result',
            'similarity',
            'comment'
        ])

        for event in events:
            writer.writerow([
                event['text_content'],
                event['language'],
                event['attempt'],
                event['event_type'],
                event['result'],
                event.get('similarity', ''),
                event['comment']
            ])

    logger.info(f"CSV report saved to: {output_path}")


def print_statistics(fix_counts: Dict[int, List[str]]):
    """Print statistics about fixes required."""
    logger.info("")
    logger.info("=" * 50)
    logger.info("Fix Statistics")
    logger.info("=" * 50)

    total = sum(len(items) for items in fix_counts.values())

    for num_fixes in sorted(fix_counts.keys()):
        items = fix_counts[num_fixes]
        if num_fixes == 0:
            label = "No fixes required (passed first time)"
        elif num_fixes == -1:
            label = f"Failed after {MAX_FIX_ATTEMPTS} attempts (unfixable)"
        else:
            label = f"Required {num_fixes} fix(es)"

        logger.info(f"{label}: {len(items)} audio entries")
        if len(items) <= 5:
            for item in items:
                logger.info(f"  - {item[:50]}...")
        else:
            logger.info(f"  (first 5 shown)")
            for item in items[:5]:
                logger.info(f"  - {item[:50]}...")

    logger.info("")
    logger.info(f"Total audio entries processed: {total}")


def main():
    global SIMILARITY_THRESHOLD

    parser = argparse.ArgumentParser(description='Verify TTS-generated audio using speech-to-text')
    parser.add_argument('--limit', type=int, help='Maximum number of audio entries to process')
    parser.add_argument('--output', type=str, default='audio_verification_report.csv',
                        help='Output CSV file path')
    parser.add_argument('--dry-run', action='store_true',
                        help='Run verification without updating database')
    parser.add_argument('--threshold', type=float, default=SIMILARITY_THRESHOLD,
                        help=f'Similarity threshold for passing (default: {SIMILARITY_THRESHOLD})')
    args = parser.parse_args()

    SIMILARITY_THRESHOLD = args.threshold

    # Check for OpenAI API key
    if not os.environ.get('OPENAI_API_KEY'):
        logger.error("OPENAI_API_KEY environment variable is required")
        sys.exit(1)

    conn = get_db_connection()

    try:
        audio_entries = get_unverified_audio(conn, args.limit)
        total = len(audio_entries)

        if total == 0:
            logger.info("No unverified audio entries found")
            return

        logger.info(f"Found {total} unverified audio entries")
        logger.info(f"Similarity threshold: {SIMILARITY_THRESHOLD:.0%}")

        all_events = []
        fix_counts = {}

        for i, entry in enumerate(audio_entries, 1):
            text_content = entry['text_content']
            language = entry['language']
            current_audio = bytes(entry['audio_data'])
            current_version = entry.get('version', 1)

            # Truncate for display
            display_text = text_content[:40] + "..." if len(text_content) > 40 else text_content

            logger.info(f"[{i}/{total}] Processing: '{display_text}' ({language}) v{current_version}")

            attempt = 0
            fixes_applied = 0
            verified = False

            while attempt < MAX_FIX_ATTEMPTS and not verified:
                attempt += 1

                is_valid, comment, similarity = verify_audio(text_content, current_audio, language)

                all_events.append({
                    'text_content': text_content,
                    'language': language,
                    'attempt': attempt,
                    'event_type': 'verify',
                    'result': 'PASS' if is_valid else 'FAIL',
                    'similarity': f"{similarity:.2%}" if similarity else "",
                    'comment': comment
                })

                if is_valid:
                    verified = True
                    logger.info(f"  Attempt {attempt}: ✓ PASSED ({similarity:.0%} similarity)")
                else:
                    logger.warning(f"  Attempt {attempt}: ✗ FAILED - {comment[:80]}...")

                    if attempt < MAX_FIX_ATTEMPTS:
                        logger.info(f"  Attempt {attempt}: Regenerating audio...")
                        new_audio = regenerate_audio_with_tts(text_content, language)

                        if new_audio:
                            all_events.append({
                                'text_content': text_content,
                                'language': language,
                                'attempt': attempt,
                                'event_type': 'regenerate',
                                'result': 'SUCCESS',
                                'similarity': '',
                                'comment': f'Audio regenerated ({len(new_audio)} bytes)'
                            })

                            current_audio = new_audio
                            fixes_applied += 1
                        else:
                            all_events.append({
                                'text_content': text_content,
                                'language': language,
                                'attempt': attempt,
                                'event_type': 'regenerate',
                                'result': 'FAIL',
                                'similarity': '',
                                'comment': 'Failed to regenerate audio'
                            })
                            break

            if not args.dry_run:
                should_increment = fixes_applied > 0
                update_audio_in_db(
                    conn, text_content, language, current_audio,
                    verified=verified,
                    comment=comment if not verified else None,
                    increment_version=should_increment
                )

            # Track fix counts
            if verified:
                count_key = fixes_applied
            else:
                count_key = -1

            if count_key not in fix_counts:
                fix_counts[count_key] = []
            fix_counts[count_key].append(text_content)

            if verified:
                if fixes_applied == 0:
                    logger.info(f"  Result: ✓ Passed on first attempt")
                else:
                    logger.info(f"  Result: ✓ Passed after {fixes_applied} fix(es)")
            else:
                logger.error(f"  Result: ✗ Failed after {MAX_FIX_ATTEMPTS} attempts")

        generate_csv_report(all_events, args.output)
        print_statistics(fix_counts)

    except openai.APIError:
        logger.error("API error - stopping processing")
    finally:
        conn.close()


if __name__ == '__main__':
    main()
