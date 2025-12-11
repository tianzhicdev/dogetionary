#!/usr/bin/env python3
"""
Populate word_to_video linking table from existing video metadata.

Reads all videos from the database, extracts the vocabulary_word from metadata,
and creates links in the word_to_video table.

Usage:
    python scripts/populate_word_to_video.py [--dry-run] [--db-host HOST] [--db-port PORT]

Example:
    python scripts/populate_word_to_video.py --dry-run
    python scripts/populate_word_to_video.py --db-host localhost --db-port 5432
"""

import argparse
import sys

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    print("Error: psycopg2 not installed.")
    print("Install with: pip install psycopg2-binary")
    sys.exit(1)


def populate_links(conn, dry_run=False):
    """
    Populate word_to_video table from video metadata.

    Args:
        conn: Database connection
        dry_run: If True, show what would be inserted without actually inserting

    Returns:
        dict: Statistics about the operation
    """
    cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    # Fetch all videos with metadata containing 'word' field
    cursor.execute("""
        SELECT id, name, metadata
        FROM videos
        WHERE metadata->>'word' IS NOT NULL
        ORDER BY id
    """)

    videos = cursor.fetchall()

    stats = {
        'total_videos': len(videos),
        'links_created': 0,
        'links_skipped': 0,
        'errors': 0
    }

    print(f"Found {len(videos)} videos with vocabulary words")
    print()

    if dry_run:
        print("[DRY RUN MODE - No changes will be made]")
        print()

    for video in videos:
        video_id = video['id']
        video_name = video['name']
        metadata = video['metadata']

        word = metadata.get('word')
        # Default to English if no language specified
        learning_language = metadata.get('language', 'en')

        if not word:
            stats['links_skipped'] += 1
            continue

        # Clean up word (lowercase, strip whitespace)
        word = word.lower().strip()

        try:
            if dry_run:
                print(f"Would link: video_id={video_id:4d} '{video_name[:40]:40s}' -> word='{word}' lang={learning_language}")
            else:
                cursor.execute("""
                    INSERT INTO word_to_video (word, learning_language, video_id)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (word, learning_language, video_id) DO NOTHING
                """, (word, learning_language, video_id))

                if cursor.rowcount > 0:
                    stats['links_created'] += 1
                    print(f"✓ Linked: video_id={video_id:4d} -> word='{word}' ({learning_language})")
                else:
                    stats['links_skipped'] += 1
                    print(f"⊘ Skipped (duplicate): video_id={video_id:4d} -> word='{word}' ({learning_language})")

        except Exception as e:
            stats['errors'] += 1
            print(f"✗ Error linking video_id={video_id}: {e}")

    if not dry_run:
        conn.commit()

    cursor.close()

    return stats


def verify_links(conn):
    """
    Verify the populated links and show statistics.

    Args:
        conn: Database connection

    Returns:
        dict: Verification statistics
    """
    cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    # Count total links
    cursor.execute("SELECT COUNT(*) as count FROM word_to_video")
    total_links = cursor.fetchone()['count']

    # Count unique words
    cursor.execute("SELECT COUNT(DISTINCT word) as count FROM word_to_video")
    unique_words = cursor.fetchone()['count']

    # Count unique videos
    cursor.execute("SELECT COUNT(DISTINCT video_id) as count FROM word_to_video")
    unique_videos = cursor.fetchone()['count']

    # Find words with most videos
    cursor.execute("""
        SELECT word, learning_language, COUNT(*) as video_count
        FROM word_to_video
        GROUP BY word, learning_language
        ORDER BY video_count DESC
        LIMIT 10
    """)
    top_words = cursor.fetchall()

    cursor.close()

    return {
        'total_links': total_links,
        'unique_words': unique_words,
        'unique_videos': unique_videos,
        'top_words': top_words
    }


def main():
    parser = argparse.ArgumentParser(
        description='Populate word_to_video linking table from video metadata',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run to see what would be created
  python scripts/populate_word_to_video.py --dry-run

  # Actually populate the table
  python scripts/populate_word_to_video.py

  # Use custom database connection
  python scripts/populate_word_to_video.py --db-host localhost --db-port 5432
        """
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be inserted without actually inserting'
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
        default='dogeuser',
        help='Database user (default: dogeuser)'
    )

    parser.add_argument(
        '--db-password',
        default='dogepass',
        help='Database password (default: dogepass)'
    )

    args = parser.parse_args()

    # Connect to database
    try:
        print(f"Connecting to database {args.db_name}@{args.db_host}:{args.db_port}...")
        conn = psycopg2.connect(
            host=args.db_host,
            port=args.db_port,
            database=args.db_name,
            user=args.db_user,
            password=args.db_password
        )
        print("Connected successfully\n")
    except Exception as e:
        print(f"Error connecting to database: {e}")
        sys.exit(1)

    # Populate links
    print("=" * 80)
    print("POPULATING WORD-TO-VIDEO LINKS")
    print("=" * 80)
    print()

    stats = populate_links(conn, dry_run=args.dry_run)

    # Print summary
    print()
    print("=" * 80)
    print(f"{'DRY RUN ' if args.dry_run else ''}SUMMARY")
    print("=" * 80)
    print(f"Total videos processed:  {stats['total_videos']}")
    print(f"Links created:           {stats['links_created']}")
    print(f"Links skipped:           {stats['links_skipped']}")
    print(f"Errors:                  {stats['errors']}")
    print("=" * 80)

    # Verify links (if not dry run)
    if not args.dry_run and stats['links_created'] > 0:
        print()
        print("Verifying populated links...")
        print()

        verify_stats = verify_links(conn)

        print("=" * 80)
        print("VERIFICATION RESULTS")
        print("=" * 80)
        print(f"Total links:             {verify_stats['total_links']}")
        print(f"Unique words:            {verify_stats['unique_words']}")
        print(f"Unique videos:           {verify_stats['unique_videos']}")
        print()

        if verify_stats['top_words']:
            print("Top 10 words by video count:")
            for row in verify_stats['top_words']:
                print(f"  - {row['word']:20s} ({row['learning_language']}): {row['video_count']} videos")

        print("=" * 80)

    conn.close()

    # Exit with error code if there were errors
    if stats['errors'] > 0:
        sys.exit(1)


if __name__ == '__main__':
    main()
