#!/usr/bin/env python3
"""
upload_videos.py - Upload videos from directory structure to backend

Reads MP3 files and metadata.json from directory structure and uploads to backend:
  <input_dir>/<video_slug>/<video_slug>.mp3
  <input_dir>/<video_slug>/metadata.json

Usage:
  python upload_videos.py --dir <directory> --backend-url <url>
"""

import os
import sys
import json
import base64
import argparse
import logging
from pathlib import Path
from typing import List, Dict, Optional
import requests

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class VideoUploader:
    """Upload videos from directory structure to backend"""

    def __init__(self, input_dir: str, backend_url: str):
        self.input_dir = Path(input_dir)
        self.backend_url = backend_url.rstrip('/')

        if not self.input_dir.exists():
            raise ValueError(f"Input directory does not exist: {self.input_dir}")

        # State tracking
        self.uploaded_videos: List[str] = []
        self.failed_uploads: List[Dict] = []

    def discover_videos(self) -> List[Path]:
        """Discover all video directories in input directory"""
        video_dirs = []

        for item in self.input_dir.iterdir():
            if not item.is_dir():
                continue

            # Check if directory contains metadata.json
            metadata_file = item / "metadata.json"
            if not metadata_file.exists():
                logger.warning(f"Skipping {item.name} - no metadata.json found")
                continue

            # Check if directory contains MP3 file
            mp3_files = list(item.glob("*.mp3"))
            if not mp3_files:
                logger.warning(f"Skipping {item.name} - no MP3 file found")
                continue

            video_dirs.append(item)

        logger.info(f"Discovered {len(video_dirs)} video directories")
        return video_dirs

    def load_metadata(self, video_dir: Path) -> Optional[Dict]:
        """Load metadata.json from video directory"""
        metadata_file = video_dir / "metadata.json"

        try:
            with open(metadata_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load metadata from {metadata_file}: {e}")
            return None

    def load_mp3(self, video_dir: Path) -> Optional[bytes]:
        """Load MP3 file from video directory"""
        mp3_files = list(video_dir.glob("*.mp3"))

        if not mp3_files:
            logger.error(f"No MP3 file found in {video_dir}")
            return None

        mp3_file = mp3_files[0]

        try:
            with open(mp3_file, 'rb') as f:
                return f.read()
        except Exception as e:
            logger.error(f"Failed to load MP3 from {mp3_file}: {e}")
            return None

    def upload_video(self, video_dir: Path) -> Optional[Dict]:
        """Upload a single video to backend"""
        slug = video_dir.name

        logger.info(f"Uploading: {slug}")

        # Load metadata
        metadata = self.load_metadata(video_dir)
        if not metadata:
            logger.error(f"  ✗ Failed to load metadata for {slug}")
            self.failed_uploads.append({"slug": slug, "error": "Failed to load metadata"})
            return None

        # Load MP3
        mp3_bytes = self.load_mp3(video_dir)
        if not mp3_bytes:
            logger.error(f"  ✗ Failed to load MP3 for {slug}")
            self.failed_uploads.append({"slug": slug, "error": "Failed to load MP3"})
            return None

        # Convert MP3 to base64
        mp3_base64 = base64.b64encode(mp3_bytes).decode('utf-8')
        size_bytes = len(mp3_bytes)
        size_mb = size_bytes / (1024 * 1024)

        logger.info(f"  MP3 size: {size_mb:.2f} MB")

        # Prepare payload (convert MP3 metadata back to video upload format)
        payload = {
            "source_id": metadata.get('source_id'),
            "videos": [
                {
                    "slug": metadata.get('slug', slug),
                    "name": metadata.get('name', slug),
                    "format": "mp3",  # Upload as MP3
                    "video_data_base64": mp3_base64,
                    "size_bytes": size_bytes,
                    "transcript": metadata.get('transcript', ''),
                    "audio_transcript": metadata.get('audio_transcript'),
                    "audio_transcript_verified": metadata.get('audio_transcript_verified', False),
                    "whisper_metadata": metadata.get('whisper_metadata'),
                    "metadata": metadata.get('clipcafe_metadata', {}),
                    "word_mappings": metadata.get('word_mappings', [])
                }
            ]
        }

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

            logger.info(f"  ✓ Uploaded {slug}: video_id={video_result['video_id']}, "
                       f"mappings_created={video_result['mappings_created']}")

            self.uploaded_videos.append(slug)
            return video_result

        except Exception as e:
            logger.error(f"  ✗ Failed to upload {slug}: {e}")
            self.failed_uploads.append({"slug": slug, "error": str(e)})
            return None

    def run(self):
        """Run the upload process"""
        logger.info(f"\n{'='*80}")
        logger.info(f"STARTING VIDEO UPLOAD")
        logger.info(f"{'='*80}")
        logger.info(f"Input Dir: {self.input_dir}")
        logger.info(f"Backend URL: {self.backend_url}")
        logger.info(f"{'='*80}\n")

        # Discover videos
        video_dirs = self.discover_videos()

        if not video_dirs:
            logger.warning("No videos found to upload")
            return

        # Upload each video
        for i, video_dir in enumerate(video_dirs, 1):
            logger.info(f"\n[{i}/{len(video_dirs)}] Processing: {video_dir.name}")
            self.upload_video(video_dir)

        # Final Summary
        logger.info(f"\n{'='*80}")
        logger.info(f"UPLOAD COMPLETED")
        logger.info(f"{'='*80}")
        logger.info(f"Videos Uploaded: {len(self.uploaded_videos)}")
        logger.info(f"Failed Uploads: {len(self.failed_uploads)}")

        if self.uploaded_videos:
            logger.info(f"\nSuccessfully uploaded:")
            for slug in self.uploaded_videos:
                logger.info(f"  - {slug}")

        if self.failed_uploads:
            logger.info(f"\nFailed uploads:")
            for failure in self.failed_uploads:
                logger.info(f"  - {failure['slug']}: {failure['error']}")

        logger.info(f"{'='*80}")


def main():
    parser = argparse.ArgumentParser(
        description='Upload videos from directory structure to backend',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        '--dir',
        required=True,
        help='Input directory containing video subdirectories'
    )

    parser.add_argument(
        '--backend-url',
        required=True,
        help='Backend API URL (e.g., http://localhost:5001)'
    )

    args = parser.parse_args()

    # Create uploader and run
    uploader = VideoUploader(
        input_dir=args.dir,
        backend_url=args.backend_url
    )

    uploader.run()


if __name__ == '__main__':
    main()
