#!/usr/bin/env python3
"""
find_videos.py - CLI wrapper for VideoFinder service

This script provides command-line access to the VideoFinder service
for discovering and uploading educational videos for vocabulary words.

Stage 1: Search ClipCafe for video metadata
Stage 2: Candidate selection using metadata transcript + LLM
Stage 3: Audio verification using Whisper API + final LLM analysis
"""

import os
import sys
import argparse
import logging
from pathlib import Path
from dotenv import load_dotenv

# Add src directory to path for service imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from services.video_finder import VideoFinder

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


def main():
    parser = argparse.ArgumentParser(
        description='Find videos for vocabulary words and upload to backend',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    # Word source: either CSV file or bundle name (mutually exclusive)
    word_source = parser.add_mutually_exclusive_group(required=True)
    word_source.add_argument(
        '--csv',
        help='Path to CSV file with word list'
    )
    word_source.add_argument(
        '--bundle',
        help='Bundle name to fetch words from (e.g., toefl_beginner, ielts_advanced)'
    )

    parser.add_argument(
        '--storage-dir',
        default='/Volumes/databank/shortfilms',
        help='Base directory for caching (default: /Volumes/databank/shortfilms)'
    )

    parser.add_argument(
        '--backend-url',
        help='Backend API URL for uploading videos (e.g., http://localhost:5001 or https://kwafy.com/api)'
    )

    parser.add_argument(
        '--max-videos',
        type=int,
        default=100,
        help='Max videos to fetch per word (default: 100)'
    )

    parser.add_argument(
        '--education-min-score',
        type=float,
        default=0.6,
        help='Minimum education score - how well video illustrates word meaning (default: 0.6)'
    )

    parser.add_argument(
        '--context-min-score',
        type=float,
        default=0.6,
        help='Minimum context score - how well scene stands alone (default: 0.6)'
    )

    parser.add_argument(
        '--download-only',
        action='store_true',
        help='Download and process videos without uploading (saves to storage directory)'
    )

    args = parser.parse_args()

    # Load secrets from .env.secrets
    env_path = Path(__file__).parent.parent / 'src' / '.env.secrets'
    if env_path.exists():
        load_dotenv(env_path)
        logger.info(f"Loaded secrets from {env_path}")
    else:
        logger.warning(f"Secrets file not found: {env_path}")

    clipcafe_api_key = os.getenv('CLIPCAFE')
    openai_api_key = os.getenv('OPENAI_API_KEY')

    if not clipcafe_api_key or not openai_api_key:
        logger.error("Missing API keys in .env.secrets (CLIPCAFE, OPENAI_API_KEY)")
        sys.exit(1)

    # Create pipeline
    finder = VideoFinder(
        storage_dir=args.storage_dir,
        word_list_path=args.csv if args.csv else None,
        clipcafe_api_key=clipcafe_api_key,
        openai_api_key=openai_api_key,
        max_videos_per_word=args.max_videos,
        education_min_score=args.education_min_score,
        context_min_score=args.context_min_score,
        download_only=args.download_only,
        backend_url=args.backend_url
    )

    # Get words from either bundle or CSV
    if args.bundle:
        words = finder.fetch_bundle_words(args.bundle)
    else:
        words = finder.load_words()

    # Run pipeline with words
    finder.run(words=words, source_name=args.bundle or args.csv)


if __name__ == '__main__':
    main()
