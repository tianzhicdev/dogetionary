#!/usr/bin/env python3
"""
ClipCafe Video Downloader
Downloads video clips for vocabulary words from clip.cafe API
"""

import os
import sys
import csv
import time
import json
import requests
from pathlib import Path
from typing import List, Dict, Optional

# Configuration
API_KEY = "8fc3c43f44c930fc35e2d3b27e5396d7"
API_BASE_URL = "https://api.clip.cafe/"
WORDS_CSV = "../resources/toefl-4889.csv"
OUTPUT_DIR = "/Volumes/databank/dogetionary-videos"
MAX_VIDEOS_PER_WORD = 10
REQUEST_DELAY = 6  # seconds between requests (10 requests/min limit)

# Create output directory
output_path = Path(OUTPUT_DIR) if OUTPUT_DIR.startswith('/') else Path(__file__).parent / OUTPUT_DIR
output_path.mkdir(parents=True, exist_ok=True)

def load_words(csv_path: str) -> List[str]:
    """Load words from CSV file"""
    csv_full_path = Path(__file__).parent / csv_path
    words = []

    with open(csv_full_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row and row[0].strip():
                words.append(row[0].strip())

    print(f"Loaded {len(words)} words from {csv_path}")
    return words

def search_clips(word: str, max_results: int = 10) -> List[Dict]:
    """
    Search for video clips containing the word in transcript

    Filters applied:
    - Language: English only
    - Duration: 1-15 seconds (to keep file sizes manageable)
    - Sort: By views (popularity)

    Returns list of clips with slug and download URL
    """
    params = {
        'api_key': API_KEY,
        'transcript': word,  # Search in transcript/captions
        'movie_language': 'English',  # English language only
        'duration': '1-15',  # 1-15 seconds clips (keeps files under ~10MB typically)
        'sort': 'views',  # Sort by most viewed (popularity)
        'order': 'desc',  # Descending order
        'size': max_results
    }

    try:
        print(f"  Searching for clips with word: '{word}'")
        response = requests.get(API_BASE_URL, params=params, timeout=30)
        response.raise_for_status()

        data = response.json()
        # Access nested hits array
        outer_hits = data.get('hits', {})
        inner_hits = outer_hits.get('hits', [])

        # Extract _source data from each hit
        clips = []
        for hit in inner_hits:
            source = hit.get('_source', {})
            if source:
                clips.append(source)

        # Filter for clips with subtitles (prefer those with embedded captions)
        clips_with_subs = []
        clips_without_subs = []

        for clip in clips:
            has_subtitles = bool(clip.get('subtitles') and clip.get('subtitles') != '{}')
            if has_subtitles:
                clips_with_subs.append(clip)
            else:
                clips_without_subs.append(clip)

        # Prioritize clips with subtitles, but include others if needed
        filtered_clips = clips_with_subs + clips_without_subs

        print(f"  Found {len(clips)} clips ({len(clips_with_subs)} with subtitles)")
        return filtered_clips

    except requests.exceptions.RequestException as e:
        print(f"  Error searching for '{word}': {e}")
        return []
    except json.JSONDecodeError as e:
        print(f"  Error parsing response for '{word}': {e}")
        return []

def download_video(download_url: str, slug: str, word: str, index: int, clip_metadata: Dict) -> bool:
    """
    Download a video clip and save metadata

    Note: download key is only valid for 5 minutes after search
    """
    # Create word directory
    word_dir = output_path / word.lower()
    word_dir.mkdir(exist_ok=True)

    # Output filenames
    output_file = word_dir / f"{slug}_{index:02d}.mp4"
    metadata_file = word_dir / f"{slug}_{index:02d}.json"

    # Skip if already downloaded
    if output_file.exists() and metadata_file.exists():
        print(f"    ✓ Already exists: {output_file.name}")
        return True

    try:
        print(f"    Downloading: {slug}")
        response = requests.get(download_url, stream=True, timeout=60)
        response.raise_for_status()

        # Check content type (accept video or octet-stream)
        content_type = response.headers.get('Content-Type', '')
        if 'video' not in content_type.lower() and 'octet-stream' not in content_type.lower():
            print(f"    ✗ Unexpected content type: {content_type}")
            return False

        # Write video file
        with open(output_file, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)

        file_size = output_file.stat().st_size / (1024 * 1024)  # MB

        # Save metadata JSON alongside video
        metadata = {
            # Vocabulary word info
            "vocabulary_word": word,
            "video_index": index,

            # Clip information
            "clip_id": clip_metadata.get('clipID'),
            "clip_title": clip_metadata.get('title'),
            "clip_slug": slug,
            "duration_seconds": clip_metadata.get('duration'),
            "resolution": clip_metadata.get('resolution'),
            "views": clip_metadata.get('views'),
            "likes": clip_metadata.get('likes'),
            "date_added": clip_metadata.get('date'),

            # Transcript and dialogue
            "transcript": clip_metadata.get('transcript', ''),
            "subtitles": clip_metadata.get('subtitles', '{}'),

            # Movie/Show information
            "movie_title": clip_metadata.get('movie_title'),
            "movie_year": clip_metadata.get('movie_year'),
            "movie_director": clip_metadata.get('movie_director'),
            "movie_writer": clip_metadata.get('movie_writer'),
            "movie_language": clip_metadata.get('movie_language'),
            "movie_country": clip_metadata.get('movie_country'),
            "movie_runtime": clip_metadata.get('movie_runtime'),
            "movie_rated": clip_metadata.get('movie_rated'),
            "movie_plot": clip_metadata.get('movie_plot'),
            "movie_imdb_score": clip_metadata.get('movie_imdbscore'),
            "movie_metascore": clip_metadata.get('movie_metascore'),
            "imdb_id": clip_metadata.get('imdb'),

            # Cast and characters
            "actors": clip_metadata.get('actors', ''),
            "characters": clip_metadata.get('characters', ''),

            # TV show specific
            "season": clip_metadata.get('season'),
            "episode": clip_metadata.get('episode'),

            # Thumbnails and images
            "movie_poster": clip_metadata.get('movie_poster'),
            "thumbnail_full": clip_metadata.get('thumbnail-full'),
            "thumbnail_16x9": clip_metadata.get('thumbnail-16x9'),

            # Download info
            "download_url": download_url,
            "file_size_mb": round(file_size, 2),
            "file_path": str(output_file.relative_to(output_path.parent))
        }

        # Write metadata to JSON file
        with open(metadata_file, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        print(f"    ✓ Downloaded: {output_file.name} ({file_size:.2f} MB) + metadata")
        return True

    except requests.exceptions.RequestException as e:
        print(f"    ✗ Download error: {e}")
        # Clean up partial download
        if output_file.exists():
            output_file.unlink()
        return False

def process_word(word: str) -> Dict:
    """
    Process a single word: search and download videos

    Returns dict with stats
    """
    print(f"\n{'='*60}")
    print(f"Processing word: {word}")
    print(f"{'='*60}")

    stats = {
        'word': word,
        'searched': 0,
        'downloaded': 0,
        'failed': 0
    }

    # Search for clips
    clips = search_clips(word, max_results=MAX_VIDEOS_PER_WORD)
    stats['searched'] = len(clips)

    if not clips:
        print(f"  No clips found for '{word}'")
        return stats

    # Download each clip
    for i, clip in enumerate(clips, 1):
        slug = clip.get('slug')
        download_url = clip.get('download')

        if not slug or not download_url:
            print(f"    ✗ Missing slug or download URL for clip {i}")
            stats['failed'] += 1
            continue

        success = download_video(download_url, slug, word, i, clip)

        if success:
            stats['downloaded'] += 1
        else:
            stats['failed'] += 1

        # Small delay between downloads to be respectful
        if i < len(clips):
            time.sleep(1)

    return stats

def main():
    """Main execution"""
    print(f"""
╔══════════════════════════════════════════════════════════╗
║         ClipCafe Video Downloader for TOEFL Words        ║
╚══════════════════════════════════════════════════════════╝

Configuration:
  - API Key: {API_KEY[:8]}...
  - Output Directory: {output_path.absolute()}
  - Max Videos per Word: {MAX_VIDEOS_PER_WORD}
  - Request Delay: {REQUEST_DELAY}s
  - Rate Limit: 10 requests/minute (PRO plan)

Filters Applied:
  ✓ Language: English only
  ✓ Duration: 1-15 seconds (keeps files under ~10MB)
  ✓ Sort: By popularity (views)
  ✓ Subtitles: Prioritized (when available)
    """)

    # Load words
    try:
        words = load_words(WORDS_CSV)
    except FileNotFoundError:
        print(f"Error: Could not find CSV file: {WORDS_CSV}")
        sys.exit(1)

    # Process ALL words
    test_words = words  # All 4879 words
    print(f"\n🚀 FULL MODE: Processing all {len(test_words)} words")
    print(f"First 10 words: {', '.join(test_words[:10])}...\n")

    total_stats = {
        'words_processed': 0,
        'total_searched': 0,
        'total_downloaded': 0,
        'total_failed': 0
    }

    for i, word in enumerate(test_words, 1):
        stats = process_word(word)

        total_stats['words_processed'] += 1
        total_stats['total_searched'] += stats['searched']
        total_stats['total_downloaded'] += stats['downloaded']
        total_stats['total_failed'] += stats['failed']

        # Rate limiting: wait between words to avoid hitting 10 req/min limit
        if i < len(test_words):
            print(f"\n⏳ Waiting {REQUEST_DELAY}s (rate limit)... [{i}/{len(test_words)} words completed]")
            time.sleep(REQUEST_DELAY)

    # Print summary
    print(f"\n{'='*60}")
    print(f"SUMMARY")
    print(f"{'='*60}")
    print(f"Words Processed:  {total_stats['words_processed']}")
    print(f"Clips Found:      {total_stats['total_searched']}")
    print(f"Videos Downloaded: {total_stats['total_downloaded']}")
    print(f"Failed:           {total_stats['total_failed']}")
    print(f"\n✓ Videos saved to: {output_path.absolute()}")

    # Calculate storage used
    if output_path.exists():
        import subprocess
        result = subprocess.run(['du', '-sh', str(output_path)], capture_output=True, text=True)
        if result.returncode == 0:
            size = result.stdout.split()[0]
            print(f"💾 Total storage used: {size}")

if __name__ == "__main__":
    main()
