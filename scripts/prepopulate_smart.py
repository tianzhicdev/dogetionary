#!/usr/bin/env python3
"""
Smart Question Pre-population Script

Uses the smart batch endpoint to automatically process only incomplete words.
Just keep calling it with num_words until everything is complete!

Usage:
    # Process 10 incomplete words at a time (localhost)
    python3 prepopulate_smart.py --source tianz_test --num-words 10

    # Production
    python3 prepopulate_smart.py --source tianz_test --num-words 10 --backend-url https://kwafy.com/api

    # Continuous mode: keeps running until all complete
    python3 prepopulate_smart.py --source tianz_test --num-words 10 --continuous
"""

import argparse
import requests
import json
import sys
import time
from typing import Optional

def smart_prepopulate(
    backend_url: str,
    source: str,
    num_words: int = 10,
    learning_lang: str = 'en',
    native_lang: str = 'zh',
    strategy: str = 'missing_any',
    continuous: bool = False
):
    """
    Call smart batch generation endpoint.

    Args:
        backend_url: Backend API URL
        source: Test vocabulary source
        num_words: Number of incomplete words to process per batch
        learning_lang: Language being learned
        native_lang: User's native language
        strategy: Selection strategy
        continuous: Keep running until all complete
    """
    endpoint = f"{backend_url}/v3/admin/questions/smart-batch-generate"

    # Build payload
    payload = {
        'source': source,
        'num_words': num_words,
        'learning_language': learning_lang,
        'native_language': native_lang,
        'strategy': strategy
    }

    # Display configuration
    print("=" * 80)
    print("🧠 SMART QUESTION PRE-POPULATION")
    print("=" * 80)
    print(f"Backend URL: {backend_url}")
    print(f"Source: {source}")
    print(f"Batch Size: {num_words} words")
    print(f"Learning Language: {learning_lang}")
    print(f"Native Language: {native_lang}")
    print(f"Strategy: {strategy}")
    print(f"Continuous Mode: {continuous}")
    print("=" * 80)
    print()

    batch_number = 0
    total_definitions_created = 0
    total_questions_generated = 0
    total_words_processed = 0
    start_time = time.time()

    while True:
        batch_number += 1

        print(f"{'='*80}")
        print(f"📦 BATCH {batch_number}")
        print(f"{'='*80}")

        try:
            # Send request
            print(f"🚀 Requesting {num_words} incomplete words...")
            response = requests.post(
                endpoint,
                json=payload,
                timeout=600  # 10 minutes
            )
            response.raise_for_status()

            result = response.json()
            stats = result['statistics']
            next_incomplete = result['next_incomplete_count']
            progress = result['progress_percentage']
            total_words = result['total_words']

            # Display results
            print()
            print(f"✅ Batch {batch_number} Complete")
            print(f"─" * 80)
            print(f"Words Processed: {stats['words_processed']}")
            print(f"Definitions Created: {stats['definitions_created']}")
            print(f"Definitions Cached: {stats['definitions_cached']}")
            print(f"Questions Generated: {stats['questions_generated']}")
            print(f"Questions Cached: {stats['questions_cached']}")
            print(f"Errors: {stats['errors']}")
            print(f"Duration: {stats['duration_seconds']:.1f}s")
            print(f"Avg per word: {stats['avg_seconds_per_word']:.1f}s")
            print()
            print(f"📊 Overall Progress")
            print(f"─" * 80)
            print(f"Total Words: {total_words}")
            print(f"Completed: {total_words - next_incomplete} ({progress:.1f}%)")
            print(f"Remaining: {next_incomplete}")

            # Show question type breakdown if any were generated
            if stats['questions_generated'] > 0:
                print()
                print(f"Question Types Generated:")
                for qtype, counts in stats['by_question_type'].items():
                    if counts['generated'] > 0:
                        print(f"  - {qtype}: {counts['generated']}")

            # Track totals
            total_definitions_created += stats['definitions_created']
            total_questions_generated += stats['questions_generated']
            total_words_processed += stats['words_processed']

            # Check if complete
            if next_incomplete == 0:
                print()
                print("=" * 80)
                print("🎉 ALL WORDS COMPLETE!")
                print("=" * 80)
                elapsed = time.time() - start_time
                print(f"Total batches: {batch_number}")
                print(f"Total words processed: {total_words_processed}")
                print(f"Total definitions created: {total_definitions_created}")
                print(f"Total questions generated: {total_questions_generated}")
                print(f"Total time: {elapsed/60:.1f} minutes")
                print("=" * 80)
                break

            # If not continuous mode, exit after one batch
            if not continuous:
                print()
                print(f"💡 To continue, run this command again (or use --continuous)")
                print(f"   Remaining: {next_incomplete} words")
                break

            # Wait before next batch
            print()
            print(f"⏸️  Waiting 3 seconds before next batch...")
            print()
            time.sleep(3)

        except requests.exceptions.RequestException as e:
            print(f"\n❌ Error calling API: {e}")
            if hasattr(e, 'response') and e.response is not None:
                try:
                    error_detail = e.response.json()
                    print(f"Error details: {json.dumps(error_detail, indent=2)}")
                except:
                    print(f"Response text: {e.response.text}")
            sys.exit(1)

        except Exception as e:
            print(f"\n❌ Unexpected error: {e}")
            sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description='Smart question pre-population - processes only incomplete words',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process 10 incomplete words (localhost)
  python3 prepopulate_smart.py --source tianz_test --num-words 10

  # Production
  python3 prepopulate_smart.py --source tianz_test --num-words 10 --backend-url https://kwafy.com/api

  # Continuous mode (keeps running until all complete)
  python3 prepopulate_smart.py --source tianz_test --num-words 10 --continuous

  # Only process words missing definitions
  python3 prepopulate_smart.py --source tianz_test --num-words 10 --strategy missing_definition
        """
    )

    parser.add_argument(
        '--backend-url',
        default='http://localhost:5001',
        help='Backend API URL (default: http://localhost:5001)'
    )

    parser.add_argument(
        '--source',
        required=True,
        choices=['tianz_test', 'tianz', 'toefl', 'ielts',
                 'toefl_beginner', 'toefl_intermediate', 'toefl_advanced',
                 'ielts_beginner', 'ielts_intermediate', 'ielts_advanced'],
        help='Test vocabulary source (required)'
    )

    parser.add_argument(
        '--num-words',
        type=int,
        default=10,
        help='Number of incomplete words to process per batch (default: 10)'
    )

    parser.add_argument(
        '--learning-language',
        default='en',
        help='Learning language code (default: en)'
    )

    parser.add_argument(
        '--native-language',
        default='zh',
        help='Native language code (default: zh)'
    )

    parser.add_argument(
        '--strategy',
        default='missing_any',
        choices=['missing_any', 'missing_definition', 'missing_questions', 'missing_video_questions'],
        help='Word selection strategy (default: missing_any)'
    )

    parser.add_argument(
        '--continuous',
        action='store_true',
        help='Keep running batches until all words are complete'
    )

    args = parser.parse_args()

    # Run smart prepopulation
    smart_prepopulate(
        backend_url=args.backend_url.rstrip('/'),
        source=args.source,
        num_words=args.num_words,
        learning_lang=args.learning_language,
        native_lang=args.native_language,
        strategy=args.strategy,
        continuous=args.continuous
    )


if __name__ == '__main__':
    main()
