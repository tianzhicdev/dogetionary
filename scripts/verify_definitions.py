#!/usr/bin/env python3
"""
Definition Verification and Fix Script

Uses LLM to verify AI-generated dictionary definitions for accuracy.
If a definition fails verification, it attempts to fix it recursively (up to 5 times).
Generates a CSV report of all verification events.

Usage:
    python verify_definitions.py [--limit N] [--output report.csv]
"""

import argparse
import csv
import json
import logging
import os
import sys
from datetime import datetime
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

# Maximum fix attempts per definition
MAX_FIX_ATTEMPTS = 5

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

# V3 Schema for definition generation
WORD_DEFINITION_V3_SCHEMA = {
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
                    "part_of_speech": {"type": "string"},
                    "definition": {"type": "string"},
                    "definition_native": {"type": "string"},
                    "examples": {
                        "type": "array",
                        "items": {"type": "string"}
                    },
                    "cultural_notes": {"type": ["string", "null"]}
                },
                "required": ["part_of_speech", "definition", "definition_native", "examples", "cultural_notes"],
                "additionalProperties": False
            }
        }
    },
    "required": ["valid_word_score", "suggestion", "word", "phonetic", "translations", "definitions"],
    "additionalProperties": False
}


def get_db_connection():
    """Get database connection from environment or default."""
    db_url = os.environ.get(
        'DATABASE_URL',
        'postgresql://dogeuser:dogepass@localhost:5432/dogetionary'
    )
    return psycopg2.connect(db_url, cursor_factory=RealDictCursor)


def verify_definition_with_llm(word: str, definition_data: dict) -> Tuple[bool, str]:
    """
    Use LLM to verify a dictionary definition.

    Returns:
        Tuple of (is_valid, comment)
    """
    definitions = definition_data.get('definitions', [])
    translations = definition_data.get('translations', [])
    phonetic = definition_data.get('phonetic', '')

    if not definitions:
        return False, "No definitions found in definition_data"

    # Build verification prompt
    def_text = ""
    for i, d in enumerate(definitions, 1):
        def_text += f"\n  Definition {i}: {d.get('definition', 'N/A')}"
        def_text += f"\n  Part of speech: {d.get('part_of_speech', 'N/A')}"
        def_text += f"\n  Examples: {', '.join(d.get('examples', [])[:3])}"
        if d.get('definition_native'):
            def_text += f"\n  Native translation: {d.get('definition_native')}"

    prompt = f"""You are a dictionary quality checker. Verify the following dictionary entry for accuracy and quality.

Word: {word}
Phonetic: {phonetic}
Translations: {', '.join(translations[:5]) if translations else 'N/A'}
{def_text}

Check for the following issues:
1. Is the definition accurate and complete for this word?
2. Are the example sentences natural, grammatically correct, and demonstrate proper usage?
3. Is the part of speech correct?
4. Are there any spelling or grammatical errors?
5. Is the phonetic transcription reasonable (if provided)?
6. Are the translations accurate (if provided)?

Respond in the following JSON format:
{{
    "is_valid": true/false,
    "issues": ["list of specific issues found, or empty if valid"],
    "severity": "none" | "minor" | "major" | "critical"
}}

Be strict but fair. Minor issues like slightly awkward phrasing are acceptable.
Major issues include incorrect definitions, wrong part of speech, or grammatically incorrect examples.
Critical issues include completely wrong definitions or inappropriate content."""

    try:
        client = openai.OpenAI()
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a precise dictionary quality checker. Respond only with valid JSON."},
                {"role": "user", "content": prompt}
            ],
            response_format={"type": "json_object"},
            temperature=0.1,
            max_tokens=500
        )

        result_text = response.choices[0].message.content
        result = json.loads(result_text)

        is_valid = result.get('is_valid', False)
        issues = result.get('issues', [])
        severity = result.get('severity', 'unknown')

        # PASS if valid OR if only minor issues (we're lenient on minor issues)
        if is_valid or severity == 'minor' or severity == 'none':
            if severity == 'minor':
                comment = f"[{severity}] (auto-passed) " + "; ".join(issues)
                return True, comment
            return True, ""
        else:
            comment = f"[{severity}] " + "; ".join(issues) if issues else f"[{severity}] Verification failed"
            return False, comment

    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse LLM response for '{word}': {e}")
        return False, f"LLM response parsing error: {str(e)}"
    except openai.APIError as e:
        logger.error(f"OpenAI API error for '{word}': {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error verifying '{word}': {e}")
        return False, f"Verification error: {str(e)}"


def regenerate_definition_with_llm(word: str, learning_lang: str, native_lang: str,
                                    old_definition: dict, issues: str,
                                    all_previous_issues: List[str] = None) -> Optional[Dict]:
    """
    Regenerate a definition based on the issues found.

    Args:
        word: The word to regenerate
        learning_lang: Learning language code
        native_lang: Native language code
        old_definition: Current definition that failed verification
        issues: Issues from the current verification attempt
        all_previous_issues: List of all issues from previous iterations

    Returns:
        New definition_data dict or None if generation fails
    """
    learning_lang_name = LANG_NAMES.get(learning_lang, 'English')
    native_lang_name = LANG_NAMES.get(native_lang, 'Chinese')

    # Build issues history section
    issues_section = f"CURRENT ISSUES (must fix):\n{issues}"
    if all_previous_issues and len(all_previous_issues) > 0:
        issues_section += "\n\nPREVIOUS ISSUES (also avoid):"
        for i, prev_issue in enumerate(all_previous_issues, 1):
            issues_section += f"\n  Attempt {i}: {prev_issue}"

    prompt = f"""You are a bilingual dictionary expert. The following dictionary entry for "{word}" has quality issues that need to be fixed.

CURRENT DEFINITION:
{json.dumps(old_definition, indent=2, ensure_ascii=False)}

{issues_section}

Please generate an improved dictionary entry that addresses ALL the issues above (both current and previous).

REQUIRED STRUCTURE:
- valid_word_score: float (0-1), should be 0.9+ for valid words
- suggestion: null (since we're fixing the word)
- word: "{word}"
- phonetic: IPA pronunciation
- translations: array of {native_lang_name} translations
- definitions: array of objects, each with:
  - part_of_speech: part of speech (noun, verb, etc.)
  - definition: in {learning_lang_name}
  - definition_native: in {native_lang_name}
  - examples: array of 5-6 example sentences (strings only, in {learning_lang_name})
  - cultural_notes: optional cultural context (string or null)

CRITICAL:
- Fix ALL the issues mentioned above
- examples must be an array of plain text strings, NOT objects
- Each example should be a complete, natural sentence in {learning_lang_name}
- Ensure definitions are accurate and complete
- Ensure translations are accurate"""

    try:
        client = openai.OpenAI()
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a bilingual dictionary expert who creates high-quality dictionary entries."},
                {"role": "user", "content": prompt}
            ],
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "word_definition_with_validation",
                    "strict": True,
                    "schema": WORD_DEFINITION_V3_SCHEMA
                }
            },
            temperature=0.3,
            max_tokens=2000
        )

        result_text = response.choices[0].message.content
        new_definition = json.loads(result_text)
        new_definition['word'] = word  # Ensure word matches
        return new_definition

    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse regenerated definition for '{word}': {e}")
        return None
    except openai.APIError as e:
        logger.error(f"OpenAI API error regenerating '{word}': {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error regenerating '{word}': {e}")
        return None


def get_unverified_definitions(conn, limit: Optional[int] = None):
    """Get definitions where ai_verified is explicitly FALSE (not NULL)."""
    cur = conn.cursor()

    query = """
        SELECT word, learning_language, native_language, definition_data, version, created_at
        FROM definitions
        WHERE ai_verified = FALSE
        ORDER BY created_at DESC
    """

    if limit:
        query += f" LIMIT {limit}"

    cur.execute(query)
    return cur.fetchall()


def update_definition_in_db(conn, word: str, learning_lang: str, native_lang: str,
                             definition_data: dict, verified: bool, comment: Optional[str] = None,
                             increment_version: bool = False):
    """Update the definition and verification status in database."""
    cur = conn.cursor()
    if increment_version:
        cur.execute("""
            UPDATE definitions
            SET definition_data = %s,
                ai_verified = %s,
                ai_verification_comment = %s,
                version = version + 1,
                updated_at = NOW()
            WHERE word = %s
              AND learning_language = %s
              AND native_language = %s
        """, (json.dumps(definition_data), verified, comment, word, learning_lang, native_lang))
    else:
        cur.execute("""
            UPDATE definitions
            SET definition_data = %s,
                ai_verified = %s,
                ai_verification_comment = %s,
                updated_at = NOW()
            WHERE word = %s
              AND learning_language = %s
              AND native_language = %s
        """, (json.dumps(definition_data), verified, comment, word, learning_lang, native_lang))
    conn.commit()


def generate_csv_report(events: List[Dict], output_path: str):
    """Generate a CSV report of all verification events."""
    if not events:
        logger.info("No events to report")
        return

    with open(output_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow([
            'word',
            'learning_language',
            'native_language',
            'attempt',
            'event_type',
            'result',
            'comment',
            'definition_data'
        ])

        for event in events:
            writer.writerow([
                event['word'],
                event['learning_language'],
                event['native_language'],
                event['attempt'],
                event['event_type'],
                event['result'],
                event['comment'],
                event['definition_data']
            ])

    logger.info(f"CSV report saved to: {output_path}")


def print_statistics(fix_counts: Dict[int, List[str]]):
    """Print statistics about fixes required."""
    logger.info("")
    logger.info("=" * 50)
    logger.info("Fix Statistics")
    logger.info("=" * 50)

    total_words = sum(len(words) for words in fix_counts.values())

    for num_fixes in sorted(fix_counts.keys()):
        words = fix_counts[num_fixes]
        if num_fixes == 0:
            label = "No fixes required (passed first time)"
        elif num_fixes == -1:
            label = f"Failed after {MAX_FIX_ATTEMPTS} attempts (unfixable)"
        else:
            label = f"Required {num_fixes} fix(es)"

        logger.info(f"{label}: {len(words)} words")
        if len(words) <= 10:
            logger.info(f"  Words: {', '.join(words)}")
        else:
            logger.info(f"  Words: {', '.join(words[:10])}... and {len(words) - 10} more")

    logger.info("")
    logger.info(f"Total words processed: {total_words}")


def main():
    parser = argparse.ArgumentParser(description='Verify and fix AI-generated dictionary definitions')
    parser.add_argument('--limit', type=int, help='Maximum number of definitions to process')
    parser.add_argument('--output', type=str, default='verification_report.csv',
                        help='Output CSV file path (default: verification_report.csv)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Run verification without updating database')
    args = parser.parse_args()

    # Check for OpenAI API key
    if not os.environ.get('OPENAI_API_KEY'):
        logger.error("OPENAI_API_KEY environment variable is required")
        sys.exit(1)

    conn = get_db_connection()

    try:
        # Get unverified definitions
        definitions = get_unverified_definitions(conn, args.limit)
        total = len(definitions)

        if total == 0:
            logger.info("No unverified definitions found")
            return

        logger.info(f"Found {total} unverified definitions")

        # Track all events for CSV report
        all_events = []

        # Track fix counts: {num_fixes: [list of words]}
        # -1 means failed after max attempts
        fix_counts = {}

        for i, defn in enumerate(definitions, 1):
            word = defn['word']
            learning_lang = defn['learning_language']
            native_lang = defn['native_language']
            current_definition = defn['definition_data']
            current_version = defn.get('version', 1)

            logger.info(f"[{i}/{total}] Processing: {word} ({learning_lang}->{native_lang}) v{current_version}")

            attempt = 0
            fixes_applied = 0
            verified = False
            all_issues_history = []  # Track all issues across attempts

            while attempt < MAX_FIX_ATTEMPTS and not verified:
                attempt += 1

                # Verify current definition
                is_valid, comment = verify_definition_with_llm(word, current_definition)

                # Record verification event
                all_events.append({
                    'word': word,
                    'learning_language': learning_lang,
                    'native_language': native_lang,
                    'attempt': attempt,
                    'event_type': 'verify',
                    'result': 'PASS' if is_valid else 'FAIL',
                    'comment': comment,
                    'definition_data': json.dumps(current_definition, ensure_ascii=False)
                })

                if is_valid:
                    verified = True
                    logger.info(f"  Attempt {attempt}: ✓ PASSED")
                else:
                    logger.warning(f"  Attempt {attempt}: ✗ FAILED - {comment[:80]}...")

                    if attempt < MAX_FIX_ATTEMPTS:
                        # Try to regenerate with full issue history
                        logger.info(f"  Attempt {attempt}: Regenerating definition...")
                        new_definition = regenerate_definition_with_llm(
                            word, learning_lang, native_lang, current_definition, comment,
                            all_previous_issues=all_issues_history
                        )

                        # Add current issue to history for next iteration
                        all_issues_history.append(comment)

                        if new_definition:
                            # Record regeneration event
                            all_events.append({
                                'word': word,
                                'learning_language': learning_lang,
                                'native_language': native_lang,
                                'attempt': attempt,
                                'event_type': 'regenerate',
                                'result': 'SUCCESS',
                                'comment': f'Definition regenerated (issues history: {len(all_issues_history)})',
                                'definition_data': json.dumps(new_definition, ensure_ascii=False)
                            })

                            current_definition = new_definition
                            fixes_applied += 1
                        else:
                            # Record failed regeneration
                            all_events.append({
                                'word': word,
                                'learning_language': learning_lang,
                                'native_language': native_lang,
                                'attempt': attempt,
                                'event_type': 'regenerate',
                                'result': 'FAIL',
                                'comment': 'Failed to regenerate definition',
                                'definition_data': ''
                            })
                            break

            # Update database
            if not args.dry_run:
                # Increment version if we made any fixes
                should_increment = fixes_applied > 0
                if verified:
                    update_definition_in_db(
                        conn, word, learning_lang, native_lang,
                        current_definition, verified=True, comment=None,
                        increment_version=should_increment
                    )
                else:
                    update_definition_in_db(
                        conn, word, learning_lang, native_lang,
                        current_definition, verified=False, comment=comment,
                        increment_version=should_increment
                    )

            # Track fix counts
            if verified:
                count_key = fixes_applied
            else:
                count_key = -1  # Failed after max attempts

            if count_key not in fix_counts:
                fix_counts[count_key] = []
            fix_counts[count_key].append(word)

            # Log result
            if verified:
                if fixes_applied == 0:
                    logger.info(f"  Result: ✓ Passed on first attempt")
                else:
                    logger.info(f"  Result: ✓ Passed after {fixes_applied} fix(es)")
            else:
                logger.error(f"  Result: ✗ Failed after {MAX_FIX_ATTEMPTS} attempts")

        # Generate CSV report
        generate_csv_report(all_events, args.output)

        # Print statistics
        print_statistics(fix_counts)

    except openai.APIError:
        logger.error("API error - stopping processing")
    finally:
        conn.close()


if __name__ == '__main__':
    main()
