#!/usr/bin/env python3
"""
Pre-populate Review Questions Script

Generates all question types for vocabulary words to eliminate LLM delays during reviews.
Calls the backend batch-generate API to populate the review_questions cache.

Usage:
    # Generate for tianz_test words (615 words with videos)
    python3 prepopulate_questions.py --source tianz_test --backend-url http://localhost:5001

    # Generate for TOEFL words
    python3 prepopulate_questions.py --source toefl --max-words 100

    # Generate for specific words
    python3 prepopulate_questions.py --words apple,banana,cherry

    # Generate only specific question types
    python3 prepopulate_questions.py --source tianz_test --question-types mc_definition,video_mc

    # Production
    python3 prepopulate_questions.py --source tianz_test --backend-url https://kwafy.com
"""

import argparse
import requests
import json
import sys
import time
from typing import List, Optional

# Question types available
ALL_QUESTION_TYPES = [
    'mc_definition',       # Multiple choice from definition
    'mc_word',             # Multiple choice word from definition
    'fill_blank',          # Fill in the blank
    'pronounce_sentence',  # Pronunciation practice
    'video_mc',            # Video-based multiple choice
]


def prepopulate_questions(
    backend_url: str,
    source: Optional[str] = None,
    words: Optional[List[str]] = None,
    learning_lang: str = 'en',
    native_lang: str = 'zh',
    question_types: Optional[List[str]] = None,
    max_words: Optional[int] = None,
    skip_existing: bool = True
):
    """
    Call backend API to batch-generate questions.

    Args:
        backend_url: Backend API URL
        source: Test vocabulary source ('tianz_test', 'toefl', etc.)
        words: Specific words to process
        learning_lang: Language being learned
        native_lang: User's native language
        question_types: Question types to generate (defaults to all)
        max_words: Maximum number of words to process
        skip_existing: Skip words that already have all question types cached
    """
    endpoint = f"{backend_url}/v3/admin/questions/batch-generate"

    # Build payload
    payload = {
        'learning_language': learning_lang,
        'native_language': native_lang,
        'skip_existing': skip_existing
    }

    if source:
        payload['source'] = source
    elif words:
        payload['words'] = words
    else:
        print("❌ Error: Either --source or --words must be provided")
        sys.exit(1)

    if question_types:
        payload['question_types'] = question_types

    if max_words:
        payload['max_words'] = max_words

    # Display configuration
    print("=" * 80)
    print("📝 PRE-POPULATE REVIEW QUESTIONS")
    print("=" * 80)
    print(f"Backend URL: {backend_url}")
    print(f"Learning Language: {learning_lang}")
    print(f"Native Language: {native_lang}")
    if source:
        print(f"Source: {source}")
    if words:
        print(f"Words: {len(words)} words")
    if question_types:
        print(f"Question Types: {', '.join(question_types)}")
    else:
        print(f"Question Types: ALL ({', '.join(ALL_QUESTION_TYPES)})")
    if max_words:
        print(f"Max Words: {max_words}")
    print(f"Skip Existing: {skip_existing}")
    print("=" * 80)
    print()

    # Send request
    print(f"🚀 Sending request to {endpoint}...")
    start_time = time.time()

    try:
        response = requests.post(
            endpoint,
            json=payload,
            timeout=600  # 10 minutes timeout
        )
        response.raise_for_status()

        result = response.json()
        duration = time.time() - start_time

        # Display results
        print("\n" + "=" * 80)
        print("✅ BATCH GENERATION COMPLETE")
        print("=" * 80)

        if 'statistics' in result:
            stats = result['statistics']
            print(f"Total Words: {stats.get('total_words', 0)}")
            print(f"Total Questions Attempted: {stats.get('total_questions_attempted', 0)}")
            print(f"New Generations: {stats.get('new_generations', 0)}")
            print(f"Cache Hits: {stats.get('cache_hits', 0)}")
            print(f"Skipped Words: {stats.get('skipped_words', 0)}")
            print(f"Errors: {stats.get('errors', 0)}")
            print(f"Duration: {stats.get('duration_seconds', duration):.2f}s")
            print(f"Speed: {stats.get('questions_per_second', 0):.2f} questions/sec")

            if stats.get('errors', 0) > 0 and stats.get('error_details'):
                print("\n❌ Error Details:")
                for error in stats['error_details'][:10]:  # Show first 10 errors
                    print(f"  - {error}")
                if len(stats['error_details']) > 10:
                    print(f"  ... and {len(stats['error_details']) - 10} more errors")
        else:
            print(json.dumps(result, indent=2))

        print("=" * 80)
        print("\n✨ Done! Review sessions will now be instant for cached questions.")

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
        description='Pre-populate review questions to eliminate LLM delays',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate for tianz_test (615 words with videos)
  python3 prepopulate_questions.py --source tianz_test

  # Test with 10 words first
  python3 prepopulate_questions.py --source tianz_test --max-words 10

  # Generate for TOEFL words
  python3 prepopulate_questions.py --source toefl --max-words 100

  # Generate for specific words
  python3 prepopulate_questions.py --words apple,banana,cherry

  # Only generate video questions
  python3 prepopulate_questions.py --source tianz_test --question-types video_mc

  # Production
  python3 prepopulate_questions.py --source tianz_test --backend-url https://kwafy.com
        """
    )

    parser.add_argument(
        '--backend-url',
        default='http://localhost:5001',
        help='Backend API URL (default: http://localhost:5001)'
    )

    parser.add_argument(
        '--source',
        choices=['tianz_test', 'tianz', 'toefl', 'ielts',
                 'toefl_beginner', 'toefl_intermediate', 'toefl_advanced',
                 'ielts_beginner', 'ielts_intermediate', 'ielts_advanced'],
        help='Test vocabulary source'
    )

    parser.add_argument(
        '--words',
        help='Comma-separated list of specific words'
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
        '--question-types',
        help=f'Comma-separated question types. Available: {", ".join(ALL_QUESTION_TYPES)}'
    )

    parser.add_argument(
        '--max-words',
        type=int,
        help='Maximum number of words to process (for testing)'
    )

    parser.add_argument(
        '--no-skip-existing',
        action='store_true',
        help='Re-generate even if questions already exist (slower)'
    )

    args = parser.parse_args()

    # Validate that either source or words is provided
    if not args.source and not args.words:
        parser.error("Either --source or --words must be provided")

    # Parse words if provided
    words_list = None
    if args.words:
        words_list = [w.strip() for w in args.words.split(',') if w.strip()]

    # Parse question types if provided
    question_types_list = None
    if args.question_types:
        question_types_list = [qt.strip() for qt in args.question_types.split(',') if qt.strip()]
        # Validate question types
        invalid = [qt for qt in question_types_list if qt not in ALL_QUESTION_TYPES]
        if invalid:
            parser.error(f"Invalid question types: {', '.join(invalid)}")

    # Run prepopulation
    prepopulate_questions(
        backend_url=args.backend_url.rstrip('/'),
        source=args.source,
        words=words_list,
        learning_lang=args.learning_language,
        native_lang=args.native_language,
        question_types=question_types_list,
        max_words=args.max_words,
        skip_existing=not args.no_skip_existing
    )


if __name__ == '__main__':
    main()
