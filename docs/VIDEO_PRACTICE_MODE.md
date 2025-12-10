# Video-Based Practice Mode - Implementation Plan

## Table of Contents
1. [Overview](#overview)
2. [Database Schema](#database-schema)
3. [API Design](#api-design)
4. [Frontend Implementation](#frontend-implementation)
5. [CDN Strategy](#cdn-strategy)
6. [Implementation Phases](#implementation-phases)
7. [Video Management](#video-management)
8. [Performance Optimization](#performance-optimization)
9. [Examples](#examples)

---

## Overview

### Goal
Enable video-based practice where users watch videos and answer comprehension questions. Videos are stored in the database and served through CDN-cached endpoints.

### Key Design Principles
- **Simple**: Minimal new code, leverage existing infrastructure
- **CDN-optimized**: Videos served through Cloudflare edge cache
- **Lightweight**: Review batch API returns IDs, not video data
- **Backwards compatible**: Video is optional enhancement

### Architecture
```
┌─────────────┐
│   iOS App   │
└──────┬──────┘
       │
       │ 1. GET /v3/next-review-words-batch
       ├──────────────────────────────────►┌──────────────┐
       │                                    │    Flask     │
       │◄──────────────────────────────────┤   Backend    │
       │ Returns: word + video_id          └──────┬───────┘
       │                                           │
       │ 2. GET /v3/videos/{id}                   │ Query
       ├──────────────────────────────────►┌──────▼───────┐
       │                                    │  PostgreSQL  │
       │◄──────────────────────────────────┤  (video_data)│
       │ Returns: MP4 binary (cached!)     └──────────────┘
       │
       └─► VideoPlayer displays video
```

---

## Database Schema

### New Table: `videos`

```sql
CREATE TABLE videos (
    -- Primary key
    id SERIAL PRIMARY KEY,

    -- File identification
    filename VARCHAR(255) NOT NULL UNIQUE,

    -- Video storage (BLOB)
    video_data BYTEA NOT NULL,

    -- Metadata
    mime_type VARCHAR(50) DEFAULT 'video/mp4',
    file_size_bytes INTEGER,
    duration_seconds INTEGER,

    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- Indexes
    INDEX idx_videos_filename (filename)
);

-- Comments
COMMENT ON TABLE videos IS 'Video files stored as binary blobs for practice mode';
COMMENT ON COLUMN videos.video_data IS 'MP4 video file as binary data';
COMMENT ON COLUMN videos.filename IS 'Original filename for reference';
```

### Modified Table: `definitions`

```sql
ALTER TABLE definitions
ADD COLUMN video_id INTEGER REFERENCES videos(id) ON DELETE SET NULL;

CREATE INDEX idx_definitions_video ON definitions(video_id);

COMMENT ON COLUMN definitions.video_id IS 'Optional video to show with this definition';
```

### Modified Table: `test_questions`

```sql
ALTER TABLE test_questions
ADD COLUMN video_id INTEGER REFERENCES videos(id) ON DELETE SET NULL;

CREATE INDEX idx_questions_video ON test_questions(video_id);

COMMENT ON COLUMN test_questions.video_id IS 'Optional video to use as question prompt';
```

### Entity Relationships

```
┌──────────┐
│  videos  │
│  id (PK) │
└────┬─────┘
     │
     │ referenced by
     │
     ├──────────────┬─────────────────┐
     │              │                 │
┌────▼─────────┐ ┌─▼──────────────┐  │
│ definitions  │ │ test_questions │  │
│ video_id(FK) │ │ video_id (FK)  │  │
└──────────────┘ └────────────────┘  │
                                     │
One video can be used in multiple    │
definitions and questions             │
```

---

## API Design

### 1. Review Batch API (Modified)

**Endpoint:**
```
GET /v3/next-review-words-batch?user_id={uuid}&count={int}
```

**Query Parameters:**
- `user_id` (required): User UUID
- `count` (optional): Number of words to return (default: 10)

**Response:**
```json
{
  "words": [
    {
      "saved_word_id": 123,
      "word": "beautiful",
      "definition": {
        "text": "漂亮的，美丽的",
        "video_id": 5
      },
      "questions": [
        {
          "id": 456,
          "question_text": "What does this mean?",
          "video_id": 5,
          "choices": [
            {"id": "A", "text": "漂亮的"},
            {"id": "B", "text": "丑陋的"},
            {"id": "C", "text": "普通的"},
            {"id": "D", "text": "特殊的"}
          ],
          "correct_answer": "A"
        }
      ]
    }
  ]
}
```

**Backend Query:**
```sql
SELECT
    sw.id as saved_word_id,
    sw.word,
    d.definition_text,
    d.video_id,              -- Just the ID
    tq.id as question_id,
    tq.question_text,
    tq.video_id as question_video_id,
    tq.choices,
    tq.correct_answer
FROM saved_words sw
JOIN definitions d ON d.word = sw.word
    AND d.learning_language = sw.learning_language
    AND d.native_language = sw.native_language
LEFT JOIN test_questions tq ON tq.definition_id = d.id
WHERE sw.user_id = $1
  AND sw.next_review_date <= NOW()
ORDER BY sw.next_review_date ASC
LIMIT $2;
```

**Implementation Location:**
- File: `/src/handlers/review_batch.py`
- Function: `get_review_words_batch()`
- Changes: Add `d.video_id` and `tq.video_id` to SELECT

---

### 2. Video Serving API (New)

**Endpoint:**
```
GET /v3/videos/{video_id}
```

**Path Parameters:**
- `video_id` (required): Video ID from database

**Response:**
- Content-Type: `video/mp4`
- Body: Binary MP4 data

**Response Headers:**
```http
Content-Type: video/mp4
Cache-Control: public, max-age=31536000, immutable
Accept-Ranges: bytes
ETag: "video-{video_id}"
Content-Length: {file_size}
Content-Disposition: inline; filename="{filename}"
```

**Error Responses:**
```json
// 404 Not Found
{
  "error": "Video not found"
}
```

**Backend Implementation:**
```python
from flask import make_response, jsonify

@v3_api.route('/videos/<int:video_id>', methods=['GET'])
def get_video(video_id):
    """
    Serve video file by ID
    CDN-cacheable endpoint for video streaming

    Args:
        video_id: Integer ID of video

    Returns:
        Binary video data with caching headers

    Status Codes:
        200: Video found and returned
        404: Video not found
        500: Database error
    """
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT video_data, mime_type, filename, file_size_bytes
            FROM videos
            WHERE id = %s
        """, (video_id,))

        result = cur.fetchone()
        if not result:
            return jsonify({"error": "Video not found"}), 404

        video_data, mime_type, filename, file_size = result

        # Create response with video binary
        response = make_response(bytes(video_data))
        response.headers['Content-Type'] = mime_type
        response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
        response.headers['Accept-Ranges'] = 'bytes'
        response.headers['ETag'] = f'video-{video_id}'
        response.headers['Content-Length'] = str(file_size)
        response.headers['Content-Disposition'] = f'inline; filename="{filename}"'

        return response

    except Exception as e:
        logging.error(f"Error serving video {video_id}: {e}")
        return jsonify({"error": "Internal server error"}), 500
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()
```

**Implementation Location:**
- File: `/src/app_v3.py`
- Add after existing routes (around line 100)

---

## Frontend Implementation

### iOS Models

**File:** `ios/dogetionary/Core/Models/DictionaryModels.swift`

```swift
// Add to existing ReviewWord structure
struct ReviewWord: Codable {
    let savedWordId: Int
    let word: String
    let definition: Definition
    let questions: [Question]

    struct Definition: Codable {
        let text: String
        let videoId: Int?  // Optional - may not have video

        enum CodingKeys: String, CodingKey {
            case text
            case videoId = "video_id"
        }
    }

    struct Question: Codable {
        let id: Int
        let questionText: String
        let videoId: Int?  // Optional - may not have video
        let choices: [Choice]
        let correctAnswer: String

        enum CodingKeys: String, CodingKey {
            case id
            case questionText = "question_text"
            case videoId = "video_id"
            case choices
            case correctAnswer = "correct_answer"
        }
    }

    struct Choice: Codable {
        let id: String
        let text: String
    }
}
```

### Video Player Component

**File:** `ios/dogetionary/Features/Review/VideoPlayerView.swift`

```swift
import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoId: Int
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .frame(height: 200)
                    .cornerRadius(12)
                    .onAppear {
                        player.play()
                    }
            } else if isLoading {
                ProgressView("Loading video...")
                    .frame(height: 200)
            } else if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(error)
                        .font(.caption)
                }
                .frame(height: 200)
            }
        }
        .onAppear {
            loadVideo()
        }
    }

    private func loadVideo() {
        let baseURL = Configuration.effectiveBaseURL
        guard let url = URL(string: "\(baseURL)/v3/videos/\(videoId)") else {
            error = "Invalid video URL"
            isLoading = false
            return
        }

        // Check cache first
        if let cachedURL = VideoCache.shared.getCachedURL(for: videoId) {
            player = AVPlayer(url: cachedURL)
            isLoading = false
            return
        }

        // Download and cache
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    self.error = "Failed to load video"
                    print("Video load error: \(error)")
                    return
                }

                guard let data = data else {
                    self.error = "No video data"
                    return
                }

                // Save to cache
                let cachedURL = VideoCache.shared.cache(data: data, for: videoId)
                player = AVPlayer(url: cachedURL)
            }
        }.resume()
    }
}
```

### Video Cache

**File:** `ios/dogetionary/Core/Services/VideoCache.swift`

```swift
import Foundation

class VideoCache {
    static let shared = VideoCache()

    private let cacheDirectory: URL

    private init() {
        let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
        cacheDirectory = cachesDirectory.appendingPathComponent("Videos")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func cache(data: Data, for videoId: Int) -> URL {
        let fileURL = cacheDirectory.appendingPathComponent("\(videoId).mp4")
        try? data.write(to: fileURL)
        return fileURL
    }

    func getCachedURL(for videoId: Int) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent("\(videoId).mp4")
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func getCacheSize() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }

        return files.reduce(0) { total, url in
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            return total + Int64(size ?? 0)
        }
    }
}
```

### Practice View Updates

**File:** `ios/dogetionary/Features/Review/PracticeWordView.swift`

```swift
struct PracticeWordView: View {
    let word: ReviewWord
    @State private var selectedAnswer: String?

    var body: some View {
        VStack(spacing: 20) {
            // Word being practiced
            Text(word.word)
                .font(.largeTitle)
                .fontWeight(.bold)

            // Definition video OR text
            if let videoId = word.definition.videoId {
                VideoPlayerView(videoId: videoId)
                    .padding()
            } else {
                Text(word.definition.text)
                    .font(.title2)
                    .padding()
            }

            Divider()

            // Question section
            if let question = word.questions.first {
                VStack(alignment: .leading, spacing: 16) {
                    // Question video (if exists)
                    if let videoId = question.videoId {
                        VideoPlayerView(videoId: videoId)
                    }

                    // Question text
                    Text(question.questionText)
                        .font(.headline)

                    // Answer choices
                    ForEach(question.choices, id: \.id) { choice in
                        Button(action: {
                            selectedAnswer = choice.id
                        }) {
                            HStack {
                                Text("\(choice.id).")
                                    .fontWeight(.bold)
                                Text(choice.text)
                                Spacer()
                                if selectedAnswer == choice.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(
                                selectedAnswer == choice.id
                                    ? Color.blue.opacity(0.1)
                                    : Color.gray.opacity(0.1)
                            )
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }

            Spacer()

            // Submit button
            Button("Submit") {
                submitAnswer()
            }
            .disabled(selectedAnswer == nil)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func submitAnswer() {
        // Submit review logic (existing)
    }
}
```

---

## CDN Strategy

### How Cloudflare CDN Works

```
┌─────────┐
│ iOS App │
└────┬────┘
     │
     │ GET /api/v3/videos/5
     ▼
┌──────────────┐
│ Cloudflare   │ Cache check
│ Edge Network │────────┐
└──────┬───────┘        │
       │                │
       │ CACHE MISS     │ CACHE HIT
       ▼                │
┌──────────┐            │
│  Nginx   │            │
└────┬─────┘            │
     │ Strip /api/      │
     ▼                  │
┌──────────┐            │
│  Flask   │            │
│ Backend  │            │
└────┬─────┘            │
     │                  │
     │ Binary MP4       │ Cached MP4
     │ + Headers        │
     ▼                  ▼
┌──────────────────────────┐
│     User receives        │
│   (First: ~500ms)        │
│   (Cached: ~50ms)        │
└──────────────────────────┘
```

### Cache Headers

**Flask Response:**
```python
response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
```

- `public`: Can be cached by CDN
- `max-age=31536000`: Cache for 1 year (365 days)
- `immutable`: Content never changes (videos don't change)

### Nginx Configuration

**File:** `nginx/default.conf`

No changes needed! Existing configuration already works:

```nginx
location /api/ {
    proxy_pass http://app:5000/;  # Strips /api/ prefix

    # Flask headers are passed through to Cloudflare
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;

    # Existing timeout settings work for videos
    proxy_connect_timeout 600s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
}
```

### CDN Benefits

| Metric | Without CDN | With CDN Cache |
|--------|------------|----------------|
| **Response time** | 500-2000ms | 50-100ms |
| **Backend load** | Every request | First request only |
| **Bandwidth cost** | Full video each time | Cached at edge |
| **Global latency** | Single origin | Edge locations |
| **Concurrent users** | Database bottleneck | Edge handles all |

### Cache Invalidation

Videos are immutable, so no invalidation needed. If a video needs updating:

1. Upload new video with new ID
2. Update definition/question to reference new video_id
3. Old video remains cached (doesn't hurt)
4. New video gets cached on first request

---

## Implementation Phases

### Phase 1: Database Setup (Day 1)

**Tasks:**
1. Create `videos` table
2. Add `video_id` foreign keys to `definitions` and `test_questions`
3. Test database migration

**SQL Migration:**
```sql
-- File: db/migrations/001_add_videos.sql

BEGIN;

-- Create videos table
CREATE TABLE videos (
    id SERIAL PRIMARY KEY,
    filename VARCHAR(255) NOT NULL UNIQUE,
    video_data BYTEA NOT NULL,
    mime_type VARCHAR(50) DEFAULT 'video/mp4',
    file_size_bytes INTEGER,
    duration_seconds INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_videos_filename ON videos(filename);

-- Add video_id to definitions
ALTER TABLE definitions
ADD COLUMN video_id INTEGER REFERENCES videos(id) ON DELETE SET NULL;

CREATE INDEX idx_definitions_video ON definitions(video_id);

-- Add video_id to test_questions
ALTER TABLE test_questions
ADD COLUMN video_id INTEGER REFERENCES videos(id) ON DELETE SET NULL;

CREATE INDEX idx_questions_video ON test_questions(video_id);

COMMIT;
```

**Testing:**
```bash
# Test migration
docker-compose exec postgres psql -U dogeuser -d dogetionary -f /db/migrations/001_add_videos.sql

# Verify tables
docker-compose exec postgres psql -U dogeuser -d dogetionary -c "\d videos"
docker-compose exec postgres psql -U dogeuser -d dogetionary -c "\d definitions" | grep video_id
```

---

### Phase 2: Backend Implementation (Day 2-3)

**Tasks:**
1. Add video serving endpoint to `/src/app_v3.py`
2. Modify review batch query in `/src/handlers/review_batch.py`
3. Test endpoints locally

**Files to Modify:**

**1. `/src/app_v3.py`**
```python
# Add after line 100 (after existing routes)

@v3_api.route('/videos/<int:video_id>', methods=['GET'])
def get_video(video_id):
    """Serve video file by ID - CDN cacheable"""
    # Implementation from API Design section above
    pass
```

**2. `/src/handlers/review_batch.py`**
```python
# Modify existing query to include video_id fields
# Change around line 50

cur.execute("""
    SELECT
        sw.id,
        sw.word,
        d.definition_text,
        d.video_id,  -- ADD THIS
        tq.question_text,
        tq.video_id  -- ADD THIS
    FROM saved_words sw
    JOIN definitions d ON ...
    LEFT JOIN test_questions tq ON ...
    WHERE sw.user_id = %s
    LIMIT %s
""", (user_id, count))
```

**Testing:**
```bash
# Start backend
docker-compose up -d app

# Test video endpoint (after importing a video)
curl -I http://localhost:5001/v3/videos/1

# Should return:
# Content-Type: video/mp4
# Cache-Control: public, max-age=31536000, immutable

# Test review batch
curl "http://localhost:5001/v3/next-review-words-batch?user_id=test-uuid&count=5" | jq .
```

---

### Phase 3: Video Management Tools (Day 3-4)

**Tasks:**
1. Create video import script
2. Create video linking script
3. Import initial test videos

**Script 1: Import Video**

**File:** `scripts/import_video.py`
```python
#!/usr/bin/env python3
"""
Import video file into database

Usage:
    python scripts/import_video.py /path/to/video.mp4
    python scripts/import_video.py /path/to/video.mp4 --filename custom_name.mp4
"""

import sys
import psycopg2
import os
from pathlib import Path

DATABASE_URL = "postgresql://dogeuser:dogepass@localhost:5432/dogetionary"

def get_video_duration(filepath):
    """Get video duration using ffprobe (optional)"""
    try:
        import subprocess
        result = subprocess.run(
            ['ffprobe', '-v', 'error', '-show_entries',
             'format=duration', '-of',
             'default=noprint_wrappers=1:nokey=1', filepath],
            capture_output=True,
            text=True
        )
        return int(float(result.stdout.strip()))
    except:
        return None

def import_video(filepath, filename=None):
    """Import video file into database"""

    if not os.path.exists(filepath):
        print(f"❌ File not found: {filepath}")
        return None

    if filename is None:
        filename = os.path.basename(filepath)

    # Read video file
    with open(filepath, 'rb') as f:
        video_bytes = f.read()

    file_size = len(video_bytes)
    duration = get_video_duration(filepath)

    print(f"📹 Importing: {filename}")
    print(f"   Size: {file_size / 1024 / 1024:.2f} MB")
    if duration:
        print(f"   Duration: {duration}s")

    # Insert into database
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()

    try:
        cur.execute("""
            INSERT INTO videos (filename, video_data, file_size_bytes, duration_seconds)
            VALUES (%s, %s, %s, %s)
            RETURNING id
        """, (
            filename,
            psycopg2.Binary(video_bytes),
            file_size,
            duration
        ))

        video_id = cur.fetchone()[0]
        conn.commit()

        print(f"✅ Imported video_id={video_id}: {filename}")
        return video_id

    except psycopg2.IntegrityError as e:
        print(f"❌ Error: Video with filename '{filename}' already exists")
        return None
    except Exception as e:
        print(f"❌ Error importing video: {e}")
        return None
    finally:
        cur.close()
        conn.close()

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python import_video.py <filepath> [--filename <name>]")
        sys.exit(1)

    filepath = sys.argv[1]
    filename = None

    if '--filename' in sys.argv:
        idx = sys.argv.index('--filename')
        filename = sys.argv[idx + 1]

    import_video(filepath, filename)
```

**Script 2: Link Video to Definition/Question**

**File:** `scripts/link_video.py`
```python
#!/usr/bin/env python3
"""
Link video to definition or question

Usage:
    # Link to definition
    python scripts/link_video.py --video 5 --definition 123

    # Link to question
    python scripts/link_video.py --video 5 --question 456

    # Auto-link by word
    python scripts/link_video.py --video beautiful.mp4 --word beautiful --lang en
"""

import sys
import psycopg2
import argparse

DATABASE_URL = "postgresql://dogeuser:dogepass@localhost:5432/dogetionary"

def link_to_definition(video_id, definition_id):
    """Link video to specific definition"""
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()

    cur.execute("""
        UPDATE definitions
        SET video_id = %s
        WHERE id = %s
        RETURNING id
    """, (video_id, definition_id))

    if cur.fetchone():
        conn.commit()
        print(f"✅ Linked video {video_id} to definition {definition_id}")
    else:
        print(f"❌ Definition {definition_id} not found")

    cur.close()
    conn.close()

def link_to_question(video_id, question_id):
    """Link video to specific question"""
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()

    cur.execute("""
        UPDATE test_questions
        SET video_id = %s
        WHERE id = %s
        RETURNING id
    """, (video_id, question_id))

    if cur.fetchone():
        conn.commit()
        print(f"✅ Linked video {video_id} to question {question_id}")
    else:
        print(f"❌ Question {question_id} not found")

    cur.close()
    conn.close()

def link_by_word(filename, word, language):
    """Auto-link video to definition by word"""
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()

    # Get video_id
    cur.execute("SELECT id FROM videos WHERE filename = %s", (filename,))
    result = cur.fetchone()
    if not result:
        print(f"❌ Video '{filename}' not found")
        return
    video_id = result[0]

    # Update definition
    cur.execute("""
        UPDATE definitions
        SET video_id = %s
        WHERE word = %s AND learning_language = %s
        RETURNING id
    """, (video_id, word, language))

    results = cur.fetchall()
    if results:
        conn.commit()
        print(f"✅ Linked video {video_id} to {len(results)} definition(s) for word '{word}'")
    else:
        print(f"❌ No definitions found for word '{word}' in language '{language}'")

    cur.close()
    conn.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--video', help='Video ID or filename')
    parser.add_argument('--definition', type=int, help='Definition ID')
    parser.add_argument('--question', type=int, help='Question ID')
    parser.add_argument('--word', help='Word to auto-link')
    parser.add_argument('--lang', help='Language for auto-link')

    args = parser.parse_args()

    if args.definition:
        link_to_definition(int(args.video), args.definition)
    elif args.question:
        link_to_question(int(args.video), args.question)
    elif args.word and args.lang:
        link_by_word(args.video, args.word, args.lang)
    else:
        print("Must specify --definition, --question, or --word + --lang")
```

**Batch Import Script:**

**File:** `scripts/batch_import_videos.sh`
```bash
#!/bin/bash
#
# Batch import videos from directory
#
# Usage:
#   ./scripts/batch_import_videos.sh /Volumes/databank/dogetionary-videos/en en

VIDEOS_DIR=$1
LANGUAGE=$2

if [[ -z "$VIDEOS_DIR" || -z "$LANGUAGE" ]]; then
    echo "Usage: $0 <videos_directory> <language>"
    exit 1
fi

echo "========================================="
echo "Batch Video Import"
echo "========================================="
echo "Directory: $VIDEOS_DIR"
echo "Language:  $LANGUAGE"
echo ""

count=0
for video in "$VIDEOS_DIR"/*.mp4; do
    if [[ ! -f "$video" ]]; then
        continue
    fi

    filename=$(basename "$video")
    word="${filename%.mp4}"  # Remove .mp4 extension

    echo "[$((++count))] Processing: $filename"

    # Import video
    video_id=$(python scripts/import_video.py "$video" --filename "$filename" 2>&1 | grep "video_id=" | sed 's/.*video_id=\([0-9]*\).*/\1/')

    if [[ -n "$video_id" ]]; then
        # Auto-link to definition
        python scripts/link_video.py --video "$filename" --word "$word" --lang "$LANGUAGE"
    fi

    echo ""
done

echo "========================================="
echo "✅ Imported $count videos"
echo "========================================="
```

**Testing:**
```bash
# Make scripts executable
chmod +x scripts/*.sh
chmod +x scripts/*.py

# Import single video
python scripts/import_video.py /path/to/beautiful.mp4

# Link to definition
python scripts/link_video.py --video beautiful.mp4 --word beautiful --lang en

# Batch import
./scripts/batch_import_videos.sh /Volumes/databank/dogetionary-videos/en en
```

---

### Phase 4: iOS Integration (Day 5-7)

**Tasks:**
1. Update data models
2. Create VideoPlayerView component
3. Update PracticeWordView
4. Add video caching
5. Test on device

**Files to Create/Modify:**

1. `ios/dogetionary/Core/Models/DictionaryModels.swift` - Add videoId fields
2. `ios/dogetionary/Features/Review/VideoPlayerView.swift` - New file
3. `ios/dogetionary/Core/Services/VideoCache.swift` - New file
4. `ios/dogetionary/Features/Review/PracticeWordView.swift` - Update

**See "Frontend Implementation" section above for full code.**

**Testing:**
```bash
# 1. Build iOS app
# 2. Start practice mode
# 3. Verify video loads and plays
# 4. Check video caching in Settings → Storage
# 5. Test offline mode (videos should play from cache)
```

---

### Phase 5: Production Deployment (Day 8)

**Pre-deployment Checklist:**
```bash
# 1. Database migration
docker-compose exec postgres psql -U dogeuser -d dogetionary -f /db/migrations/001_add_videos.sql

# 2. Import videos
./scripts/batch_import_videos.sh /Volumes/databank/dogetionary-videos/en en

# 3. Test backend
curl -I https://kwafy.com/api/v3/videos/1

# 4. Check CDN caching
curl -I https://kwafy.com/api/v3/videos/1 | grep -i cache

# 5. Deploy iOS app update
# 6. Monitor error rates
# 7. Check CDN bandwidth usage
```

**Deployment Steps:**
1. Backup database: `pg_dump dogetionary > backup.sql`
2. Run migration
3. Import videos
4. Deploy backend (restart app container)
5. Test endpoints
6. Deploy iOS app to TestFlight
7. Monitor for 24 hours
8. Release to production

---

## Video Management

### Video Guidelines

**Technical Specifications:**
- Format: MP4 (H.264)
- Max file size: 5MB per video
- Recommended duration: 3-10 seconds
- Resolution: 720p or 1080p
- Frame rate: 24-30 fps
- Audio: Optional (AAC codec if included)

**Content Guidelines:**
- Show clear visual representation of word/concept
- Keep videos short and focused
- Ensure good lighting and clarity
- Avoid copyrighted content
- Consider cultural appropriateness

### Video Naming Convention

```
{word}_{descriptor}.mp4

Examples:
- beautiful_sunset.mp4
- beautiful_flower.mp4
- run_person.mp4
- happy_smile.mp4
```

### Storage Estimates

| Video Count | Avg Size | Total Storage |
|-------------|----------|---------------|
| 100 videos  | 3MB      | 300MB        |
| 1,000 videos| 3MB      | 3GB          |
| 10,000 videos| 3MB     | 30GB         |

PostgreSQL can handle this easily. For 10k videos at 3MB each:
- Database size: ~30GB (well within limits)
- Backup time: ~5 minutes
- Query performance: Excellent with indexes

### Maintenance Scripts

**Check video stats:**
```sql
-- Video count and total size
SELECT
    COUNT(*) as total_videos,
    SUM(file_size_bytes) / 1024 / 1024 as total_mb,
    AVG(file_size_bytes) / 1024 / 1024 as avg_mb,
    AVG(duration_seconds) as avg_duration
FROM videos;

-- Videos not linked to anything
SELECT v.id, v.filename
FROM videos v
WHERE NOT EXISTS (SELECT 1 FROM definitions WHERE video_id = v.id)
  AND NOT EXISTS (SELECT 1 FROM test_questions WHERE video_id = v.id);

-- Most used videos
SELECT
    v.filename,
    COUNT(DISTINCT d.id) as def_count,
    COUNT(DISTINCT tq.id) as question_count
FROM videos v
LEFT JOIN definitions d ON d.video_id = v.id
LEFT JOIN test_questions tq ON tq.video_id = v.id
GROUP BY v.id, v.filename
ORDER BY (COUNT(DISTINCT d.id) + COUNT(DISTINCT tq.id)) DESC
LIMIT 20;
```

---

## Performance Optimization

### Backend Optimization

**Database Indexes:**
```sql
-- Already created in schema
CREATE INDEX idx_videos_filename ON videos(filename);
CREATE INDEX idx_definitions_video ON definitions(video_id);
CREATE INDEX idx_questions_video ON test_questions(video_id);

-- Additional optimization (if needed)
CREATE INDEX idx_videos_file_size ON videos(file_size_bytes);
```

**Query Optimization:**
```python
# Use connection pooling (already in place)
# Prepared statements (psycopg2 does this automatically)

# For large batches, consider limiting video data in initial query
# and fetching videos separately if needed
```

### Frontend Optimization

**Prefetching Strategy:**
```swift
// When batch loads, prefetch next 3 videos in background
func prefetchVideos(for words: [ReviewWord]) {
    let videoIds = words.prefix(3).compactMap { $0.definition.videoId }

    for videoId in videoIds {
        Task.detached(priority: .background) {
            await VideoCache.shared.prefetch(videoId: videoId)
        }
    }
}
```

**Memory Management:**
```swift
// Clear cache when low on memory
NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification,
    object: nil,
    queue: .main
) { _ in
    VideoCache.shared.clearOldestVideos(keepingCount: 10)
}
```

**Progressive Loading:**
```swift
// Show thumbnail first, then load full video
struct VideoPlayerView: View {
    let videoId: Int
    @State private var thumbnail: Image?
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                thumbnail
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }

            if let player = player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            loadThumbnail()
            loadVideo()
        }
    }
}
```

### CDN Optimization

**Cache Hit Rate Monitoring:**
```bash
# Check Cloudflare analytics
# Look for:
# - Cache hit rate (target: >90%)
# - Bandwidth saved (target: >80%)
# - Origin requests (should be low after warmup)
```

**Cache Warming:**
```python
# Script to warm CDN cache
# scripts/warm_cdn_cache.py

import requests

def warm_cache():
    """Fetch all videos through CDN to populate cache"""
    conn = psycopg2.connect(DATABASE_URL)
    cur = conn.cursor()

    cur.execute("SELECT id FROM videos ORDER BY id")
    video_ids = [row[0] for row in cur.fetchall()]

    base_url = "https://kwafy.com/api/v3/videos"

    for video_id in video_ids:
        url = f"{base_url}/{video_id}"
        print(f"Warming cache for video {video_id}...")
        requests.head(url)  # HEAD request to cache without downloading

    print(f"✅ Warmed cache for {len(video_ids)} videos")

# Run after deploying new videos
```

---

## Examples

### Example 1: Complete Flow

```
1. User opens practice mode
   ↓
2. App calls: GET /v3/next-review-words-batch?user_id=abc-123&count=10
   ↓
3. Backend returns:
   {
     "words": [{
       "word": "beautiful",
       "definition": {
         "text": "漂亮的",
         "video_id": 5
       },
       "questions": [{
         "video_id": 5,
         "question_text": "What does this mean?",
         ...
       }]
     }]
   }
   ↓
4. For video_id=5, app requests: GET /v3/videos/5
   ↓
5. Cloudflare CDN checks cache
   - First time: MISS → Flask → Database → Returns MP4
   - Subsequent: HIT → Returns cached MP4 (instant!)
   ↓
6. iOS saves to local cache (FileManager)
   ↓
7. VideoPlayer displays video
   ↓
8. User watches video → Answers question → Submits
```

### Example 2: Database State

```sql
-- Videos table
id | filename              | video_data | file_size_bytes | duration_seconds
---|-----------------------|------------|-----------------|------------------
1  | beautiful_sunset.mp4  | <binary>   | 3145728         | 5
2  | beautiful_flower.mp4  | <binary>   | 2621440         | 4
3  | run_person.mp4        | <binary>   | 4194304         | 6

-- Definitions table (showing video_id)
id  | word      | definition_text | learning_language | video_id
----|-----------|-----------------|-------------------|----------
100 | beautiful | 漂亮的，美丽的    | en                | 1
101 | beautiful | 漂亮的，美丽的    | en                | 2
102 | run       | 跑，奔跑         | en                | 3

-- Questions table (showing video_id)
id  | definition_id | question_text          | video_id
----|---------------|------------------------|----------
500 | 100           | What does this mean?   | 1
501 | 101           | What does this mean?   | 2
```

### Example 3: API Responses

**Request:**
```http
GET /v3/next-review-words-batch?user_id=550e8400-e29b-41d4-a716-446655440000&count=1
```

**Response:**
```json
{
  "words": [
    {
      "saved_word_id": 12345,
      "word": "beautiful",
      "definition": {
        "text": "漂亮的，美丽的",
        "video_id": 1
      },
      "questions": [
        {
          "id": 500,
          "question_text": "What does this mean?",
          "video_id": 1,
          "choices": [
            {"id": "A", "text": "漂亮的"},
            {"id": "B", "text": "丑陋的"},
            {"id": "C", "text": "普通的"},
            {"id": "D", "text": "特殊的"}
          ],
          "correct_answer": "A"
        }
      ]
    }
  ]
}
```

**Then:**
```http
GET /v3/videos/1

Response Headers:
  Content-Type: video/mp4
  Content-Length: 3145728
  Cache-Control: public, max-age=31536000, immutable
  ETag: "video-1"

Response Body:
  <binary MP4 data>
```

---

## Troubleshooting

### Common Issues

**1. Video not loading**
```
Symptoms: iOS shows loading forever
Check:
- Video ID exists in database
- video_data is not null
- Backend endpoint returns 200
- Network connectivity

Solution:
curl -I https://kwafy.com/api/v3/videos/{id}
Check for 404 or 500 errors
```

**2. Videos too slow**
```
Symptoms: Long load times (>3 seconds)
Check:
- File size (should be <5MB)
- CDN cache status (cf-cache-status header)
- Network speed

Solution:
- Compress videos: ffmpeg -i input.mp4 -vcodec h264 -acodec aac -b:v 1M output.mp4
- Check Cloudflare analytics
```

**3. Database too large**
```
Symptoms: Slow queries, backup takes long
Check:
- Total video data size: SELECT SUM(file_size_bytes) FROM videos;
- Average video size: SELECT AVG(file_size_bytes) FROM videos;

Solution:
- Delete unused videos
- Compress existing videos
- Consider file size limits
```

**4. CDN not caching**
```
Symptoms: Every request hits backend
Check:
- Response headers include Cache-Control
- Cloudflare is enabled
- cf-cache-status header (should be HIT)

Solution:
curl -I https://kwafy.com/api/v3/videos/1 | grep -i cache
Should see: Cache-Control: public, max-age=31536000
```

### Debug Queries

```sql
-- Find videos larger than 5MB
SELECT id, filename, file_size_bytes / 1024 / 1024 as size_mb
FROM videos
WHERE file_size_bytes > 5242880
ORDER BY file_size_bytes DESC;

-- Find definitions with missing videos
SELECT d.id, d.word, d.video_id
FROM definitions d
WHERE d.video_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM videos v WHERE v.id = d.video_id);

-- Count video usage
SELECT
    COUNT(DISTINCT d.video_id) as defs_with_video,
    COUNT(DISTINCT tq.video_id) as questions_with_video,
    (SELECT COUNT(*) FROM videos) as total_videos
FROM definitions d
FULL OUTER JOIN test_questions tq ON tq.video_id = d.video_id;
```

---

## Best Practices

### Video Production
1. Keep videos under 5MB
2. Use 3-10 second clips
3. Ensure good visual quality
4. Test on multiple devices
5. Consider accessibility (captions)

### Database Management
1. Regular backups before importing videos
2. Monitor database size growth
3. Index video_id columns
4. Clean up unused videos periodically

### Frontend Development
1. Always cache videos locally
2. Handle loading states gracefully
3. Provide fallback to text
4. Respect user's data preferences
5. Clear cache when storage low

### Performance Monitoring
1. Track CDN cache hit rate
2. Monitor video load times
3. Check database query performance
4. Review error logs regularly
5. User feedback on video quality

---

## Migration Guide

### For Existing Installations

If you already have a running dogetionary instance:

```bash
# 1. Backup database
docker-compose exec postgres pg_dump -U dogeuser dogetionary > backup_$(date +%Y%m%d).sql

# 2. Run migration
docker-compose exec postgres psql -U dogeuser -d dogetionary -f /db/migrations/001_add_videos.sql

# 3. Verify migration
docker-compose exec postgres psql -U dogeuser -d dogetionary -c "\d videos"

# 4. Deploy backend changes
docker-compose build app --no-cache
docker-compose up -d app

# 5. Test new endpoint
curl -I http://localhost:5001/v3/videos/1

# 6. Import test video
python scripts/import_video.py /path/to/test.mp4

# 7. Test complete flow
curl "http://localhost:5001/v3/next-review-words-batch?user_id=test&count=1" | jq .
```

### Rollback Plan

If issues occur:

```bash
# 1. Restore database
docker-compose exec postgres psql -U dogeuser dogetionary < backup_YYYYMMDD.sql

# 2. Revert code
git revert <commit-hash>

# 3. Restart services
docker-compose restart app
```

---

## Success Metrics

### Key Performance Indicators

**Week 1:**
- Videos successfully loading: >95%
- CDN cache hit rate: >80%
- Average video load time: <500ms

**Week 2:**
- CDN cache hit rate: >90%
- User engagement (video completion): >70%
- Backend video requests: <1000/day (rest from CDN)

**Month 1:**
- Total videos imported: 100+
- User satisfaction: Track feedback
- Practice completion rate: Maintain or improve

### Monitoring Dashboard

Track these metrics:
1. Video endpoint response time (p50, p95, p99)
2. CDN cache hit/miss ratio
3. Database video table size
4. Error rate (4xx, 5xx)
5. User engagement (videos watched vs skipped)

---

## Future Enhancements

### Phase 2 Features (Optional)

1. **Multiple videos per definition/question**
   - Change `video_id` to `video_ids INTEGER[]`
   - Random selection or carousel

2. **Video thumbnails**
   - Generate thumbnails on upload
   - Store as separate `thumbnail_data` column
   - Show before video loads

3. **Video analytics**
   - Track view counts
   - User completion rates
   - Popular videos

4. **Admin UI**
   - Web interface for video management
   - Upload directly from browser
   - Preview before linking

5. **Compression pipeline**
   - Auto-compress on upload
   - Multiple quality levels
   - Adaptive streaming

---

## Conclusion

This implementation plan provides:
- ✅ Complete database schema
- ✅ Backend API specification
- ✅ Frontend integration guide
- ✅ Video management tools
- ✅ CDN optimization strategy
- ✅ Step-by-step implementation phases
- ✅ Testing and deployment procedures

**Timeline: 8 days from start to production**

**Effort:**
- Backend: ~8 hours
- Frontend: ~16 hours
- Testing: ~8 hours
- Deployment: ~4 hours

**Total: ~36 hours of development**

For questions or issues, refer to the Troubleshooting section or consult this document.

---

*Last updated: 2025-12-09*
*Version: 1.0*
