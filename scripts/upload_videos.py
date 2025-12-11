#!/usr/bin/env python3
"""
Upload videos from a directory to database.
Each video file is stored in the videos table and linked to the word (folder name).

Usage:
    python upload_videos.py /path/to/videos/directory

Directory structure should be:
    /path/to/videos/
        word1/
            video1.mp4
            video2.mp4
        word2/
            video3.mp4
"""

import os
import sys
import json
import hashlib
import psycopg2
from pathlib import Path

# Database connection
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'dogetionary',
    'user': 'dogeuser',
    'password': 'dogepass'
}


def calculate_md5(file_path):
    """Calculate MD5 hash of a file."""
    hash_md5 = hashlib.md5()
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def sanitize_text(text):
    """Remove NUL characters and other problematic bytes from text."""
    if text is None:
        return None
    if not isinstance(text, str):
        return text
    # Remove NUL bytes (0x00) which PostgreSQL doesn't allow in text fields or JSONB
    return text.replace('\x00', '')


def sanitize_metadata(data):
    """Recursively sanitize all string values in a dictionary."""
    if isinstance(data, dict):
        return {k: sanitize_metadata(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [sanitize_metadata(item) for item in data]
    elif isinstance(data, str):
        return sanitize_text(data)
    else:
        return data


def upload_videos(videos_dir):
    """Upload all videos from directory to database."""

    videos_path = Path(videos_dir)

    if not videos_path.exists():
        print(f"❌ Directory not found: {videos_path}")
        sys.exit(1)

    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()

    try:
        # Add hash column if it doesn't exist (idempotent migration)
        cur.execute("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.columns
                    WHERE table_name='videos' AND column_name='content_hash'
                ) THEN
                    ALTER TABLE videos ADD COLUMN content_hash VARCHAR(32);
                    CREATE INDEX IF NOT EXISTS idx_videos_content_hash ON videos(content_hash);
                END IF;
            END $$;
        """)
        conn.commit()

        # Get all word folders
        word_folders = [f for f in videos_path.iterdir() if f.is_dir()]

        print(f"Found {len(word_folders)} word folders")

        total_videos = 0
        total_links = 0
        skipped_duplicates = 0

        for word_folder in sorted(word_folders):
            word = word_folder.name.lower()

            # Get all mp4 files in this folder
            video_files = list(word_folder.glob('*.mp4'))

            if not video_files:
                print(f"⚠️  No videos found for word: {word}")
                continue

            print(f"\n📁 Processing word: '{word}' ({len(video_files)} videos)")

            for video_file in sorted(video_files):
                # Look for matching JSON metadata file
                json_file = video_file.with_suffix('.json')
                clip_metadata = {}
                transcript = None

                if json_file.exists():
                    try:
                        with open(json_file, 'r', encoding='utf-8') as f:
                            clip_metadata = json.load(f)
                        transcript = sanitize_text(clip_metadata.get('transcript', ''))
                    except Exception as e:
                        print(f"  ⚠️  Could not read metadata for {video_file.name}: {e}")

                # Calculate video hash for deduplication
                video_hash = calculate_md5(video_file)

                # Check if video with this hash already exists
                cur.execute("""
                    SELECT id, name FROM videos WHERE content_hash = %s
                """, (video_hash,))

                existing = cur.fetchone()

                if existing:
                    video_id, existing_name = existing

                    # Update transcript and metadata for existing video
                    try:
                        enhanced_metadata = {
                            'word': word,
                            'clip_id': clip_metadata.get('clip_id'),
                            'clip_title': clip_metadata.get('clip_title'),
                            'clip_slug': clip_metadata.get('clip_slug'),
                            'duration_seconds': clip_metadata.get('duration_seconds'),
                            'resolution': clip_metadata.get('resolution'),
                            'views': clip_metadata.get('clip_views'),
                            'likes': clip_metadata.get('likes'),
                            'date_added': clip_metadata.get('date_added'),
                            'subtitles': clip_metadata.get('subtitles'),
                            'movie_title': clip_metadata.get('movie_title'),
                            'movie_year': clip_metadata.get('movie_year'),
                            'movie_director': clip_metadata.get('movie_director'),
                            'movie_writer': clip_metadata.get('movie_writer'),
                            'movie_language': clip_metadata.get('movie_language'),
                            'movie_country': clip_metadata.get('movie_country'),
                            'movie_runtime': clip_metadata.get('movie_runtime'),
                            'movie_rated': clip_metadata.get('movie_rated'),
                            'movie_plot': clip_metadata.get('movie_plot'),
                            'movie_imdb_score': clip_metadata.get('movie_imdb_score'),
                            'movie_metascore': clip_metadata.get('movie_metascore'),
                            'imdb_id': clip_metadata.get('imdb_id'),
                            'actors': clip_metadata.get('actors'),
                            'characters': clip_metadata.get('characters'),
                            'season': clip_metadata.get('season'),
                            'episode': clip_metadata.get('episode'),
                            'movie_poster': clip_metadata.get('movie_poster'),
                            'thumbnail_full': clip_metadata.get('thumbnail_full'),
                            'thumbnail_16x9': clip_metadata.get('thumbnail_16x9'),
                            'file_size_mb': clip_metadata.get('file_size_mb'),
                            'file_path': clip_metadata.get('file_path'),
                        }
                        # Remove None values
                        enhanced_metadata = {k: v for k, v in enhanced_metadata.items() if v is not None}

                        # Sanitize all strings in metadata
                        enhanced_metadata = sanitize_metadata(enhanced_metadata)

                        # Test JSON serialization before DB insert
                        metadata_json = json.dumps(enhanced_metadata, ensure_ascii=False)

                        cur.execute("""
                            UPDATE videos
                            SET transcript = %s,
                                metadata = %s::jsonb,
                                updated_at = NOW()
                            WHERE id = %s
                        """, (transcript, metadata_json, video_id))

                        skipped_duplicates += 1
                        print(f"  🔄 Updated metadata: {video_file.name} (ID: {video_id})")
                    except (ValueError, TypeError) as e:
                        print(f"  ⚠️  Skipped {video_file.name}: metadata error - {e}")
                        skipped_duplicates += 1
                else:
                    try:
                        # Read video binary data
                        with open(video_file, 'rb') as f:
                            video_data = f.read()

                        video_name = video_file.stem  # filename without extension
                        file_size_bytes = len(video_data)
                        file_size_mb = file_size_bytes / (1024 * 1024)

                        # Build enhanced metadata from JSON
                        enhanced_metadata = {
                            'word': word,
                            'file_size_mb': round(file_size_mb, 2),
                            'clip_id': clip_metadata.get('clip_id'),
                            'clip_title': clip_metadata.get('clip_title'),
                            'clip_slug': clip_metadata.get('clip_slug'),
                            'duration_seconds': clip_metadata.get('duration_seconds'),
                            'resolution': clip_metadata.get('resolution'),
                            'views': clip_metadata.get('views'),
                            'likes': clip_metadata.get('likes'),
                            'date_added': clip_metadata.get('date_added'),
                            'subtitles': clip_metadata.get('subtitles'),
                            'movie_title': clip_metadata.get('movie_title'),
                            'movie_year': clip_metadata.get('movie_year'),
                            'movie_director': clip_metadata.get('movie_director'),
                            'movie_writer': clip_metadata.get('movie_writer'),
                            'movie_language': clip_metadata.get('movie_language'),
                            'movie_country': clip_metadata.get('movie_country'),
                            'movie_runtime': clip_metadata.get('movie_runtime'),
                            'movie_rated': clip_metadata.get('movie_rated'),
                            'movie_plot': clip_metadata.get('movie_plot'),
                            'movie_imdb_score': clip_metadata.get('movie_imdb_score'),
                            'movie_metascore': clip_metadata.get('movie_metascore'),
                            'imdb_id': clip_metadata.get('imdb_id'),
                            'actors': clip_metadata.get('actors'),
                            'characters': clip_metadata.get('characters'),
                            'season': clip_metadata.get('season'),
                            'episode': clip_metadata.get('episode'),
                            'movie_poster': clip_metadata.get('movie_poster'),
                            'thumbnail_full': clip_metadata.get('thumbnail_full'),
                            'thumbnail_16x9': clip_metadata.get('thumbnail_16x9'),
                            'file_path': clip_metadata.get('file_path'),
                        }
                        # Remove None values
                        enhanced_metadata = {k: v for k, v in enhanced_metadata.items() if v is not None}

                        # Sanitize all strings in metadata
                        enhanced_metadata = sanitize_metadata(enhanced_metadata)

                        # Test JSON serialization before DB insert
                        metadata_json = json.dumps(enhanced_metadata, ensure_ascii=False)

                        # Insert video into videos table with hash, size, transcript, and enhanced metadata
                        cur.execute("""
                            INSERT INTO videos (name, format, video_data, content_hash, size_bytes, transcript, metadata)
                            VALUES (%s, %s, %s, %s, %s, %s, %s::jsonb)
                            ON CONFLICT (name, format)
                            DO UPDATE SET
                                video_data = EXCLUDED.video_data,
                                content_hash = EXCLUDED.content_hash,
                                size_bytes = EXCLUDED.size_bytes,
                                transcript = EXCLUDED.transcript,
                                metadata = EXCLUDED.metadata,
                                updated_at = NOW()
                            RETURNING id
                        """, (
                            video_name,
                            'mp4',
                            psycopg2.Binary(video_data),
                            video_hash,
                            file_size_bytes,
                            transcript,
                            metadata_json
                        ))

                        video_id = cur.fetchone()[0]
                        total_videos += 1

                        transcript_status = f"transcript: {len(transcript)} chars" if transcript else "no transcript"
                        metadata_fields = len([v for v in enhanced_metadata.values() if v is not None])
                        print(f"  ✅ Uploaded: {video_name} (ID: {video_id}, {file_size_mb:.2f} MB, {transcript_status}, {metadata_fields} metadata fields)")
                    except (ValueError, TypeError) as e:
                        print(f"  ⚠️  Skipped {video_file.name}: metadata error - {e}")

                # Link video to word in word_to_video table (idempotent)
                cur.execute("""
                    INSERT INTO word_to_video (word, learning_language, video_id)
                    VALUES (%s, %s, %s)
                    ON CONFLICT (word, learning_language, video_id) DO NOTHING
                    RETURNING id
                """, (word, 'en', video_id))

                if cur.fetchone() is not None:
                    total_links += 1
                    print(f"     🔗 Linked to word: '{word}'")
                else:
                    print(f"     ↩️  Already linked to: '{word}'")

        # Commit all changes
        conn.commit()

        print(f"\n{'='*60}")
        print(f"✅ Upload complete!")
        print(f"   Videos uploaded: {total_videos}")
        print(f"   Duplicates skipped: {skipped_duplicates}")
        print(f"   Word links created: {total_links}")
        print(f"{'='*60}")

        # Show summary by word
        print(f"\n📊 Summary by word:")
        cur.execute("""
            SELECT
                wtv.word,
                COUNT(DISTINCT wtv.video_id) as video_count
            FROM word_to_video wtv
            WHERE wtv.learning_language = 'en'
            GROUP BY wtv.word
            ORDER BY wtv.word
        """)

        for row in cur.fetchall():
            print(f"   {row[0]}: {row[1]} videos")

    except Exception as e:
        conn.rollback()
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        raise
    finally:
        cur.close()
        conn.close()


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python upload_videos.py /path/to/videos/directory")
        print("\nExample: python upload_videos.py /Volumes/databank/dogetionary-videos/")
        sys.exit(1)

    videos_dir = sys.argv[1]

    print(f"📂 Videos directory: {videos_dir}")
    print(f"🔌 Database: {DB_CONFIG['database']} @ {DB_CONFIG['host']}:{DB_CONFIG['port']}")
    print()

    upload_videos(videos_dir)
