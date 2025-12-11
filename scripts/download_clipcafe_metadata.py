#!/usr/bin/env python3
"""
ClipCafe Metadata Downloader
Downloads metadata JSON files for vocabulary words from clip.cafe API (no videos)
"""

import os
import sys
import csv
import time
import json
import requests
from pathlib import Path
from typing import List, Dict

# Configuration
API_KEY = "8fc3c43f44c930fc35e2d3b27e5396d7"
API_BASE_URL = "https://api.clip.cafe/"
OUTPUT_DIR = "/Volumes/databank/dogetionary-metadata"
MAX_METADATA_PER_WORD = 100  # Top 100 results

def load_words_from_csv(csv_path: str) -> List[str]:
    """Load words from CSV file"""
    csv_full_path = Path(csv_path)
    if not csv_full_path.is_absolute():
        csv_full_path = Path(__file__).parent / csv_path

    words = []
    with open(csv_full_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if row and row[0].strip():
                words.append(row[0].strip())

    print(f"Loaded {len(words)} words from {csv_path}")
    return words

def search_clips(word: str, max_results: int = 100) -> List[Dict]:
    """
    Search for video clips containing the word in transcript

    Filters applied:
    - Language: English only
    - Duration: 1-15 seconds
    - Sort: By views (popularity)

    Returns list of clip metadata
    """
    params = {
        'api_key': API_KEY,
        'transcript': word,
        'movie_language': 'English',
        'duration': '1-15',
        'sort': 'views',
        'order': 'desc',
        'size': max_results
    }

    try:
        print(f"  Searching for clips with word: '{word}'")
        response = requests.get(API_BASE_URL, params=params, timeout=30)
        response.raise_for_status()

        data = response.json()
        outer_hits = data.get('hits', {})
        inner_hits = outer_hits.get('hits', [])

        # Extract _source data from each hit
        clips = []
        for hit in inner_hits:
            source = hit.get('_source', {})
            if source:
                clips.append(source)

        # Filter and prioritize clips with subtitles
        clips_with_subs = []
        clips_without_subs = []

        for clip in clips:
            has_subtitles = bool(clip.get('subtitles') and clip.get('subtitles') != '{}')
            if has_subtitles:
                clips_with_subs.append(clip)
            else:
                clips_without_subs.append(clip)

        filtered_clips = clips_with_subs + clips_without_subs

        print(f"  Found {len(clips)} clips ({len(clips_with_subs)} with subtitles)")
        return filtered_clips

    except requests.exceptions.RequestException as e:
        print(f"  Error searching for '{word}': {e}")
        return []
    except json.JSONDecodeError as e:
        print(f"  Error parsing response for '{word}': {e}")
        return []

def save_metadata(word: str, index: int, clip_metadata: Dict, output_dir: Path) -> bool:
    """
    Save clip metadata to JSON file (no video download)
    """
    # Create word directory
    word_dir = output_dir / word.lower()
    word_dir.mkdir(parents=True, exist_ok=True)

    # Get slug for filename
    slug = clip_metadata.get('slug', f'clip_{index}')
    metadata_file = word_dir / f"{slug}_{index:03d}.json"

    # Skip if already exists
    if metadata_file.exists():
        print(f"    ✓ Already exists: {metadata_file.name}")
        return True

    try:
        # Create metadata structure
        metadata = {
            # Vocabulary word info
            "vocabulary_word": word,
            "result_index": index,

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

            # Download URL (available for 5 minutes after search)
            "download_url": clip_metadata.get('download', '')
        }

        # Write metadata to JSON file
        with open(metadata_file, 'w', encoding='utf-8') as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)

        print(f"    ✓ Saved metadata: {metadata_file.name}")
        return True

    except Exception as e:
        print(f"    ✗ Error saving metadata: {e}")
        if metadata_file.exists():
            metadata_file.unlink()
        return False

def process_word(word: str, output_dir: Path) -> Dict:
    """
    Process a single word: search and save metadata

    Returns dict with stats
    """
    print(f"\n{'='*60}")
    print(f"Processing word: {word}")
    print(f"{'='*60}")

    stats = {
        'word': word,
        'searched': 0,
        'saved': 0,
        'failed': 0
    }

    # Search for clips
    clips = search_clips(word, max_results=MAX_METADATA_PER_WORD)
    stats['searched'] = len(clips)

    if not clips:
        print(f"  No clips found for '{word}'")
        return stats

    # Save metadata for each clip
    for i, clip in enumerate(clips, 1):
        success = save_metadata(word, i, clip, output_dir)

        if success:
            stats['saved'] += 1
        else:
            stats['failed'] += 1

    return stats

def main():
    """Main execution"""
    # Parse command line arguments
    if len(sys.argv) < 2:
        print("Usage: python download_clipcafe_metadata.py <csv_file> [output_dir]")
        print("\nExample:")
        print("  python download_clipcafe_metadata.py ../resources/toefl-4889.csv")
        print("  python download_clipcafe_metadata.py words.csv /path/to/output")
        sys.exit(1)

    csv_file = sys.argv[1]
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(OUTPUT_DIR)

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"""
╔══════════════════════════════════════════════════════════╗
║      ClipCafe Metadata Downloader (No Videos)            ║
╚══════════════════════════════════════════════════════════╝

Configuration:
  - API Key: {API_KEY[:8]}...
  - Input CSV: {csv_file}
  - Output Directory: {output_dir.absolute()}
  - Max Results per Word: {MAX_METADATA_PER_WORD}

Filters Applied:
  ✓ Language: English only
  ✓ Duration: 1-15 seconds
  ✓ Sort: By popularity (views)
  ✓ Subtitles: Prioritized (when available)
    """)

    # Load words
    try:
        words = load_words_from_csv(csv_file)
    except FileNotFoundError:
        print(f"Error: Could not find CSV file: {csv_file}")
        sys.exit(1)

    print(f"\n🚀 Processing {len(words)} words")
    if len(words) > 10:
        print(f"First 10 words: {', '.join(words[:10])}...\n")
    else:
        print(f"Words: {', '.join(words)}\n")

    total_stats = {
        'words_processed': 0,
        'total_searched': 0,
        'total_saved': 0,
        'total_failed': 0
    }

    for i, word in enumerate(words, 1):
        stats = process_word(word, output_dir)

        total_stats['words_processed'] += 1
        total_stats['total_searched'] += stats['searched']
        total_stats['total_saved'] += stats['saved']
        total_stats['total_failed'] += stats['failed']

        # Progress indicator
        if i < len(words):
            print(f"\n📊 Progress: [{i}/{len(words)} words completed]")

    # Print summary
    print(f"\n{'='*60}")
    print(f"SUMMARY")
    print(f"{'='*60}")
    print(f"Words Processed:    {total_stats['words_processed']}")
    print(f"Clips Found:        {total_stats['total_searched']}")
    print(f"Metadata Files Saved: {total_stats['total_saved']}")
    print(f"Failed:             {total_stats['total_failed']}")
    print(f"\n✓ Metadata saved to: {output_dir.absolute()}")

    # Calculate storage used
    if output_dir.exists():
        import subprocess
        result = subprocess.run(['du', '-sh', str(output_dir)], capture_output=True, text=True)
        if result.returncode == 0:
            size = result.stdout.split()[0]
            print(f"💾 Total storage used: {size}")

if __name__ == "__main__":
    main()
