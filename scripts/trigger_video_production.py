#!/usr/bin/env python3
"""
Video Production Automation Script

Processes words from vocabulary_merged.csv and triggers video production
for words that don't have any associated videos yet.

Usage:
    python trigger_video_production.py [options]

Examples:
    # Dry run to see what would be processed
    python trigger_video_production.py --dry-run

    # Process first 10 words
    python trigger_video_production.py --limit 10

    # Resume from previous run
    python trigger_video_production.py --resume

    # Custom API URL
    python trigger_video_production.py --api-url http://localhost:5001
"""

import requests
import json
import time
import logging
import argparse
import csv
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class VideoProductionManager:
    """Manages automated video production for vocabulary words"""

    def __init__(
        self,
        api_url: str = "http://localhost:5001",
        words_file: str = "/Users/biubiu/projects/dogetionary/resources/words/vocabulary_merged.csv",
        learning_language: str = "en",
        delay_seconds: int = 2,
        max_retries: int = 3,
        checkpoint_interval: int = 10,
        progress_file: str = "video_production_progress.json",
        dry_run: bool = False,
        max_concurrent_processing: int = 1  # Maximum words being processed simultaneously
    ):
        self.api_url = api_url.rstrip('/')
        self.words_file = Path(words_file)
        self.learning_language = learning_language
        self.delay_seconds = delay_seconds
        self.max_retries = max_retries
        self.checkpoint_interval = checkpoint_interval
        self.progress_file = Path(progress_file)
        self.dry_run = dry_run
        self.max_concurrent_processing = max_concurrent_processing

        # Statistics tracking
        self.stats = {
            'total_words': 0,
            'processed': 0,
            'has_videos': 0,
            'triggered': 0,
            'failed': 0,
            'skipped': 0,
            'start_time': None,
            'end_time': None
        }

        # Tracking lists
        self.triggered_words = []
        self.failed_words = []
        self.words_with_videos = []

    def load_words(self) -> List[str]:
        """Load words from vocabulary CSV file"""
        logger.info(f"Loading words from {self.words_file}")

        if not self.words_file.exists():
            raise FileNotFoundError(f"Words file not found: {self.words_file}")

        words = []
        with open(self.words_file, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                word = row.get('word', '').strip().lower()
                if word:
                    words.append(word)

        logger.info(f"Loaded {len(words)} words from vocabulary file")
        self.stats['total_words'] = len(words)
        return words

    def load_progress(self) -> Optional[Dict]:
        """Load progress from checkpoint file"""
        if not self.progress_file.exists():
            return None

        try:
            with open(self.progress_file, 'r') as f:
                progress = json.load(f)
            logger.info(f"Loaded progress: last processed word index = {progress.get('last_index', 0)}")
            return progress
        except Exception as e:
            logger.warning(f"Failed to load progress file: {e}")
            return None

    def save_progress(self, current_index: int):
        """Save progress checkpoint"""
        progress = {
            'last_index': current_index,
            'timestamp': datetime.now().isoformat(),
            'stats': self.stats,
            'triggered_words': self.triggered_words,
            'failed_words': self.failed_words,
            'words_with_videos': self.words_with_videos
        }

        with open(self.progress_file, 'w') as f:
            json.dump(progress, indent=2, fp=f)

        logger.debug(f"Progress saved at index {current_index}")

    def check_word_has_videos(self, word: str) -> Tuple[bool, int]:
        """
        Check if a word has associated videos.

        Returns:
            Tuple of (has_videos, video_count)
        """
        url = f"{self.api_url}/v3/api/check-word-videos"
        params = {
            'word': word,
            'lang': self.learning_language
        }

        for attempt in range(self.max_retries):
            try:
                response = requests.get(url, params=params, timeout=10)

                # Handle rate limiting with exponential backoff
                if response.status_code == 429:
                    retry_after = int(response.headers.get('Retry-After', 2 ** attempt))
                    logger.warning(f"Rate limited (429) for word '{word}'. Waiting {retry_after}s...")
                    time.sleep(retry_after)
                    continue

                response.raise_for_status()
                data = response.json()

                has_videos = data.get('has_videos', False)
                video_count = data.get('video_count', 0)

                return has_videos, video_count

            except requests.exceptions.RequestException as e:
                if attempt < self.max_retries - 1:
                    wait_time = 2 ** attempt
                    logger.warning(f"Error checking word '{word}' (attempt {attempt + 1}/{self.max_retries}): {e}. Retrying in {wait_time}s...")
                    time.sleep(wait_time)
                else:
                    logger.error(f"Failed to check word '{word}' after {self.max_retries} attempts: {e}")
                    raise

        return False, 0

    def trigger_video_search(self, word: str) -> bool:
        """
        Trigger video production for a word.

        Returns:
            True if successful, False otherwise
        """
        if self.dry_run:
            logger.info(f"[DRY RUN] Would trigger video search for: {word}")
            return True

        url = f"{self.api_url}/v3/api/trigger-video-search"
        payload = {
            'word': word,
            'learning_language': self.learning_language
        }

        for attempt in range(self.max_retries):
            try:
                response = requests.post(url, json=payload, timeout=10)

                # Handle rate limiting with exponential backoff
                if response.status_code == 429:
                    retry_after = int(response.headers.get('Retry-After', 2 ** attempt))
                    logger.warning(f"Rate limited (429) triggering video for '{word}'. Waiting {retry_after}s...")
                    time.sleep(retry_after)
                    continue

                response.raise_for_status()
                data = response.json()

                if data.get('status') == 'triggered':
                    logger.info(f"✓ Triggered video search for: {word}")
                    return True
                else:
                    logger.warning(f"Unexpected response for '{word}': {data}")
                    return False

            except requests.exceptions.RequestException as e:
                if attempt < self.max_retries - 1:
                    wait_time = 2 ** attempt
                    logger.warning(f"Error triggering video for '{word}' (attempt {attempt + 1}/{self.max_retries}): {e}. Retrying in {wait_time}s...")
                    time.sleep(wait_time)
                else:
                    logger.error(f"Failed to trigger video for '{word}' after {self.max_retries} attempts: {e}")
                    return False

        return False

    def process_words(self, words: List[str], start_index: int = 0, limit: Optional[int] = None):
        """Process words and trigger video production for those without videos"""
        self.stats['start_time'] = datetime.now().isoformat()

        # Apply limit if specified
        end_index = len(words) if limit is None else min(start_index + limit, len(words))
        words_to_process = words[start_index:end_index]

        logger.info(f"\n{'='*80}")
        logger.info(f"Starting video production workflow")
        logger.info(f"{'='*80}")
        logger.info(f"Processing {len(words_to_process)} words (index {start_index} to {end_index-1})")
        logger.info(f"API URL: {self.api_url}")
        logger.info(f"Language: {self.learning_language}")
        logger.info(f"Delay between requests: {self.delay_seconds}s")
        logger.info(f"Dry run: {self.dry_run}")
        logger.info(f"{'='*80}\n")

        # Confirmation prompt (skip in dry run)
        if not self.dry_run:
            response = input(f"Ready to process {len(words_to_process)} words. Continue? (y/n): ")
            if response.lower() != 'y':
                logger.info("Aborted by user")
                return

        # Process each word
        for i, word in enumerate(words_to_process):
            actual_index = start_index + i
            self.stats['processed'] += 1
            triggered_this_word = False

            try:
                # Check if word has videos
                logger.info(f"[{actual_index+1}/{end_index}] Checking word: '{word}'")
                has_videos, video_count = self.check_word_has_videos(word)

                if has_videos:
                    logger.info(f"  → Word '{word}' already has {video_count} video(s) (skipped)")
                    self.stats['has_videos'] += 1
                    self.words_with_videos.append(word)
                else:
                    logger.info(f"  → Word '{word}' has no videos (triggering production)")

                    # Trigger video production
                    success = self.trigger_video_search(word)

                    if success:
                        self.stats['triggered'] += 1
                        self.triggered_words.append(word)
                        triggered_this_word = True
                    else:
                        self.stats['failed'] += 1
                        self.failed_words.append(word)

            except Exception as e:
                logger.error(f"  ✗ Failed to process word '{word}': {e}")
                self.stats['failed'] += 1
                self.failed_words.append(word)

            # Save checkpoint
            if (i + 1) % self.checkpoint_interval == 0:
                self.save_progress(actual_index)
                logger.info(f"\n  Checkpoint: {self.stats['processed']} words processed, "
                          f"{self.stats['triggered']} triggered, {self.stats['has_videos']} skipped\n")

            # Rate limiting delay - only after triggering production (not for skipped words)
            if triggered_this_word and i < len(words_to_process) - 1:
                time.sleep(self.delay_seconds)

        # Final checkpoint
        self.save_progress(end_index - 1)

        # Mark completion
        self.stats['end_time'] = datetime.now().isoformat()

        # Generate report
        self.generate_report()

    def generate_report(self):
        """Generate final summary report"""
        logger.info(f"\n{'='*80}")
        logger.info(f"VIDEO PRODUCTION SUMMARY")
        logger.info(f"{'='*80}")
        logger.info(f"Total words processed: {self.stats['processed']}")
        logger.info(f"Words with existing videos (skipped): {self.stats['has_videos']}")
        logger.info(f"Words triggered for production: {self.stats['triggered']}")
        logger.info(f"Failed words: {self.stats['failed']}")

        if self.stats['start_time'] and self.stats['end_time']:
            start = datetime.fromisoformat(self.stats['start_time'])
            end = datetime.fromisoformat(self.stats['end_time'])
            duration = (end - start).total_seconds() / 60
            logger.info(f"Duration: {duration:.2f} minutes")

        logger.info(f"{'='*80}\n")

        # Save detailed report
        report = {
            'summary': self.stats,
            'triggered_words': self.triggered_words,
            'words_with_videos': self.words_with_videos,
            'failed_words': self.failed_words
        }

        report_file = Path('video_production_report.json')
        with open(report_file, 'w') as f:
            json.dump(report, indent=2, fp=f)

        logger.info(f"Detailed report saved to: {report_file}")

        # Save CSV for analysis
        csv_file = Path('video_production_report.csv')
        with open(csv_file, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['word', 'action', 'status'])

            for word in self.words_with_videos:
                writer.writerow([word, 'skipped', 'has_videos'])

            for word in self.triggered_words:
                writer.writerow([word, 'triggered', 'success'])

            for word in self.failed_words:
                writer.writerow([word, 'triggered', 'failed'])

        logger.info(f"CSV report saved to: {csv_file}\n")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Trigger video production for words without videos',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run to see what would be processed
  python trigger_video_production.py --dry-run

  # Process first 10 words
  python trigger_video_production.py --limit 10

  # Resume from previous run
  python trigger_video_production.py --resume

  # Custom API URL
  python trigger_video_production.py --api-url http://localhost:5001
        """
    )

    parser.add_argument(
        '--api-url',
        default='http://localhost:5001',
        help='API base URL (default: http://localhost:5001)'
    )

    parser.add_argument(
        '--words-file',
        default='/Users/biubiu/projects/dogetionary/resources/words/vocabulary_merged.csv',
        help='Path to vocabulary CSV file'
    )

    parser.add_argument(
        '--language',
        default='en',
        help='Learning language code (default: en)'
    )

    parser.add_argument(
        '--delay',
        type=int,
        default=2,
        help='Delay in seconds between API calls (default: 2, recommended: 5-10 for production)'
    )

    parser.add_argument(
        '--interval',
        type=int,
        help='Alias for --delay (overrides --delay if provided)'
    )

    parser.add_argument(
        '--limit',
        type=int,
        help='Limit number of words to process'
    )

    parser.add_argument(
        '--resume',
        action='store_true',
        help='Resume from last checkpoint'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Simulate without actually triggering video production'
    )

    parser.add_argument(
        '--checkpoint-interval',
        type=int,
        default=10,
        help='Save progress every N words (default: 10)'
    )

    parser.add_argument(
        '--max-retries',
        type=int,
        default=3,
        help='Maximum retries for failed API calls (default: 3)'
    )

    args = parser.parse_args()

    # Use interval if provided, otherwise use delay
    delay = args.interval if args.interval is not None else args.delay

    # Create manager
    manager = VideoProductionManager(
        api_url=args.api_url,
        words_file=args.words_file,
        learning_language=args.language,
        delay_seconds=delay,
        max_retries=args.max_retries,
        checkpoint_interval=args.checkpoint_interval,
        dry_run=args.dry_run,
        max_concurrent_processing=1
    )

    try:
        # Load words
        words = manager.load_words()

        # Determine starting index
        start_index = 0
        if args.resume:
            progress = manager.load_progress()
            if progress:
                start_index = progress.get('last_index', 0) + 1
                logger.info(f"Resuming from word index {start_index}")

        # Process words
        manager.process_words(words, start_index=start_index, limit=args.limit)

    except KeyboardInterrupt:
        logger.info("\n\nInterrupted by user. Progress has been saved.")
        logger.info("Run with --resume to continue from where you left off.\n")
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        return 1

    return 0


if __name__ == '__main__':
    exit(main())
