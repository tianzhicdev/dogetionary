#!/usr/bin/env python3
"""
Import videos from a directory into the database.

Usage:
    python scripts/import_videos_to_db.py --directory /path/to/videos [--batch-size 10] [--dry-run]

Example:
    python scripts/import_videos_to_db.py --directory /Volumes/databank/dogetionary-videos --batch-size 10
"""

import argparse
import os
import sys
from pathlib import Path
from typing import List, Dict

# Add parent directory to path to import modules
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from video_utils import (
    check_ffprobe_installed,
    get_video_info,
    format_file_size,
    format_duration
)

try:
    from tqdm import tqdm
except ImportError:
    print("Warning: tqdm not installed. Install with: pip install tqdm")
    # Fallback implementation
    class tqdm:
        def __init__(self, iterable=None, **kwargs):
            self.iterable = iterable
            self.total = kwargs.get('total', 0)
            self.current = 0

        def __iter__(self):
            for item in self.iterable:
                yield item
                self.current += 1

        def __enter__(self):
            return self

        def __exit__(self, *args):
            pass

        def update(self, n=1):
            self.current += n

        def set_description(self, desc):
            pass


# Supported video formats
SUPPORTED_FORMATS = {'.mp4', '.mov', '.webm', '.avi', '.mkv'}


def find_video_files(directory: str) -> List[str]:
    """
    Recursively find all video files in the directory.

    Args:
        directory: Root directory to scan

    Returns:
        list: Paths to all video files found
    """
    video_files = []

    for root, dirs, files in os.walk(directory):
        for file in files:
            if Path(file).suffix.lower() in SUPPORTED_FORMATS:
                video_files.append(os.path.join(root, file))

    return sorted(video_files)


def import_video_to_db(cursor, video_info: Dict, dry_run: bool = False) -> bool:
    """
    Import a single video into the database.

    Args:
        cursor: Database cursor
        video_info: Video information dictionary from get_video_info()
        dry_run: If True, don't actually insert into database

    Returns:
        bool: True if successful, False otherwise
    """
    if dry_run:
        return True

    try:
        import psycopg2.extras

        cursor.execute("""
            INSERT INTO videos (name, format, video_data, transcript, metadata)
            VALUES (%(name)s, %(format)s, %(video_data)s, %(transcript)s, %(metadata)s)
            ON CONFLICT (name, format) DO UPDATE
            SET video_data = EXCLUDED.video_data,
                transcript = EXCLUDED.transcript,
                metadata = EXCLUDED.metadata,
                updated_at = NOW()
        """, {
            'name': video_info['name'],
            'format': video_info['format'],
            'video_data': video_info['video_data'],
            'transcript': video_info['transcript'],
            'metadata': psycopg2.extras.Json(video_info['metadata'])
        })
        return True
    except Exception as e:
        print(f"\nError inserting video: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description='Import videos from directory into database',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Import all videos from directory
  python scripts/import_videos_to_db.py --directory /Volumes/databank/dogetionary-videos

  # Dry run to see what would be imported
  python scripts/import_videos_to_db.py --directory /path/to/videos --dry-run

  # Import with smaller batch size
  python scripts/import_videos_to_db.py --directory /path/to/videos --batch-size 5
        """
    )

    parser.add_argument(
        '--directory',
        required=True,
        help='Directory containing video files to import'
    )

    parser.add_argument(
        '--batch-size',
        type=int,
        default=10,
        help='Number of videos to process in each transaction (default: 10)'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Scan and process videos without inserting into database'
    )

    parser.add_argument(
        '--db-host',
        default='localhost',
        help='Database host (default: localhost)'
    )

    parser.add_argument(
        '--db-port',
        type=int,
        default=5432,
        help='Database port (default: 5432)'
    )

    parser.add_argument(
        '--db-name',
        default='dogetionary',
        help='Database name (default: dogetionary)'
    )

    parser.add_argument(
        '--db-user',
        default='postgres',
        help='Database user (default: postgres)'
    )

    parser.add_argument(
        '--db-password',
        default='postgres',
        help='Database password (default: postgres)'
    )

    args = parser.parse_args()

    # Validate directory
    if not os.path.isdir(args.directory):
        print(f"Error: Directory not found: {args.directory}")
        sys.exit(1)

    # Check ffprobe installation
    if not check_ffprobe_installed():
        print("Error: ffprobe is not installed.")
        print("Install ffmpeg:")
        print("  macOS: brew install ffmpeg")
        print("  Ubuntu: sudo apt-get install ffmpeg")
        print("  Windows: Download from https://ffmpeg.org/download.html")
        sys.exit(1)

    # Find all video files
    print(f"Scanning directory: {args.directory}")
    video_files = find_video_files(args.directory)

    if not video_files:
        print(f"No video files found in {args.directory}")
        print(f"Supported formats: {', '.join(SUPPORTED_FORMATS)}")
        sys.exit(0)

    print(f"Found {len(video_files)} video files")
    print()

    # Connect to database (unless dry run)
    conn = None
    cursor = None

    if not args.dry_run:
        try:
            import psycopg2
            import psycopg2.extras
        except ImportError:
            print("Error: psycopg2 not installed.")
            print("Install with: pip install psycopg2-binary")
            sys.exit(1)

        try:
            print(f"Connecting to database {args.db_name}@{args.db_host}:{args.db_port}...")
            conn = psycopg2.connect(
                host=args.db_host,
                port=args.db_port,
                database=args.db_name,
                user=args.db_user,
                password=args.db_password
            )
            conn.set_session(autocommit=False)
            cursor = conn.cursor()
            print("Connected successfully\n")

            # Check if videos table exists
            cursor.execute("""
                SELECT EXISTS (
                    SELECT FROM information_schema.tables
                    WHERE table_schema = 'public'
                    AND table_name = 'videos'
                )
            """)
            table_exists = cursor.fetchone()[0]

            if not table_exists:
                print("Error: videos table does not exist.")
                print("Run the migration first: psql -d dogetionary -f db/migrations/002_create_videos_table.sql")
                sys.exit(1)

        except Exception as e:
            print(f"Error connecting to database: {e}")
            sys.exit(1)

    # Statistics
    stats = {
        'total': len(video_files),
        'success': 0,
        'failed': 0,
        'skipped': 0,
        'total_size_bytes': 0,
        'total_duration_seconds': 0.0
    }

    # Process videos in batches
    print(f"{'[DRY RUN] ' if args.dry_run else ''}Processing {len(video_files)} videos (batch size: {args.batch_size})...\n")

    failed_files = []

    for i in range(0, len(video_files), args.batch_size):
        batch = video_files[i:i + args.batch_size]
        batch_num = (i // args.batch_size) + 1
        total_batches = (len(video_files) + args.batch_size - 1) // args.batch_size

        print(f"Batch {batch_num}/{total_batches}:")

        for video_path in tqdm(batch, desc=f"  Processing", unit="video"):
            try:
                # Extract video information
                video_info = get_video_info(video_path)

                # Update statistics
                stats['total_size_bytes'] += len(video_info['video_data'])
                stats['total_duration_seconds'] += video_info['metadata'].get('duration_seconds', 0)

                # Import to database
                if import_video_to_db(cursor, video_info, dry_run=args.dry_run):
                    stats['success'] += 1
                else:
                    stats['failed'] += 1
                    failed_files.append((video_path, "Database insert failed"))

            except Exception as e:
                stats['failed'] += 1
                failed_files.append((video_path, str(e)))
                print(f"\n  Error processing {os.path.basename(video_path)}: {e}")

        # Commit batch (unless dry run)
        if not args.dry_run and cursor:
            try:
                conn.commit()
                print(f"  ✓ Batch {batch_num} committed\n")
            except Exception as e:
                conn.rollback()
                print(f"  ✗ Batch {batch_num} rollback: {e}\n")
                stats['failed'] += len(batch)
                stats['success'] -= len(batch)

    # Close database connection
    if cursor:
        cursor.close()
    if conn:
        conn.close()

    # Print summary
    print("\n" + "=" * 60)
    print(f"{'DRY RUN ' if args.dry_run else ''}IMPORT SUMMARY")
    print("=" * 60)
    print(f"Total videos:        {stats['total']}")
    print(f"Successfully imported: {stats['success']}")
    print(f"Failed:              {stats['failed']}")
    print(f"Skipped:             {stats['skipped']}")
    print()
    print(f"Total size:          {format_file_size(stats['total_size_bytes'])}")
    print(f"Total duration:      {format_duration(stats['total_duration_seconds'])}")
    print("=" * 60)

    # Show failed files
    if failed_files:
        print(f"\nFailed files ({len(failed_files)}):")
        for video_path, error in failed_files[:10]:  # Show first 10
            print(f"  - {os.path.basename(video_path)}: {error}")
        if len(failed_files) > 10:
            print(f"  ... and {len(failed_files) - 10} more")

    # Exit with error code if any failures
    if stats['failed'] > 0:
        sys.exit(1)


if __name__ == '__main__':
    main()
