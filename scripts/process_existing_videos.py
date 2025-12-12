#!/usr/bin/env python3
"""
process_existing_videos.py - Process existing videos to create metadata_v2.json

Processes videos in old format (word_folder/*.mp4 + *.json) and generates:
- Extracts MP3 audio from MP4
- Gets Whisper audio transcript
- Creates metadata_v2.json with cleaner data and aggressive word matching

Usage:
  python process_existing_videos.py --input-dir /path/to/videos --max-videos 10
"""

import os
import sys
import json
import subprocess
import argparse
import logging
from pathlib import Path
from typing import List, Dict, Optional, Set
from datetime import datetime
from dotenv import load_dotenv
import requests

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class VideoProcessor:
    """Process existing videos and create metadata_v2.json"""

    def __init__(self, input_dir: str, openai_api_key: str, vocab_list: Optional[List[str]] = None):
        self.input_dir = Path(input_dir)
        self.openai_api_key = openai_api_key
        self.vocab_list = set(word.lower() for word in vocab_list) if vocab_list else None

        if not self.input_dir.exists():
            raise ValueError(f"Input directory does not exist: {self.input_dir}")

    def extract_mp3(self, mp4_path: Path) -> Optional[Path]:
        """Extract MP3 audio from MP4 video"""
        mp3_path = mp4_path.with_suffix('.mp3')

        # Skip if already exists
        if mp3_path.exists():
            logger.info(f"    MP3 already exists: {mp3_path.name}")
            return mp3_path

        try:
            logger.info(f"    Extracting MP3: {mp3_path.name}")
            subprocess.run([
                'ffmpeg',
                '-i', str(mp4_path),
                '-vn',  # No video
                '-acodec', 'libmp3lame',
                '-q:a', '2',  # High quality
                '-y',  # Overwrite
                str(mp3_path)
            ], check=True, capture_output=True, stderr=subprocess.DEVNULL)

            logger.info(f"    ✓ Extracted MP3")
            return mp3_path

        except (subprocess.CalledProcessError, UnicodeDecodeError) as e:
            logger.error(f"    ✗ Failed to extract MP3: {type(e).__name__}")
            return None
        except Exception as e:
            logger.error(f"    ✗ Unexpected error extracting MP3: {e}")
            return None

    def get_whisper_transcript(self, mp3_path: Path) -> Optional[Dict]:
        """Get audio transcript using OpenAI Whisper API"""
        try:
            logger.info(f"    Getting Whisper transcript...")
            
            with open(mp3_path, 'rb') as audio_file:
                response = requests.post(
                    'https://api.openai.com/v1/audio/transcriptions',
                    headers={'Authorization': f'Bearer {self.openai_api_key}'},
                    files={'file': audio_file},
                    data={
                        'model': 'whisper-1',
                        'response_format': 'verbose_json',
                        'timestamp_granularities[]': 'word'
                    },
                    timeout=60
                )
                response.raise_for_status()
                
            result = response.json()
            transcript_text = result.get('text', '').strip()
            duration = result.get('duration', 0)
            
            logger.info(f"    ✓ Whisper: {len(transcript_text.split())} words, {duration:.1f}s")
            
            return {
                'text': transcript_text,
                'duration': duration,
                'whisper_metadata': {
                    'task': result.get('task'),
                    'language': result.get('language'),
                }
            }
            
        except Exception as e:
            logger.error(f"    ✗ Whisper failed: {e}")
            return None

    def find_word_mappings(self, transcript: str, original_word: str) -> List[Dict]:
        """
        Find all vocabulary words in transcript (aggressive matching).

        If vocab_list is provided, looks for those words.
        Otherwise, extracts all words from transcript (3+ characters).
        """
        transcript_lower = transcript.lower()
        words_found = []

        if self.vocab_list:
            # Vocab list mode: find vocab words in transcript
            for vocab_word in self.vocab_list:
                # Check if word appears in transcript
                if vocab_word in transcript_lower:
                    # Calculate simple relevance score based on frequency
                    count = transcript_lower.count(vocab_word)
                    relevance_score = min(0.95, 0.7 + (count * 0.1))  # 0.7-0.95 based on frequency

                    words_found.append({
                        'word': vocab_word,
                        'learning_language': 'en',
                        'relevance_score': relevance_score,
                        'transcript_source': 'audio',
                        'occurrences': count
                    })
        else:
            # No vocab list: extract all meaningful words from transcript
            import re
            # Extract words (3+ characters, letters only)
            transcript_words = re.findall(r'\b[a-z]{3,}\b', transcript_lower)

            # Count occurrences
            word_counts = {}
            for word in transcript_words:
                word_counts[word] = word_counts.get(word, 0) + 1

            # Create mappings for unique words
            for word, count in word_counts.items():
                # Skip common words
                common_words = {'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'can',
                               'was', 'had', 'has', 'been', 'have', 'from', 'that', 'this', 'with'}
                if word in common_words:
                    continue

                relevance_score = min(0.95, 0.7 + (count * 0.1))
                words_found.append({
                    'word': word,
                    'learning_language': 'en',
                    'relevance_score': relevance_score,
                    'transcript_source': 'audio',
                    'occurrences': count
                })

        # Sort by relevance score (highest first)
        words_found.sort(key=lambda x: x['relevance_score'], reverse=True)

        logger.info(f"    ✓ Found {len(words_found)} vocabulary words in transcript")

        return words_found

    def process_video(self, word_folder: Path, mp4_file: Path) -> Optional[Dict]:
        """Process a single video and create metadata_v2.json"""
        video_name = mp4_file.stem
        json_file = mp4_file.with_suffix('.json')
        metadata_v2_path = mp4_file.with_name(f"{video_name}_metadata_v2.json")

        # Skip if metadata_v2 already exists
        if metadata_v2_path.exists():
            logger.info(f"  Skipping: {video_name} (metadata_v2 already exists)")
            return None

        logger.info(f"  Processing: {video_name}")

        # Load old metadata
        if not json_file.exists():
            logger.warning(f"    No JSON metadata found for {video_name}")
            return None
        
        with open(json_file, 'r') as f:
            old_metadata = json.load(f)
        
        # Extract MP3
        mp3_path = self.extract_mp3(mp4_file)
        if not mp3_path:
            return None
        
        # Get Whisper transcript
        whisper_data = self.get_whisper_transcript(mp3_path)
        if not whisper_data:
            return None
        
        # Find word mappings (aggressive)
        original_word = old_metadata.get('vocabulary_word', word_folder.name)
        word_mappings = self.find_word_mappings(
            whisper_data['text'],
            original_word
        )
        
        if not word_mappings:
            logger.warning(f"    No vocabulary words found in transcript")
            return None
        
        # Create metadata_v2
        metadata_v2 = {
            'video_name': video_name,
            'format': 'mp3',
            'movie_title': old_metadata.get('movie_title'),
            'movie_year': old_metadata.get('movie_year'),
            'audio_duration': whisper_data['duration'],
            'audio_transcript': whisper_data['text'],
            'audio_transcript_verified': True,
            'clip_metadata': {
                'clip_id': old_metadata.get('clip_id'),
                'duration_seconds': old_metadata.get('duration_seconds'),
                'imdb_id': old_metadata.get('imdb_id'),
                'movie_plot': old_metadata.get('movie_plot'),
            },
            'word_mappings': word_mappings,
            'processed_at': datetime.now().isoformat(),
            'source': 'process_existing_videos'
        }
        
        # Save metadata_v2.json
        metadata_v2_path = mp4_file.with_name(f"{video_name}_metadata_v2.json")
        with open(metadata_v2_path, 'w') as f:
            json.dump(metadata_v2, f, indent=2)
        
        logger.info(f"    ✓ Created metadata_v2.json with {len(word_mappings)} word mappings")
        
        return metadata_v2

    def process_word_folder(self, word_folder: Path) -> List[Dict]:
        """Process all videos in a word folder"""
        logger.info(f"\n{'='*60}")
        logger.info(f"Processing folder: {word_folder.name}")
        logger.info(f"{'='*60}")

        # Find all MP4 files
        mp4_files = sorted(word_folder.glob('*.mp4'))

        if not mp4_files:
            logger.warning(f"No MP4 files found in {word_folder.name}")
            return []

        logger.info(f"Found {len(mp4_files)} videos to process")
        
        results = []
        for i, mp4_file in enumerate(mp4_files, 1):
            logger.info(f"\n[{i}/{len(mp4_files)}]")
            result = self.process_video(word_folder, mp4_file)
            if result:
                results.append(result)
        
        logger.info(f"\nProcessed {len(results)}/{len(mp4_files)} videos successfully")
        return results

    def run(self):
        """Process videos from input directory"""
        logger.info(f"\n{'='*80}")
        logger.info(f"PROCESSING EXISTING VIDEOS")
        logger.info(f"{'='*80}")
        logger.info(f"Input Dir: {self.input_dir}")
        if self.vocab_list:
            logger.info(f"Vocabulary Mode: Filtering ({len(self.vocab_list)} words)")
        else:
            logger.info(f"Vocabulary Mode: Extract all words from transcript")
        logger.info(f"{'='*80}\n")

        # Check if input_dir contains MP4 files directly (single folder mode)
        # or subdirectories (multi-folder mode)
        mp4_files_in_root = list(self.input_dir.glob('*.mp4'))

        if mp4_files_in_root:
            # Single folder mode - process this folder directly
            logger.info(f"Single folder mode: processing {self.input_dir.name}")
            all_results = self.process_word_folder(self.input_dir)
            folders_processed = 1
        else:
            # Multi-folder mode - process subdirectories
            word_folders = [d for d in self.input_dir.iterdir() if d.is_dir() and not d.name.startswith('.')]
            word_folders = sorted(word_folders)

            logger.info(f"Found {len(word_folders)} word folders")

            all_results = []
            for folder in word_folders:
                results = self.process_word_folder(folder)
                all_results.extend(results)

            folders_processed = len(word_folders)

        # Summary
        logger.info(f"\n{'='*80}")
        logger.info(f"PROCESSING COMPLETED")
        logger.info(f"{'='*80}")
        logger.info(f"Folders Processed: {folders_processed}")
        logger.info(f"Videos Processed: {len(all_results)}")
        logger.info(f"{'='*80}")


def main():
    parser = argparse.ArgumentParser(
        description='Process existing videos to create metadata_v2.json',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        '--input-dir',
        required=True,
        help='Input directory containing word folders with videos'
    )

    parser.add_argument(
        '--vocab',
        help='Optional: Path to vocabulary CSV file for filtering (if not provided, extracts all words from transcript)'
    )

    args = parser.parse_args()

    # Load secrets
    env_path = Path(__file__).parent.parent / 'src' / '.env.secrets'
    if env_path.exists():
        load_dotenv(env_path)
        logger.info(f"Loaded secrets from {env_path}")
    else:
        logger.warning(f"Secrets file not found: {env_path}")

    openai_api_key = os.getenv('OPENAI_API_KEY')
    if not openai_api_key:
        logger.error("Missing OPENAI_API_KEY in .env.secrets")
        sys.exit(1)

    # Load vocabulary (optional)
    vocab_list = None
    if args.vocab:
        vocab_path = Path(args.vocab)
        if not vocab_path.exists():
            logger.error(f"Vocabulary file not found: {vocab_path}")
            sys.exit(1)

        vocab_list = []
        with open(vocab_path, 'r') as f:
            for line in f:
                word = line.strip()
                if word and not word.startswith('#'):
                    vocab_list.append(word)

        logger.info(f"Loaded {len(vocab_list)} vocabulary words")
    else:
        logger.info("No vocabulary file provided - will extract all words from transcripts")

    # Create processor and run
    processor = VideoProcessor(
        input_dir=args.input_dir,
        openai_api_key=openai_api_key,
        vocab_list=vocab_list
    )

    processor.run()


if __name__ == '__main__':
    main()
