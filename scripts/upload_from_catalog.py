#!/usr/bin/env python3
"""
upload_from_catalog.py - Upload videos from catalog.csv based on quality scores

Reads catalog.csv and uploads filtered videos (by educational score) to backend:
  - Filters videos by minimum educational score threshold
  - Loads video data from /Volumes/databank/shortfilms/<video_name>/
  - Uploads to backend API with word-to-video mappings
  - Supports dry-run mode

Usage:
  # Dry run to see what would be uploaded
  python upload_from_catalog.py --min-educational-score 0.6 --dry-run

  # Upload to localhost
  python upload_from_catalog.py -e 0.6 --backend-url http://localhost:5001

  # Upload to production
  python upload_from_catalog.py -e 0.6 --backend-url https://kwafy.com
"""

import os
import sys
import csv
import json
import base64
import argparse
import logging
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime
import requests

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class CatalogUploader:
    """Upload videos from catalog.csv based on quality scores"""

    def __init__(self, catalog_path: str, videos_dir: str, backend_url: str,
                 min_educational: float, min_context: Optional[float] = None,
                 dry_run: bool = False):
        self.catalog_path = Path(catalog_path)
        self.videos_dir = Path(videos_dir)
        self.backend_url = backend_url.rstrip('/')
        self.min_educational = min_educational
        self.min_context = min_context
        self.dry_run = dry_run

        if not self.catalog_path.exists():
            raise ValueError(f"Catalog file not found: {self.catalog_path}")
        if not self.videos_dir.exists():
            raise ValueError(f"Videos directory not found: {self.videos_dir}")

        # Statistics
        self.stats = {
            'total_in_catalog': 0,
            'filtered': 0,
            'uploaded': 0,
            'skipped': 0,
            'errors': 0,
            'total_mappings': 0
        }

    def load_catalog(self) -> List[Dict]:
        """Load and filter catalog.csv by score thresholds"""
        logger.info(f"Loading catalog from: {self.catalog_path}")

        videos = []

        with open(self.catalog_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)

            for row in reader:
                self.stats['total_in_catalog'] += 1

                try:
                    edu_score = float(row['educational_score'])
                    ctx_score = float(row['context_score'])

                    # Apply filters
                    if edu_score < self.min_educational:
                        continue

                    if self.min_context is not None and ctx_score < self.min_context:
                        continue

                    # Parse linked words
                    linked_words = []
                    if row['linked_words'].strip():
                        linked_words = [w.strip() for w in row['linked_words'].split(',')]

                    videos.append({
                        'video_name': row['video_name'],
                        'educational_score': edu_score,
                        'context_score': ctx_score,
                        'audio_transcript': row['audio_transcript'],
                        'linked_words': linked_words
                    })

                except (ValueError, KeyError) as e:
                    logger.warning(f"Skipping malformed row: {e}")
                    continue

        self.stats['filtered'] = len(videos)

        logger.info(f"Loaded catalog: {self.stats['total_in_catalog']} total, "
                   f"{self.stats['filtered']} pass filters")

        return videos

    def load_video_data(self, video_name: str) -> Optional[Dict]:
        """Load all files for a video"""
        video_folder = self.videos_dir / video_name

        if not video_folder.exists():
            logger.warning(f"  Video folder not found: {video_name}")
            return None

        # Load MP4 (required)
        mp4_path = video_folder / f"{video_name}.mp4"
        if not mp4_path.exists():
            logger.warning(f"  MP4 not found: {video_name}")
            return None

        try:
            with open(mp4_path, 'rb') as f:
                mp4_bytes = f.read()
        except Exception as e:
            logger.error(f"  Failed to read MP4: {e}")
            return None

        # Load v3.json (required for quality scores)
        v3_path = video_folder / f"{video_name}.v3.json"
        if not v3_path.exists():
            logger.warning(f"  v3.json not found: {video_name}")
            return None

        try:
            with open(v3_path, 'r') as f:
                v3_data = json.load(f)
        except Exception as e:
            logger.error(f"  Failed to read v3.json: {e}")
            return None

        # Load v2.json (optional, for Whisper metadata)
        v2_data = None
        v2_path = video_folder / f"{video_name}.v2.json"
        if v2_path.exists():
            try:
                with open(v2_path, 'r') as f:
                    v2_data = json.load(f)
            except:
                pass

        # Load original .json (optional, for ClipCafe metadata)
        original_data = None
        json_path = video_folder / f"{video_name}.json"
        if json_path.exists():
            try:
                with open(json_path, 'r') as f:
                    original_data = json.load(f)
            except:
                pass

        return {
            'mp4_bytes': mp4_bytes,
            'v3_data': v3_data,
            'v2_data': v2_data,
            'original_data': original_data
        }

    def build_upload_payload(self, catalog_row: Dict, video_data: Dict) -> Dict:
        """Build API upload payload"""
        video_name = catalog_row['video_name']
        v3_data = video_data['v3_data']
        v2_data = video_data['v2_data']
        original_data = video_data['original_data']
        mp4_bytes = video_data['mp4_bytes']

        # Base64 encode MP4
        mp4_base64 = base64.b64encode(mp4_bytes).decode('utf-8')

        # Extract metadata
        assessment = v3_data.get('llm_assessment', {})
        illustrated_words = assessment.get('illustrated_words', catalog_row['linked_words'])

        # Build word mappings with relevance scores
        word_mappings = []
        for word in illustrated_words:
            if not word or not word.strip():
                continue

            word_mappings.append({
                'word': word.strip().lower(),
                'learning_language': 'en',
                'relevance_score': catalog_row['educational_score'],  # Use educational score as relevance
                'transcript_source': 'audio'
            })

        # Build ClipCafe metadata from original .json
        clipcafe_metadata = {}
        if original_data:
            clipcafe_metadata = {
                'clip_id': original_data.get('clipID'),
                'title': original_data.get('title'),
                'imdb': original_data.get('imdb'),
                'slug': original_data.get('slug'),
                'movie_title': original_data.get('movie_title'),
                'movie_year': original_data.get('movie_year'),
                'movie_plot': original_data.get('movie_plot'),
                'duration': original_data.get('duration'),
            }
        elif v3_data:
            clipcafe_metadata = {
                'clip_id': v3_data.get('clip_id'),
                'movie_title': v3_data.get('movie_title'),
                'movie_year': v3_data.get('movie_year'),
                'movie_plot': v3_data.get('movie_plot'),
                'imdb_id': v3_data.get('imdb_id'),
            }

        # Build payload
        payload = {
            'source_id': f"catalog_upload_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
            'videos': [{
                'slug': video_name,
                'name': video_name,
                'format': 'mp4',
                'video_data_base64': mp4_base64,
                'size_bytes': len(mp4_bytes),
                'transcript': original_data.get('transcript', '') if original_data else '',
                'audio_transcript': catalog_row['audio_transcript'],
                'audio_transcript_verified': True,
                'whisper_metadata': v2_data.get('whisper_metadata') if v2_data else None,
                'metadata': clipcafe_metadata,
                'word_mappings': word_mappings
            }]
        }

        return payload

    def upload_video(self, catalog_row: Dict) -> Optional[Dict]:
        """Upload a single video"""
        video_name = catalog_row['video_name']

        # Load video data
        video_data = self.load_video_data(video_name)
        if not video_data:
            self.stats['skipped'] += 1
            return None

        # Build payload
        payload = self.build_upload_payload(catalog_row, video_data)

        size_mb = len(video_data['mp4_bytes']) / (1024 * 1024)
        word_count = len(payload['videos'][0]['word_mappings'])

        if self.dry_run:
            logger.info(f"  [DRY RUN] Would upload: {video_name}")
            logger.info(f"    Educational: {catalog_row['educational_score']:.2f}, "
                       f"Context: {catalog_row['context_score']:.2f}")
            logger.info(f"    Words: {word_count} ({', '.join(catalog_row['linked_words'][:5])})")
            logger.info(f"    MP4 size: {size_mb:.2f} MB")
            return {'dry_run': True, 'video_name': video_name, 'word_count': word_count}

        # Upload to backend
        try:
            response = requests.post(
                f"{self.backend_url}/v3/admin/videos/batch-upload",
                json=payload,
                timeout=120
            )
            response.raise_for_status()

            result = response.json()
            video_result = result['results'][0]

            logger.info(f"  ✓ Uploaded {video_name}: video_id={video_result['video_id']}, "
                       f"mappings={video_result['mappings_created']}, size={size_mb:.2f}MB")

            self.stats['uploaded'] += 1
            self.stats['total_mappings'] += video_result['mappings_created']

            return video_result

        except Exception as e:
            logger.error(f"  ✗ Failed to upload {video_name}: {e}")
            self.stats['errors'] += 1
            return None

    def run(self, max_videos: Optional[int] = None):
        """Run the upload process"""
        start_time = datetime.now()

        logger.info(f"\n{'='*80}")
        logger.info(f"CATALOG VIDEO UPLOAD")
        logger.info(f"{'='*80}")
        logger.info(f"Catalog: {self.catalog_path}")
        logger.info(f"Videos Dir: {self.videos_dir}")
        logger.info(f"Backend URL: {self.backend_url}")
        logger.info(f"Min Educational Score: {self.min_educational}")
        if self.min_context:
            logger.info(f"Min Context Score: {self.min_context}")
        logger.info(f"Dry Run: {self.dry_run}")
        logger.info(f"{'='*80}\n")

        # Load and filter catalog
        videos = self.load_catalog()

        if not videos:
            logger.warning("No videos pass the filter criteria")
            return

        if max_videos:
            videos = videos[:max_videos]
            logger.info(f"Limited to {max_videos} videos for testing\n")

        # Show summary before upload
        logger.info(f"\n{'='*80}")
        logger.info(f"UPLOAD SUMMARY")
        logger.info(f"{'='*80}")
        logger.info(f"Total videos in catalog: {self.stats['total_in_catalog']}")
        logger.info(f"Videos passing filters: {self.stats['filtered']}")
        logger.info(f"Videos to process: {len(videos)}")

        if self.dry_run:
            logger.info(f"\n[DRY RUN MODE - No uploads will be performed]\n")

        logger.info(f"{'='*80}\n")

        # Upload each video
        for i, catalog_row in enumerate(videos, 1):
            logger.info(f"\n[{i}/{len(videos)}] Processing: {catalog_row['video_name']}")
            self.upload_video(catalog_row)

            # Progress update every 10 videos
            if i % 10 == 0:
                logger.info(f"\n--- Progress: {i}/{len(videos)} processed ---\n")

        # Final summary
        end_time = datetime.now()
        duration = end_time - start_time

        logger.info(f"\n{'='*80}")
        logger.info(f"FINAL SUMMARY")
        logger.info(f"{'='*80}")
        logger.info(f"Total in catalog: {self.stats['total_in_catalog']}")
        logger.info(f"Passed filters: {self.stats['filtered']}")
        logger.info(f"Processed: {len(videos)}")

        if self.dry_run:
            logger.info(f"[DRY RUN - No actual uploads performed]")
        else:
            logger.info(f"Uploaded: {self.stats['uploaded']}")
            logger.info(f"Skipped: {self.stats['skipped']}")
            logger.info(f"Errors: {self.stats['errors']}")
            logger.info(f"Total word mappings: {self.stats['total_mappings']}")

        logger.info(f"Duration: {duration}")
        logger.info(f"{'='*80}")


def main():
    parser = argparse.ArgumentParser(
        description='Upload videos from catalog.csv based on quality scores',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        '--catalog',
        default='/Volumes/databank/shortfilms/catalog.csv',
        help='Path to catalog.csv (default: /Volumes/databank/shortfilms/catalog.csv)'
    )

    parser.add_argument(
        '--videos-dir',
        default='/Volumes/databank/shortfilms',
        help='Directory containing video folders (default: /Volumes/databank/shortfilms)'
    )

    parser.add_argument(
        '--backend-url',
        default='http://localhost:5001',
        help='Backend API URL (default: http://localhost:5001)'
    )

    parser.add_argument(
        '-e', '--min-educational-score',
        type=float,
        default=0.6,
        help='Minimum educational score threshold (default: 0.6)'
    )

    parser.add_argument(
        '-c', '--min-context-score',
        type=float,
        default=None,
        help='Minimum context score threshold (optional)'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be uploaded without actually uploading'
    )

    parser.add_argument(
        '--max-videos',
        type=int,
        help='Maximum number of videos to upload (for testing)'
    )

    args = parser.parse_args()

    # Create uploader and run
    uploader = CatalogUploader(
        catalog_path=args.catalog,
        videos_dir=args.videos_dir,
        backend_url=args.backend_url,
        min_educational=args.min_educational_score,
        min_context=args.min_context_score,
        dry_run=args.dry_run
    )

    uploader.run(max_videos=args.max_videos)


if __name__ == '__main__':
    main()
