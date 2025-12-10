# Video Database Preparation Plan

## Overview

Prepare the database to store videos and create an import script to load videos from `/Volumes/databank/dogetionary-videos` into PostgreSQL.

---

## Part 1: Database Schema Design

### Table: `videos`

```sql
CREATE TABLE videos (
    -- Primary key
    id SERIAL PRIMARY KEY,

    -- File information
    name VARCHAR(255) NOT NULL,              -- Original filename (e.g., "beautiful_sunset")
    format VARCHAR(10) NOT NULL,             -- File format (e.g., "mp4", "mov", "webm")

    -- Video data (BLOB storage)
    video_data BYTEA NOT NULL,               -- Binary video file data

    -- Transcript (optional text)
    transcript TEXT,                          -- Spoken words in video (if any)

    -- Metadata (JSON for flexibility)
    metadata JSONB DEFAULT '{}'::jsonb,      -- Video metadata (see structure below)

    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- Constraints
    UNIQUE(name, format),  -- Prevent duplicate video files

    -- Indexes
    INDEX idx_videos_name (name),
    INDEX idx_videos_format (format),
    INDEX idx_videos_metadata (metadata) USING GIN  -- For JSON queries
);

-- Comments
COMMENT ON TABLE videos IS 'Video files with metadata for practice mode';
COMMENT ON COLUMN videos.name IS 'Video filename without extension (e.g., beautiful_sunset)';
COMMENT ON COLUMN videos.format IS 'Video file format/extension (mp4, mov, webm)';
COMMENT ON COLUMN videos.video_data IS 'Binary video file data (BYTEA/BLOB)';
COMMENT ON COLUMN videos.transcript IS 'Optional transcript of spoken words in video';
COMMENT ON COLUMN videos.metadata IS 'JSON metadata: duration, size, resolution, word, language, etc.';
```

### Metadata JSON Structure

```json
{
  "duration_seconds": 5,
  "file_size_bytes": 3145728,
  "width": 1920,
  "height": 1080,
  "fps": 30,
  "bitrate": 5000000,
  "codec": "h264",
  "audio_codec": "aac",
  "word": "beautiful",
  "language": "en",
  "description": "Sunset over ocean",
  "tags": ["nature", "sunset", "ocean"],
  "source": "stock_footage",
  "license": "CC0",
  "original_path": "/Volumes/databank/dogetionary-videos/en/beautiful_sunset.mp4"
}
```

**Benefits of JSONB metadata:**
- Flexible schema (can add fields without ALTER TABLE)
- Queryable with PostgreSQL JSON operators
- Indexed for fast lookups
- Self-documenting

---

## Part 2: Video Directory Structure

### Expected Structure

```
/Volumes/databank/dogetionary-videos/
├── en/                          # English videos
│   ├── beautiful_sunset.mp4
│   ├── beautiful_flower.mp4
│   ├── run_person.mp4
│   └── ...
├── zh/                          # Chinese videos
│   ├── 你好_greeting.mp4
│   └── ...
├── transcripts/                 # Optional transcript files
│   ├── en/
│   │   ├── beautiful_sunset.txt
│   │   └── ...
│   └── zh/
│       └── ...
└── metadata/                    # Optional metadata files
    ├── en/
    │   ├── beautiful_sunset.json
    │   └── ...
    └── zh/
        └── ...
```

### Filename Convention

```
{word}_{descriptor}.{format}

Examples:
- beautiful_sunset.mp4      → word="beautiful", descriptor="sunset"
- run_person.mp4             → word="run", descriptor="person"
- happy_child_playing.mp4    → word="happy", descriptor="child_playing"
```

### Transcript File Convention (Optional)

```
{video_name}.txt

Example:
beautiful_sunset.txt contains:
"This is a beautiful sunset over the ocean. The colors are amazing."
```

### Metadata File Convention (Optional)

```
{video_name}.json

Example:
beautiful_sunset.json contains:
{
  "description": "Sunset over ocean",
  "tags": ["nature", "sunset"],
  "source": "Pexels",
  "license": "CC0"
}
```

---

## Part 3: Import Script Design

### Script: `scripts/import_videos_to_db.py`

#### Features

1. **Directory Scanning**
   - Recursively scan `/Volumes/databank/dogetionary-videos`
   - Find all video files (mp4, mov, webm)
   - Extract language from directory structure

2. **Metadata Extraction**
   - Use `ffprobe` to extract video metadata
   - Parse filename to extract word and descriptor
   - Load external metadata JSON if exists
   - Load transcript file if exists

3. **Database Import**
   - Read video file as binary
   - Insert into `videos` table
   - Handle duplicates gracefully
   - Transaction-safe (rollback on error)

4. **Progress Tracking**
   - Show progress bar
   - Count imported/skipped/failed
   - Summary report at end

5. **Error Handling**
   - Skip corrupted files
   - Log errors to file
   - Continue on individual failures
   - Validate file size limits

#### Script Flow

```
┌─────────────────────┐
│ Start Import        │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Scan Directory      │
│ Find all *.mp4      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ For each video:     │
│ 1. Extract metadata │
│ 2. Read file binary │
│ 3. Load transcript  │
│ 4. Insert to DB     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Print Summary       │
│ - Imported: 50      │
│ - Skipped: 5        │
│ - Failed: 2         │
└─────────────────────┘
```

#### Script Parameters

```bash
python scripts/import_videos_to_db.py \
  --source /Volumes/databank/dogetionary-videos \
  --formats mp4,mov,webm \
  --max-size 10485760 \
  --skip-existing \
  --dry-run \
  --verbose
```

**Parameters:**
- `--source`: Source directory (default: /Volumes/databank/dogetionary-videos)
- `--formats`: Comma-separated video formats (default: mp4)
- `--max-size`: Max file size in bytes (default: 10MB = 10485760)
- `--skip-existing`: Skip if video already exists in DB
- `--dry-run`: Show what would be imported without doing it
- `--verbose`: Show detailed logs

---

## Part 4: Metadata Extraction Logic

### Using ffprobe

```python
import subprocess
import json

def extract_video_metadata(filepath):
    """Extract metadata using ffprobe"""
    try:
        cmd = [
            'ffprobe',
            '-v', 'quiet',
            '-print_format', 'json',
            '-show_format',
            '-show_streams',
            filepath
        ]

        result = subprocess.run(cmd, capture_output=True, text=True)
        data = json.loads(result.stdout)

        # Extract video stream
        video_stream = next(
            (s for s in data['streams'] if s['codec_type'] == 'video'),
            None
        )

        # Extract audio stream
        audio_stream = next(
            (s for s in data['streams'] if s['codec_type'] == 'audio'),
            None
        )

        metadata = {
            'duration_seconds': float(data['format'].get('duration', 0)),
            'file_size_bytes': int(data['format'].get('size', 0)),
            'bitrate': int(data['format'].get('bit_rate', 0)),
        }

        if video_stream:
            metadata.update({
                'width': int(video_stream.get('width', 0)),
                'height': int(video_stream.get('height', 0)),
                'codec': video_stream.get('codec_name', 'unknown'),
                'fps': eval(video_stream.get('r_frame_rate', '0/1'))
            })

        if audio_stream:
            metadata['audio_codec'] = audio_stream.get('codec_name', 'none')

        return metadata

    except Exception as e:
        print(f"Error extracting metadata: {e}")
        return {}
```

### Parsing Filename

```python
import re
from pathlib import Path

def parse_filename(filepath, language_dir):
    """
    Parse filename to extract video information

    Args:
        filepath: /Volumes/.../en/beautiful_sunset.mp4
        language_dir: "en"

    Returns:
        {
            'name': 'beautiful_sunset',
            'format': 'mp4',
            'word': 'beautiful',
            'descriptor': 'sunset',
            'language': 'en'
        }
    """
    path = Path(filepath)

    # Get name without extension
    name = path.stem  # "beautiful_sunset"
    format = path.suffix[1:]  # "mp4" (remove leading dot)

    # Parse word and descriptor
    parts = name.split('_', 1)
    word = parts[0]
    descriptor = parts[1] if len(parts) > 1 else None

    return {
        'name': name,
        'format': format,
        'word': word,
        'descriptor': descriptor,
        'language': language_dir
    }
```

---

## Part 5: Database Operations

### Insert Video

```python
import psycopg2
from psycopg2.extras import Json

def insert_video(conn, video_data):
    """
    Insert video into database

    Args:
        conn: psycopg2 connection
        video_data: dict with all video information

    Returns:
        video_id or None
    """
    cur = conn.cursor()

    try:
        # Read video file as binary
        with open(video_data['filepath'], 'rb') as f:
            video_binary = f.read()

        # Prepare metadata JSON
        metadata = {
            'duration_seconds': video_data.get('duration_seconds'),
            'file_size_bytes': video_data.get('file_size_bytes'),
            'width': video_data.get('width'),
            'height': video_data.get('height'),
            'fps': video_data.get('fps'),
            'bitrate': video_data.get('bitrate'),
            'codec': video_data.get('codec'),
            'audio_codec': video_data.get('audio_codec'),
            'word': video_data.get('word'),
            'language': video_data.get('language'),
            'descriptor': video_data.get('descriptor'),
            'original_path': video_data['filepath']
        }

        # Remove None values
        metadata = {k: v for k, v in metadata.items() if v is not None}

        # Insert
        cur.execute("""
            INSERT INTO videos (
                name,
                format,
                video_data,
                transcript,
                metadata
            ) VALUES (%s, %s, %s, %s, %s)
            RETURNING id
        """, (
            video_data['name'],
            video_data['format'],
            psycopg2.Binary(video_binary),
            video_data.get('transcript'),
            Json(metadata)
        ))

        video_id = cur.fetchone()[0]
        conn.commit()

        return video_id

    except psycopg2.IntegrityError:
        conn.rollback()
        # Video already exists
        return None

    except Exception as e:
        conn.rollback()
        raise e

    finally:
        cur.close()
```

### Check if Video Exists

```python
def video_exists(conn, name, format):
    """Check if video already exists in database"""
    cur = conn.cursor()

    cur.execute("""
        SELECT id FROM videos
        WHERE name = %s AND format = %s
    """, (name, format))

    result = cur.fetchone()
    cur.close()

    return result is not None
```

---

## Part 6: Complete Script Structure

### File Structure

```
scripts/
├── import_videos_to_db.py        # Main import script
├── video_utils.py                # Utility functions
│   ├── extract_metadata()
│   ├── parse_filename()
│   ├── load_transcript()
│   └── load_external_metadata()
└── requirements.txt              # Python dependencies
```

### requirements.txt

```
psycopg2-binary>=2.9.0
tqdm>=4.65.0
```

### Main Script Outline

```python
#!/usr/bin/env python3
"""
Import videos from directory to PostgreSQL database

Usage:
    python scripts/import_videos_to_db.py --source /Volumes/databank/dogetionary-videos
    python scripts/import_videos_to_db.py --dry-run --verbose
"""

import argparse
import sys
from pathlib import Path
from tqdm import tqdm
import psycopg2

# Constants
DEFAULT_SOURCE = "/Volumes/databank/dogetionary-videos"
DEFAULT_FORMATS = ["mp4"]
DEFAULT_MAX_SIZE = 10 * 1024 * 1024  # 10MB
DATABASE_URL = "postgresql://dogeuser:dogepass@localhost:5432/dogetionary"

class VideoImporter:
    def __init__(self, source_dir, formats, max_size, skip_existing, dry_run, verbose):
        self.source_dir = Path(source_dir)
        self.formats = formats
        self.max_size = max_size
        self.skip_existing = skip_existing
        self.dry_run = dry_run
        self.verbose = verbose

        # Statistics
        self.stats = {
            'scanned': 0,
            'imported': 0,
            'skipped': 0,
            'failed': 0
        }

    def scan_videos(self):
        """Scan directory for video files"""
        video_files = []

        for format in self.formats:
            pattern = f"**/*.{format}"
            files = list(self.source_dir.glob(pattern))
            video_files.extend(files)

        return video_files

    def get_language_from_path(self, filepath):
        """Extract language from directory structure"""
        # Assume structure: .../en/video.mp4 or .../zh/video.mp4
        parts = filepath.parts

        # Look for language code (2-letter)
        for part in reversed(parts):
            if len(part) == 2 and part.isalpha():
                return part

        return 'unknown'

    def process_video(self, filepath):
        """Process single video file"""
        # Implementation details in next section
        pass

    def run(self):
        """Main import process"""
        print(f"🎬 Video Import Starting")
        print(f"   Source: {self.source_dir}")
        print(f"   Formats: {', '.join(self.formats)}")
        print(f"   Max size: {self.max_size / 1024 / 1024:.1f}MB")
        print(f"   Dry run: {self.dry_run}")
        print()

        # Scan for videos
        video_files = self.scan_videos()
        self.stats['scanned'] = len(video_files)

        print(f"📹 Found {len(video_files)} video files")
        print()

        if not video_files:
            print("❌ No video files found")
            return

        # Connect to database
        if not self.dry_run:
            conn = psycopg2.connect(DATABASE_URL)
        else:
            conn = None

        # Process each video
        with tqdm(video_files, desc="Importing") as pbar:
            for filepath in pbar:
                pbar.set_description(f"Processing {filepath.name}")

                try:
                    self.process_video(filepath, conn)
                except Exception as e:
                    self.stats['failed'] += 1
                    if self.verbose:
                        print(f"\n❌ Error processing {filepath}: {e}")

        # Close connection
        if conn:
            conn.close()

        # Print summary
        self.print_summary()

    def print_summary(self):
        """Print import summary"""
        print()
        print("=" * 50)
        print("📊 Import Summary")
        print("=" * 50)
        print(f"Scanned:  {self.stats['scanned']}")
        print(f"Imported: {self.stats['imported']} ✅")
        print(f"Skipped:  {self.stats['skipped']} ⏭️")
        print(f"Failed:   {self.stats['failed']} ❌")
        print("=" * 50)

def main():
    parser = argparse.ArgumentParser(description='Import videos to database')
    parser.add_argument('--source', default=DEFAULT_SOURCE, help='Source directory')
    parser.add_argument('--formats', default='mp4', help='Comma-separated formats')
    parser.add_argument('--max-size', type=int, default=DEFAULT_MAX_SIZE, help='Max file size')
    parser.add_argument('--skip-existing', action='store_true', help='Skip existing videos')
    parser.add_argument('--dry-run', action='store_true', help='Dry run (no DB changes)')
    parser.add_argument('--verbose', action='store_true', help='Verbose output')

    args = parser.parse_args()

    # Parse formats
    formats = [f.strip() for f in args.formats.split(',')]

    # Create importer
    importer = VideoImporter(
        source_dir=args.source,
        formats=formats,
        max_size=args.max_size,
        skip_existing=args.skip_existing,
        dry_run=args.dry_run,
        verbose=args.verbose
    )

    # Run import
    importer.run()

if __name__ == '__main__':
    main()
```

---

## Part 7: Implementation Phases

### Phase 1: Database Setup (30 minutes)

**Tasks:**
1. Create migration file
2. Run migration
3. Verify table created
4. Test manual insert

**Files:**
- `db/migrations/002_create_videos_table.sql`

**Commands:**
```bash
# Create migration
cat > db/migrations/002_create_videos_table.sql << 'EOF'
-- Migration content here
EOF

# Run migration
docker-compose exec postgres psql -U dogeuser -d dogetionary -f /db/migrations/002_create_videos_table.sql

# Verify
docker-compose exec postgres psql -U dogeuser -d dogetionary -c "\d videos"
```

### Phase 2: Utility Functions (1 hour)

**Tasks:**
1. Create `scripts/video_utils.py`
2. Implement metadata extraction
3. Implement filename parsing
4. Test functions with sample video

**Test:**
```python
# Test metadata extraction
python -c "
from video_utils import extract_video_metadata
metadata = extract_video_metadata('/path/to/test.mp4')
print(metadata)
"
```

### Phase 3: Import Script Core (2 hours)

**Tasks:**
1. Create `scripts/import_videos_to_db.py`
2. Implement directory scanning
3. Implement database operations
4. Add error handling

**Test:**
```bash
# Dry run
python scripts/import_videos_to_db.py --dry-run --verbose

# Import single directory
python scripts/import_videos_to_db.py --source /path/to/test/videos
```

### Phase 4: Enhancement & Testing (1 hour)

**Tasks:**
1. Add progress bar (tqdm)
2. Add transcript loading
3. Add external metadata loading
4. Test with actual videos

**Test:**
```bash
# Full import
python scripts/import_videos_to_db.py \
  --source /Volumes/databank/dogetionary-videos \
  --skip-existing \
  --verbose
```

---

## Part 8: Validation & Testing

### Pre-flight Checks

```bash
# 1. Check ffprobe installed
which ffprobe
# If not: brew install ffmpeg

# 2. Check source directory exists
ls /Volumes/databank/dogetionary-videos

# 3. Check database connection
docker-compose exec postgres psql -U dogeuser -d dogetionary -c "SELECT 1"

# 4. Check Python dependencies
pip install psycopg2-binary tqdm
```

### Test Cases

**Test 1: Single Small Video**
```bash
# Create test directory
mkdir -p /tmp/test-videos/en
cp /path/to/small.mp4 /tmp/test-videos/en/test_video.mp4

# Import
python scripts/import_videos_to_db.py --source /tmp/test-videos

# Verify
docker-compose exec postgres psql -U dogeuser -d dogetionary -c "SELECT id, name, format, octet_length(video_data) FROM videos;"
```

**Test 2: Duplicate Detection**
```bash
# Import same video twice
python scripts/import_videos_to_db.py --source /tmp/test-videos
python scripts/import_videos_to_db.py --source /tmp/test-videos --skip-existing

# Should skip on second run
```

**Test 3: Large Video (Edge Case)**
```bash
# Try to import video > 10MB
# Should skip with warning
```

**Test 4: Metadata Extraction**
```bash
# Verify metadata JSON is populated correctly
docker-compose exec postgres psql -U dogeuser -d dogetionary -c "
SELECT name, metadata->'duration_seconds', metadata->'width', metadata->'height'
FROM videos;
"
```

### Validation Queries

```sql
-- Check all imported videos
SELECT
    id,
    name,
    format,
    octet_length(video_data) / 1024 / 1024 as size_mb,
    metadata->>'duration_seconds' as duration,
    metadata->>'word' as word,
    metadata->>'language' as language
FROM videos
ORDER BY id;

-- Check for duplicates
SELECT name, format, COUNT(*)
FROM videos
GROUP BY name, format
HAVING COUNT(*) > 1;

-- Check total storage
SELECT
    COUNT(*) as total_videos,
    SUM(octet_length(video_data)) / 1024 / 1024 as total_mb,
    AVG(octet_length(video_data)) / 1024 / 1024 as avg_mb
FROM videos;

-- Check metadata completeness
SELECT
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE metadata->>'word' IS NOT NULL) as has_word,
    COUNT(*) FILTER (WHERE metadata->>'duration_seconds' IS NOT NULL) as has_duration,
    COUNT(*) FILTER (WHERE transcript IS NOT NULL) as has_transcript
FROM videos;
```

---

## Part 9: Error Handling

### Common Issues

**Issue 1: ffprobe not found**
```python
# Check before using
import shutil

if not shutil.which('ffprobe'):
    print("❌ ffprobe not found. Install ffmpeg:")
    print("   brew install ffmpeg")
    sys.exit(1)
```

**Issue 2: File too large**
```python
# Check file size before reading
file_size = filepath.stat().st_size

if file_size > self.max_size:
    print(f"⏭️  Skipping {filepath.name}: File too large ({file_size / 1024 / 1024:.1f}MB)")
    self.stats['skipped'] += 1
    return
```

**Issue 3: Database connection lost**
```python
# Reconnect on error
try:
    insert_video(conn, video_data)
except psycopg2.OperationalError:
    print("⚠️  Database connection lost, reconnecting...")
    conn = psycopg2.connect(DATABASE_URL)
    insert_video(conn, video_data)
```

**Issue 4: Corrupt video file**
```python
# Handle ffprobe errors gracefully
try:
    metadata = extract_video_metadata(filepath)
except Exception as e:
    print(f"⚠️  Could not extract metadata from {filepath.name}: {e}")
    metadata = {}  # Use empty metadata
```

---

## Part 10: Summary

### What We're Building

1. **Database Table: `videos`**
   - Stores video files as BYTEA
   - Flexible JSONB metadata
   - Optional transcript field
   - Indexed for performance

2. **Import Script: `import_videos_to_db.py`**
   - Scans directory recursively
   - Extracts metadata with ffprobe
   - Loads transcripts if available
   - Batch imports to database
   - Progress tracking
   - Error handling

### Timeline

| Phase | Duration | Tasks |
|-------|----------|-------|
| Database Setup | 30 min | Create table, run migration |
| Utility Functions | 1 hour | Metadata extraction, parsing |
| Import Script | 2 hours | Core logic, DB operations |
| Testing | 1 hour | Test cases, validation |
| **Total** | **4.5 hours** | End-to-end completion |

### Deliverables

1. ✅ SQL migration file
2. ✅ `video_utils.py` - Utility functions
3. ✅ `import_videos_to_db.py` - Main import script
4. ✅ Test cases and validation queries
5. ✅ Documentation

### Next Steps After This Plan

1. Review and approve this plan
2. Implement database migration
3. Implement utility functions
4. Implement import script
5. Test with sample videos
6. Run full import from `/Volumes/databank/dogetionary-videos`

---

## Appendix A: Sample SQL Migration

**File:** `db/migrations/002_create_videos_table.sql`

```sql
-- Migration: Create videos table
-- Date: 2025-12-09
-- Description: Add video storage for practice mode

BEGIN;

-- Create videos table
CREATE TABLE IF NOT EXISTS videos (
    -- Primary key
    id SERIAL PRIMARY KEY,

    -- File information
    name VARCHAR(255) NOT NULL,
    format VARCHAR(10) NOT NULL,

    -- Video data (BLOB)
    video_data BYTEA NOT NULL,

    -- Transcript (optional)
    transcript TEXT,

    -- Metadata (JSON)
    metadata JSONB DEFAULT '{}'::jsonb,

    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- Constraints
    CONSTRAINT videos_name_format_unique UNIQUE (name, format),
    CONSTRAINT videos_format_check CHECK (format IN ('mp4', 'mov', 'webm', 'avi'))
);

-- Create indexes
CREATE INDEX idx_videos_name ON videos(name);
CREATE INDEX idx_videos_format ON videos(format);
CREATE INDEX idx_videos_metadata ON videos USING GIN (metadata);

-- Create index on metadata->word for fast lookups
CREATE INDEX idx_videos_metadata_word ON videos ((metadata->>'word'));
CREATE INDEX idx_videos_metadata_language ON videos ((metadata->>'language'));

-- Comments
COMMENT ON TABLE videos IS 'Video files with metadata for practice mode';
COMMENT ON COLUMN videos.name IS 'Video filename without extension';
COMMENT ON COLUMN videos.format IS 'Video file format (mp4, mov, webm, avi)';
COMMENT ON COLUMN videos.video_data IS 'Binary video file data';
COMMENT ON COLUMN videos.transcript IS 'Optional transcript of spoken words';
COMMENT ON COLUMN videos.metadata IS 'JSONB metadata: duration, size, resolution, word, language, etc.';

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_videos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update updated_at
CREATE TRIGGER videos_updated_at
BEFORE UPDATE ON videos
FOR EACH ROW
EXECUTE FUNCTION update_videos_updated_at();

COMMIT;
```

---

## Appendix B: Directory Structure Example

```
/Volumes/databank/dogetionary-videos/
│
├── en/                                  # English videos
│   ├── beautiful_sunset.mp4             # Word: beautiful
│   ├── beautiful_flower.mp4
│   ├── run_person.mp4                   # Word: run
│   ├── happy_child.mp4                  # Word: happy
│   └── sad_face.mp4                     # Word: sad
│
├── zh/                                  # Chinese videos
│   ├── 你好_greeting.mp4                 # Word: 你好
│   └── 谢谢_thanks.mp4                   # Word: 谢谢
│
├── transcripts/                         # Optional transcripts
│   ├── en/
│   │   ├── beautiful_sunset.txt         # "This is a beautiful sunset"
│   │   └── run_person.txt               # "A person is running"
│   └── zh/
│       └── 你好_greeting.txt             # "你好，很高兴见到你"
│
└── metadata/                            # Optional external metadata
    ├── en/
    │   ├── beautiful_sunset.json        # Extra metadata
    │   └── run_person.json
    └── zh/
        └── 你好_greeting.json
```

---

*Ready for implementation!*
