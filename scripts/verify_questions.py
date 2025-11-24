#!/usr/bin/env python3
"""
Question Verification and Fix Script

Uses LLM to verify AI-generated review questions for accuracy.
If a question fails verification, it attempts to fix it recursively (up to 5 times).
Generates a CSV report of all verification events.

Usage:
    python verify_questions.py [--limit N] [--output report.csv]
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

# Maximum fix attempts per question
MAX_FIX_ATTEMPTS = 5


def get_db_connection():
    """Get database connection from environment or default."""
    db_url = os.environ.get(
        'DATABASE_URL',
        'postgresql://dogeuser:dogepass@localhost:5432/dogetionary'
    )
    return psycopg2.connect(db_url, cursor_factory=RealDictCursor)


def verify_question_with_llm(word: str, question_type: str, question_data: dict) -> Tuple[bool, str]:
    """
    Use LLM to verify a review question.

    Returns:
        Tuple of (is_valid, comment)
    """
    question_text = question_data.get('question_text', '')
    options = question_data.get('options', [])
    correct_answer = question_data.get('correct_answer', '')
    sentence = question_data.get('sentence', '')  # For fill_blank

    # Build options text (handle malformed options gracefully)
    options_text = ""
    correct_option_text = ""
    has_malformed_options = False
    for opt in options:
        if isinstance(opt, dict):
            opt_id = opt.get('id', '')
            opt_text = opt.get('text', '')
            options_text += f"\n  {opt_id}: {opt_text}"
            if opt_id == correct_answer:
                correct_option_text = opt_text
        else:
            # Malformed option (string instead of dict)
            has_malformed_options = True

    # If options are malformed, fail immediately
    if has_malformed_options:
        return False, "[critical] Malformed options data - contains non-dict elements"

    prompt = f"""You are a language learning question quality checker. Verify the following review question for accuracy and quality.

Word being tested: {word}
Question type: {question_type}
Question: {question_text}
{f'Sentence: {sentence}' if sentence else ''}
Options:{options_text}
Correct answer: {correct_answer} ({correct_option_text})

Check for the following issues:
1. Is there exactly ONE correct answer among the options?
2. Is the marked correct answer actually correct for this word?
3. Are the distractors (wrong answers) plausible but clearly incorrect?
4. Is the question unambiguous and well-formed?
5. Are all options grammatically consistent with each other?
6. For fill_blank: Does the correct word fit naturally in the sentence?

Respond in the following JSON format:
{{
    "is_valid": true/false,
    "issues": ["list of specific issues found, or empty if valid"],
    "severity": "none" | "minor" | "major" | "critical"
}}

Major issues: wrong correct answer, multiple correct answers, ambiguous question
Minor issues: slightly awkward phrasing, minor grammatical issues
Critical issues: completely wrong correct answer, inappropriate content"""

    try:
        client = openai.OpenAI()
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a precise question quality checker. Respond only with valid JSON."},
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

        # PASS if valid OR if only minor issues
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


def regenerate_question_with_llm(word: str, question_type: str, old_question: dict,
                                  issues: str, all_previous_issues: List[str] = None) -> Optional[Dict]:
    """
    Regenerate a question based on the issues found.

    Returns:
        New question_data dict or None if generation fails
    """
    # Build issues history section
    issues_section = f"CURRENT ISSUES (must fix):\n{issues}"
    if all_previous_issues and len(all_previous_issues) > 0:
        issues_section += "\n\nPREVIOUS ISSUES (also avoid):"
        for i, prev_issue in enumerate(all_previous_issues, 1):
            issues_section += f"\n  Attempt {i}: {prev_issue}"

    if question_type == 'mc_definition':
        structure = """Return JSON:
{
  "question_text": "What does 'WORD' mean?",
  "options": [
    {"id": "A", "text": "correct definition"},
    {"id": "B", "text": "plausible but wrong"},
    {"id": "C", "text": "plausible but wrong"},
    {"id": "D", "text": "plausible but wrong"}
  ],
  "correct_answer": "A",
  "question_type": "mc_definition",
  "word": "WORD"
}"""
    elif question_type == 'mc_word':
        structure = """Return JSON:
{
  "question_text": "Which word matches this definition: '...'?",
  "options": [
    {"id": "A", "text": "correct word"},
    {"id": "B", "text": "similar but wrong word"},
    {"id": "C", "text": "similar but wrong word"},
    {"id": "D", "text": "similar but wrong word"}
  ],
  "correct_answer": "A",
  "question_type": "mc_word",
  "word": "WORD"
}"""
    elif question_type == 'fill_blank':
        structure = """Return JSON:
{
  "sentence": "A sentence with _____ where the word goes.",
  "question_text": "Fill in the blank:",
  "options": [
    {"id": "A", "text": "correct word"},
    {"id": "B", "text": "similar but wrong"},
    {"id": "C", "text": "similar but wrong"},
    {"id": "D", "text": "similar but wrong"}
  ],
  "correct_answer": "A",
  "question_type": "fill_blank",
  "word": "WORD"
}"""
    else:
        return None  # Can't regenerate recognition type

    prompt = f"""You are a language learning expert. The following review question for "{word}" has quality issues.

CURRENT QUESTION:
{json.dumps(old_question, indent=2, ensure_ascii=False)}

{issues_section}

Please generate an improved question that fixes ALL the issues above.

Requirements:
- The correct answer MUST be option A
- Distractors must be plausible but clearly wrong
- Only ONE option should be correct
- Question must be unambiguous

{structure.replace('WORD', word)}"""

    try:
        client = openai.OpenAI()
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a language learning expert creating high-quality review questions. Return only valid JSON."},
                {"role": "user", "content": prompt}
            ],
            response_format={"type": "json_object"},
            temperature=0.3,
            max_tokens=1000
        )

        result_text = response.choices[0].message.content
        new_question = json.loads(result_text)
        new_question['word'] = word
        new_question['question_type'] = question_type
        return new_question

    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse regenerated question for '{word}': {e}")
        return None
    except openai.APIError as e:
        logger.error(f"OpenAI API error regenerating '{word}': {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error regenerating '{word}': {e}")
        return None


def get_unverified_questions(conn, limit: Optional[int] = None):
    """Get questions where ai_verified is explicitly FALSE."""
    cur = conn.cursor()

    query = """
        SELECT id, word, learning_language, native_language, question_type, question_data, version, created_at
        FROM review_questions
        WHERE ai_verified = FALSE
        ORDER BY created_at DESC
    """

    if limit:
        query += f" LIMIT {limit}"

    cur.execute(query)
    return cur.fetchall()


def update_question_in_db(conn, question_id: int, question_data: dict,
                           verified: bool, comment: Optional[str] = None,
                           increment_version: bool = False):
    """Update the question and verification status in database."""
    cur = conn.cursor()
    if increment_version:
        cur.execute("""
            UPDATE review_questions
            SET question_data = %s,
                ai_verified = %s,
                ai_verification_comment = %s,
                version = version + 1
            WHERE id = %s
        """, (json.dumps(question_data), verified, comment, question_id))
    else:
        cur.execute("""
            UPDATE review_questions
            SET question_data = %s,
                ai_verified = %s,
                ai_verification_comment = %s
            WHERE id = %s
        """, (json.dumps(question_data), verified, comment, question_id))
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
            'question_type',
            'attempt',
            'event_type',
            'result',
            'comment',
            'question_data'
        ])

        for event in events:
            writer.writerow([
                event['word'],
                event['question_type'],
                event['attempt'],
                event['event_type'],
                event['result'],
                event['comment'],
                event['question_data']
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

        logger.info(f"{label}: {len(words)} questions")
        if len(words) <= 10:
            logger.info(f"  Words: {', '.join(words)}")
        else:
            logger.info(f"  Words: {', '.join(words[:10])}... and {len(words) - 10} more")

    logger.info("")
    logger.info(f"Total questions processed: {total_words}")


def main():
    parser = argparse.ArgumentParser(description='Verify and fix AI-generated review questions')
    parser.add_argument('--limit', type=int, help='Maximum number of questions to process')
    parser.add_argument('--output', type=str, default='questions_verification_report.csv',
                        help='Output CSV file path')
    parser.add_argument('--dry-run', action='store_true',
                        help='Run verification without updating database')
    args = parser.parse_args()

    # Check for OpenAI API key
    if not os.environ.get('OPENAI_API_KEY'):
        logger.error("OPENAI_API_KEY environment variable is required")
        sys.exit(1)

    conn = get_db_connection()

    try:
        questions = get_unverified_questions(conn, args.limit)
        total = len(questions)

        if total == 0:
            logger.info("No unverified questions found")
            return

        logger.info(f"Found {total} unverified questions")

        all_events = []
        fix_counts = {}

        for i, q in enumerate(questions, 1):
            question_id = q['id']
            word = q['word']
            question_type = q['question_type']
            current_question = q['question_data']
            current_version = q.get('version', 1)

            # Skip recognition type (no LLM content to verify)
            if question_type == 'recognition':
                logger.info(f"[{i}/{total}] Skipping recognition question: {word}")
                continue

            logger.info(f"[{i}/{total}] Processing: {word} ({question_type}) v{current_version}")

            attempt = 0
            fixes_applied = 0
            verified = False
            all_issues_history = []

            while attempt < MAX_FIX_ATTEMPTS and not verified:
                attempt += 1

                is_valid, comment = verify_question_with_llm(word, question_type, current_question)

                all_events.append({
                    'word': word,
                    'question_type': question_type,
                    'attempt': attempt,
                    'event_type': 'verify',
                    'result': 'PASS' if is_valid else 'FAIL',
                    'comment': comment,
                    'question_data': json.dumps(current_question, ensure_ascii=False)
                })

                if is_valid:
                    verified = True
                    logger.info(f"  Attempt {attempt}: ✓ PASSED")
                else:
                    logger.warning(f"  Attempt {attempt}: ✗ FAILED - {comment[:80]}...")

                    if attempt < MAX_FIX_ATTEMPTS:
                        logger.info(f"  Attempt {attempt}: Regenerating question...")
                        new_question = regenerate_question_with_llm(
                            word, question_type, current_question, comment,
                            all_previous_issues=all_issues_history
                        )

                        all_issues_history.append(comment)

                        if new_question:
                            all_events.append({
                                'word': word,
                                'question_type': question_type,
                                'attempt': attempt,
                                'event_type': 'regenerate',
                                'result': 'SUCCESS',
                                'comment': f'Question regenerated (issues history: {len(all_issues_history)})',
                                'question_data': json.dumps(new_question, ensure_ascii=False)
                            })

                            current_question = new_question
                            fixes_applied += 1
                        else:
                            all_events.append({
                                'word': word,
                                'question_type': question_type,
                                'attempt': attempt,
                                'event_type': 'regenerate',
                                'result': 'FAIL',
                                'comment': 'Failed to regenerate question',
                                'question_data': ''
                            })
                            break

            if not args.dry_run:
                should_increment = fixes_applied > 0
                if verified:
                    update_question_in_db(
                        conn, question_id, current_question,
                        verified=True, comment=None,
                        increment_version=should_increment
                    )
                else:
                    update_question_in_db(
                        conn, question_id, current_question,
                        verified=False, comment=comment,
                        increment_version=should_increment
                    )

            # Track fix counts
            word_key = f"{word}:{question_type}"
            if verified:
                count_key = fixes_applied
            else:
                count_key = -1

            if count_key not in fix_counts:
                fix_counts[count_key] = []
            fix_counts[count_key].append(word_key)

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
