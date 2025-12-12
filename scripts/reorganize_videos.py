#!/usr/bin/env python3
"""
reorganize_videos.py - Reorganize video files into unified shortfilms structure

Consolidates videos from:
- /Volumes/databank/dogetionary-videos/
- /Volumes/databank/dogetionary-pipeline/
- /Volumes/databank/dogetionary-metadata/

Into:
- /Volumes/databank/shortfilms/<videoname>/
  - <videoname>.mp4
  - <videoname>.mp3
  - <videoname>.json
  - <videoname>.v2.json

Usage:
  python reorganize_videos.py --dry-run  # Preview what will be done
  python reorganize_videos.py            # Actually reorganize files
"""

import os
import sys
import json
import shutil
import logging
import argparse
from pathlib import Path
from typing import Dict, Set, Optional
from datetime import datetime
from collections import defaultdict

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class VideoOrganizer:
    """Reorganize videos from multiple sources into unified structure"""

    def __init__(self, output_dir: str, dry_run: bool = False):
        self.output_dir = Path(output_dir)
        self.dry_run = dry_run

        # Source directories
        self.videos_dir = Path('/Volumes/databank/dogetionary-videos')
        self.pipeline_dir = Path('/Volumes/databank/dogetionary-pipeline')
        self.metadata_dir = Path('/Volumes/databank/dogetionary-metadata')

        # Video index: {video_name: {mp4: path, mp3: path, json: path, json_v2: path}}
        self.video_index = defaultdict(lambda: {
            'mp4': None,
            'mp3': None,
            'json': None,
            'json_v2': None,
            'source_folder': None
        })

        # Statistics
        self.stats = {
            'folders_scanned': 0,
            'videos_found': 0,
            'mp4_files': 0,
            'mp3_files': 0,
            'json_files': 0,
            'json_v2_files': 0,
            'folders_created': 0,
            'files_copied': 0,
            'errors': 0
        }

    def scan_videos_directory(self):
        """Scan /Volumes/databank/dogetionary-videos/ (PRIMARY SOURCE)"""
        logger.info(f"\n{'='*80}")
        logger.info(f"SCANNING: {self.videos_dir}")
        logger.info(f"{'='*80}")

        if not self.videos_dir.exists():
            logger.warning(f"Directory does not exist: {self.videos_dir}")
            return

        # Iterate through word/phrase folders
        word_folders = [d for d in self.videos_dir.iterdir() if d.is_dir() and not d.name.startswith('.')]

        for word_folder in sorted(word_folders):
            self.stats['folders_scanned'] += 1

            # Find all MP4 files in this folder
            mp4_files = list(word_folder.glob('*.mp4'))

            for mp4_file in mp4_files:
                video_name = mp4_file.stem  # e.g., "video-name_08"

                # Register this video in the index
                self.video_index[video_name]['mp4'] = mp4_file
                self.video_index[video_name]['source_folder'] = word_folder.name
                self.stats['mp4_files'] += 1

                # Look for associated files
                mp3_file = mp4_file.with_suffix('.mp3')
                if mp3_file.exists():
                    self.video_index[video_name]['mp3'] = mp3_file
                    self.stats['mp3_files'] += 1

                json_file = mp4_file.with_suffix('.json')
                if json_file.exists():
                    self.video_index[video_name]['json'] = json_file
                    self.stats['json_files'] += 1

                json_v2_file = mp4_file.with_name(f"{video_name}_metadata_v2.json")
                if json_v2_file.exists():
                    self.video_index[video_name]['json_v2'] = json_v2_file
                    self.stats['json_v2_files'] += 1

            if self.stats['folders_scanned'] % 100 == 0:
                logger.info(f"Scanned {self.stats['folders_scanned']} folders, found {len(self.video_index)} unique videos...")

        logger.info(f"✓ Scanned {self.stats['folders_scanned']} folders")
        logger.info(f"✓ Found {len(self.video_index)} unique videos from dogetionary-videos")

    def scan_pipeline_directory(self):
        """Scan /Volumes/databank/dogetionary-pipeline/videos/"""
        logger.info(f"\n{'='*80}")
        logger.info(f"SCANNING: {self.pipeline_dir}/videos")
        logger.info(f"{'='*80}")

        pipeline_videos = self.pipeline_dir / 'videos'
        if not pipeline_videos.exists():
            logger.warning(f"Directory does not exist: {pipeline_videos}")
            return

        mp4_files = list(pipeline_videos.glob('*.mp4'))
        added = 0

        for mp4_file in mp4_files:
            # Pipeline uses slug without suffix, need to match with existing videos
            base_slug = mp4_file.stem  # e.g., "video-name" (no _08 suffix)

            # Try to find matching video in index
            # Look for videos that start with this slug
            matched = False
            for video_name in self.video_index.keys():
                # Check if video_name starts with base_slug and has _XX suffix pattern
                if video_name.startswith(base_slug):
                    # Check if it's actually the same video (has _\d+ suffix or exact match)
                    if video_name == base_slug or (len(video_name) > len(base_slug) and
                                                    video_name[len(base_slug):].startswith('_')):
                        # Only add if we don't already have MP4 for this video
                        if self.video_index[video_name]['mp4'] is None:
                            self.video_index[video_name]['mp4'] = mp4_file
                            added += 1
                        matched = True
                        break

            # If not matched, this is a new video (pipeline only)
            if not matched:
                self.video_index[base_slug]['mp4'] = mp4_file
                self.video_index[base_slug]['source_folder'] = 'pipeline'
                added += 1

        logger.info(f"✓ Added {added} videos from pipeline directory")
        logger.info(f"✓ Total unique videos: {len(self.video_index)}")

    def organize_videos(self):
        """Organize all videos into /shortfilms/ structure"""
        logger.info(f"\n{'='*80}")
        logger.info(f"ORGANIZING VIDEOS")
        logger.info(f"{'='*80}")
        logger.info(f"Output directory: {self.output_dir}")
        logger.info(f"Dry run: {self.dry_run}")
        logger.info(f"Total videos to organize: {len(self.video_index)}")
        logger.info(f"{'='*80}\n")

        if not self.dry_run and not self.output_dir.exists():
            logger.info(f"Creating output directory: {self.output_dir}")
            self.output_dir.mkdir(parents=True, exist_ok=True)

        # Process each video
        for i, (video_name, files) in enumerate(sorted(self.video_index.items()), 1):
            try:
                # Create video folder
                video_folder = self.output_dir / video_name

                if self.dry_run:
                    logger.info(f"[{i}/{len(self.video_index)}] WOULD CREATE: {video_folder.name}/")
                else:
                    if not video_folder.exists():
                        video_folder.mkdir(parents=True, exist_ok=True)
                        self.stats['folders_created'] += 1

                # Copy files
                files_to_copy = []

                if files['mp4']:
                    files_to_copy.append(('mp4', files['mp4'], video_folder / f"{video_name}.mp4"))

                if files['mp3']:
                    files_to_copy.append(('mp3', files['mp3'], video_folder / f"{video_name}.mp3"))

                if files['json']:
                    files_to_copy.append(('json', files['json'], video_folder / f"{video_name}.json"))

                if files['json_v2']:
                    files_to_copy.append(('v2', files['json_v2'], video_folder / f"{video_name}.v2.json"))

                # Copy each file
                for file_type, src_path, dst_path in files_to_copy:
                    if self.dry_run:
                        logger.info(f"  WOULD COPY {file_type.upper()}: {src_path.name} → {dst_path.name}")
                    else:
                        if not dst_path.exists():
                            shutil.copy2(src_path, dst_path)
                            self.stats['files_copied'] += 1

                # Progress reporting
                if i % 100 == 0:
                    logger.info(f"Progress: {i}/{len(self.video_index)} videos processed...")

            except Exception as e:
                logger.error(f"Error processing {video_name}: {e}")
                self.stats['errors'] += 1
                continue

        logger.info(f"\n✓ Organized {len(self.video_index)} videos")

    def verify_organization(self):
        """Verify the organization was successful"""
        logger.info(f"\n{'='*80}")
        logger.info(f"VERIFICATION")
        logger.info(f"{'='*80}")

        if self.dry_run:
            logger.info("Skipping verification (dry run mode)")
            return

        if not self.output_dir.exists():
            logger.warning("Output directory does not exist")
            return

        # Count folders and files in output
        folders = [d for d in self.output_dir.iterdir() if d.is_dir()]
        total_mp4 = sum(1 for d in folders for _ in d.glob('*.mp4'))
        total_mp3 = sum(1 for d in folders for _ in d.glob('*.mp3'))
        total_json = sum(1 for d in folders for _ in d.glob('*.json'))
        total_v2 = sum(1 for d in folders for _ in d.glob('*.v2.json'))

        logger.info(f"Output folders created: {len(folders)}")
        logger.info(f"MP4 files: {total_mp4}")
        logger.info(f"MP3 files: {total_mp3}")
        logger.info(f"JSON files: {total_json - total_v2}")  # Subtract v2 from total
        logger.info(f"V2 JSON files: {total_v2}")

    def print_summary(self):
        """Print final summary"""
        logger.info(f"\n{'='*80}")
        logger.info(f"SUMMARY")
        logger.info(f"{'='*80}")
        logger.info(f"Mode: {'DRY RUN' if self.dry_run else 'ACTUAL RUN'}")
        logger.info(f"")
        logger.info(f"Source Scanning:")
        logger.info(f"  Folders scanned: {self.stats['folders_scanned']}")
        logger.info(f"  Unique videos found: {len(self.video_index)}")
        logger.info(f"  MP4 files: {self.stats['mp4_files']}")
        logger.info(f"  MP3 files: {self.stats['mp3_files']}")
        logger.info(f"  JSON files: {self.stats['json_files']}")
        logger.info(f"  V2 JSON files: {self.stats['json_v2_files']}")
        logger.info(f"")
        if not self.dry_run:
            logger.info(f"Organization:")
            logger.info(f"  Folders created: {self.stats['folders_created']}")
            logger.info(f"  Files copied: {self.stats['files_copied']}")
            logger.info(f"  Errors: {self.stats['errors']}")
        logger.info(f"{'='*80}")

    def run(self):
        """Run the complete reorganization process"""
        start_time = datetime.now()

        logger.info(f"\n{'='*80}")
        logger.info(f"VIDEO REORGANIZATION")
        logger.info(f"{'='*80}")
        logger.info(f"Started at: {start_time}")
        logger.info(f"Mode: {'DRY RUN (no changes will be made)' if self.dry_run else 'LIVE RUN'}")
        logger.info(f"{'='*80}\n")

        # Step 1: Scan primary source (dogetionary-videos)
        self.scan_videos_directory()

        # Step 2: Scan pipeline videos (supplementary)
        self.scan_pipeline_directory()

        # Step 3: Organize videos
        self.organize_videos()

        # Step 4: Verify
        self.verify_organization()

        # Step 5: Summary
        self.print_summary()

        end_time = datetime.now()
        duration = end_time - start_time
        logger.info(f"\nCompleted in: {duration}")


def main():
    parser = argparse.ArgumentParser(
        description='Reorganize video files into unified shortfilms structure',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        '--output-dir',
        default='/Volumes/databank/shortfilms',
        help='Output directory for organized videos (default: /Volumes/databank/shortfilms)'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Preview what will be done without making changes'
    )

    args = parser.parse_args()

    # Create organizer and run
    organizer = VideoOrganizer(
        output_dir=args.output_dir,
        dry_run=args.dry_run
    )

    organizer.run()


if __name__ == '__main__':
    main()
