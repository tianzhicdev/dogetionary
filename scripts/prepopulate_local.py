#!/usr/bin/env python3
"""
Local Question Pre-population Script

Runs directly inside the Docker container, bypassing HTTP/Cloudflare.
Reuses all existing Flask logic without timeout issues.

Usage:
    # Inside Docker container
    docker exec -it dogetionary-app-1 python3 /app/scripts/prepopulate_local.py \
        --source demo_bundle \
        --num-words 10 \
        --continuous

    # Or copy to container and run
    docker cp scripts/prepopulate_local.py dogetionary-app-1:/app/scripts/
    docker exec -it dogetionary-app-1 python3 /app/scripts/prepopulate_local.py --source demo_bundle --num-words 10
"""

import sys
import os
import argparse
import time
import logging

# Add src directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

# Import existing functions - reuse 100% of Flask logic
from handlers.admin_questions_smart import (
    find_incomplete_words,
    determine_question_types,
    count_incomplete_words,
    get_total_words_count,
    ALL_QUESTION_TYPES
)
from services.definition_service import generate_definition_with_llm
from services.question_generation_service import get_or_generate_question
from utils.database import db_fetch_one

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def process_batch(
    source: str,
    num_words: int,
    learning_lang: str,
    native_lang: str,
    strategy: str
):
    """
    Process a batch of incomplete words.
    This is the exact same logic as the Flask handler, just without HTTP layer.
    """
    start_time = time.time()

    # Find incomplete words
    logger.info(f"Finding {num_words} incomplete words from {source} using strategy '{strategy}'")
    incomplete_words = find_incomplete_words(
        source=source,
        num_words=num_words,
        learning_lang=learning_lang,
        native_lang=native_lang,
        strategy=strategy
    )

    if not incomplete_words:
        total_words = get_total_words_count(source, learning_lang)
        return {
            'words_requested': num_words,
            'words_processed': 0,
            'definitions_cached': 0,
            'definitions_created': 0,
            'questions_cached': 0,
            'questions_generated': 0,
            'errors': 0,
            'duration_seconds': 0,
            'next_incomplete_count': 0,
            'progress_percentage': 100.0,
            'total_words': total_words,
            'complete': True
        }

    # Statistics
    stats = {
        'words_requested': num_words,
        'words_processed': 0,
        'definitions_cached': 0,
        'definitions_created': 0,
        'questions_cached': 0,
        'questions_generated': 0,
        'by_question_type': {qt: {'cached': 0, 'generated': 0} for qt in ALL_QUESTION_TYPES},
        'errors': 0,
        'error_details': []
    }

    # Process each incomplete word
    for i, word_info in enumerate(incomplete_words, 1):
        word = word_info['word']
        has_definition = word_info['has_definition']
        has_video = word_info['has_video']

        try:
            logger.info(f"[{i}/{len(incomplete_words)}] Processing '{word}' "
                       f"(def={has_definition}, video={has_video})")

            # Step 1: Get or generate definition
            if not has_definition:
                definition_data = generate_definition_with_llm(word, learning_lang, native_lang)
                if not definition_data:
                    logger.error(f"Failed to generate definition for '{word}'")
                    stats['errors'] += 1
                    stats['error_details'].append(f"Definition generation failed for '{word}'")
                    continue
                stats['definitions_created'] += 1
                logger.info(f"  ✓ Created definition")
            else:
                definition = db_fetch_one("""
                    SELECT definition_data
                    FROM definitions
                    WHERE word = %s
                    AND learning_language = %s
                    AND native_language = %s
                """, (word, learning_lang, native_lang))
                definition_data = definition['definition_data']
                stats['definitions_cached'] += 1

            # Step 2: Determine which question types to generate
            question_types_to_generate = determine_question_types(
                word=word,
                learning_lang=learning_lang,
                native_lang=native_lang,
                has_video=has_video
            )

            # Step 3: Generate missing questions
            for question_type in question_types_to_generate:
                try:
                    # Check if already cached
                    existing = db_fetch_one("""
                        SELECT id FROM review_questions
                        WHERE word = %s
                        AND learning_language = %s
                        AND native_language = %s
                        AND question_type = %s
                    """, (word, learning_lang, native_lang, question_type))

                    if existing:
                        stats['questions_cached'] += 1
                        stats['by_question_type'][question_type]['cached'] += 1
                    else:
                        # Generate new question
                        question = get_or_generate_question(
                            word=word,
                            definition=definition_data,
                            learning_lang=learning_lang,
                            native_lang=native_lang,
                            question_type=question_type
                        )
                        stats['questions_generated'] += 1
                        stats['by_question_type'][question_type]['generated'] += 1
                        logger.info(f"  [{question_type}] ✓ generated")

                except Exception as e:
                    stats['errors'] += 1
                    error_msg = f"Question generation failed for '{word}' ({question_type}): {str(e)}"
                    stats['error_details'].append(error_msg)
                    logger.error(error_msg)
                    continue

            stats['words_processed'] += 1

            # Progress update every 5 words
            if i % 5 == 0:
                logger.info(f"Progress: {i}/{len(incomplete_words)} words, "
                           f"{stats['questions_generated']} new questions")

        except Exception as e:
            stats['errors'] += 1
            error_msg = f"Error processing '{word}': {str(e)}"
            stats['error_details'].append(error_msg)
            logger.error(error_msg, exc_info=True)
            continue

    # Calculate progress
    next_incomplete = count_incomplete_words(source, learning_lang, native_lang, strategy)
    total_words = get_total_words_count(source, learning_lang)
    progress = ((total_words - next_incomplete) / total_words * 100) if total_words > 0 else 0

    duration = time.time() - start_time
    stats['duration_seconds'] = round(duration, 2)
    stats['avg_seconds_per_word'] = round(duration / stats['words_processed'], 2) if stats['words_processed'] > 0 else 0
    stats['next_incomplete_count'] = next_incomplete
    stats['progress_percentage'] = round(progress, 2)
    stats['total_words'] = total_words
    stats['complete'] = (next_incomplete == 0)

    logger.info(f"Batch complete: {stats['words_processed']} words, "
               f"{stats['questions_generated']} new questions, "
               f"{next_incomplete} remaining")

    return stats


def main():
    parser = argparse.ArgumentParser(description='Local question pre-population (no HTTP/Cloudflare)')
    parser.add_argument('--source', required=True, help='Vocabulary source (demo_bundle, toefl, etc.)')
    parser.add_argument('--num-words', type=int, default=10, help='Number of words per batch')
    parser.add_argument('--learning-lang', default='en', help='Learning language')
    parser.add_argument('--native-lang', default='zh', help='Native language')
    parser.add_argument('--strategy', default='missing_any',
                       choices=['missing_any', 'missing_definition', 'missing_questions', 'missing_video_questions'],
                       help='Selection strategy')
    parser.add_argument('--continuous', action='store_true', help='Keep running until all complete')

    args = parser.parse_args()

    # Display configuration
    print("=" * 80)
    print("🧠 LOCAL QUESTION PRE-POPULATION")
    print("=" * 80)
    print(f"Source: {args.source}")
    print(f"Batch Size: {args.num_words} words")
    print(f"Learning Language: {args.learning_lang}")
    print(f"Native Language: {args.native_lang}")
    print(f"Strategy: {args.strategy}")
    print(f"Continuous Mode: {args.continuous}")
    print("=" * 80)
    print()

    batch_number = 0

    while True:
        batch_number += 1

        print(f"{'='*80}")
        print(f"📦 BATCH {batch_number}")
        print(f"{'='*80}")

        try:
            result = process_batch(
                source=args.source,
                num_words=args.num_words,
                learning_lang=args.learning_lang,
                native_lang=args.native_lang,
                strategy=args.strategy
            )

            # Display results
            print()
            print("✅ Batch Complete")
            print("─" * 80)
            print(f"Words Processed: {result['words_processed']}")
            print(f"Definitions Created: {result['definitions_created']}")
            print(f"Definitions Cached: {result['definitions_cached']}")
            print(f"Questions Generated: {result['questions_generated']}")
            print(f"Questions Cached: {result['questions_cached']}")
            print(f"Errors: {result['errors']}")
            print(f"Duration: {result['duration_seconds']}s")
            if result['words_processed'] > 0:
                print(f"Avg per word: {result['avg_seconds_per_word']}s")
            print()
            print("📊 Overall Progress")
            print("─" * 80)
            print(f"Total Words: {result['total_words']}")
            print(f"Completed: {result['total_words'] - result['next_incomplete_count']} ({result['progress_percentage']:.1f}%)")
            print(f"Remaining: {result['next_incomplete_count']}")
            print()

            # Show question type breakdown
            if result['questions_generated'] > 0:
                print("Question Types Generated:")
                for qt, counts in result['by_question_type'].items():
                    if counts['generated'] > 0:
                        print(f"  - {qt}: {counts['generated']}")
                print()

            # Check if complete
            if result['complete']:
                print("🎉 All words are complete!")
                break

            # Exit if not continuous
            if not args.continuous:
                break

            # Wait before next batch
            print("⏸️  Waiting 3 seconds before next batch...")
            print()
            time.sleep(3)

        except KeyboardInterrupt:
            print("\n\n⚠️  Interrupted by user")
            break
        except Exception as e:
            logger.error(f"Batch error: {e}", exc_info=True)
            if not args.continuous:
                sys.exit(1)
            print("⏸️  Waiting 5 seconds before retry...")
            time.sleep(5)


if __name__ == '__main__':
    main()
