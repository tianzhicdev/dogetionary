# Video Question Type Design

## Overview
This document outlines the design for adding video-based practice questions to the dogetionary review system. Users will watch a video clip and select the correct definition/word being demonstrated.

---

## 1. Database Schema Design

### 1.1 Word-to-Video Linking Table

**Purpose**: Many-to-many relationship between words and videos. A word can have multiple videos, and a video can be linked to multiple words.

```sql
CREATE TABLE word_to_video (
    id SERIAL PRIMARY KEY,
    word VARCHAR(255) NOT NULL,
    learning_language VARCHAR(10) NOT NULL,
    video_id INTEGER NOT NULL REFERENCES videos(id) ON DELETE CASCADE,

    -- Metadata
    relevance_score DECIMAL(3,2),  -- 0.00-1.00, how well the video demonstrates this word
    created_at TIMESTAMP DEFAULT NOW(),

    -- Composite unique constraint: each word+language can link to a video only once
    UNIQUE(word, learning_language, video_id)
);

-- Indexes for efficient lookups
CREATE INDEX idx_word_to_video_word ON word_to_video(word, learning_language);
CREATE INDEX idx_word_to_video_video_id ON word_to_video(video_id);
CREATE INDEX idx_word_to_video_relevance ON word_to_video(relevance_score DESC);
```

**Key Design Decisions**:
- **No `native_language`**: Videos are language-agnostic visual content. Only `learning_language` matters (the word being taught).
- **`relevance_score`**: Optional field for ranking videos (better videos shown first). Populated during import or by user feedback.
- **Foreign key to `videos(id)`**: CASCADE delete ensures orphan cleanup if video is removed.

### 1.2 Migration Strategy

The linking table will be populated by:
1. **Automated script**: Parse existing video metadata (`vocabulary_word` field) and create links
2. **Manual curation**: Admin interface to add/remove video links
3. **Future**: ML-based relevance scoring based on user engagement

---

## 2. New Question Type: `video_mc`

### 2.1 Question Type Overview

**Name**: `video_mc` (Video Multiple Choice)

**Format**:
- Show video clip (auto-play or tap-to-play)
- Question: "What does this video demonstrate?"
- 4 multiple-choice options (word definitions)
- User selects the correct definition

**Question Data Structure** (JSONB in `review_questions.question_data`):

```json
{
  "question_type": "video_mc",
  "word": "abdominal",
  "question_text": "Watch the video. What word is being demonstrated?",
  "video_id": 12,
  "options": [
    {
      "id": "A",
      "text": "relating to the abdomen or belly region",
      "is_correct": true
    },
    {
      "id": "B",
      "text": "relating to the chest area",
      "is_correct": false
    },
    {
      "id": "C",
      "text": "relating to the head or skull",
      "is_correct": false
    },
    {
      "id": "D",
      "text": "relating to the arms or upper limbs",
      "is_correct": false
    }
  ],
  "correct_answer": "A",
  "show_word_before_video": false  // If true, show word first; if false, reveal after answer
}
```

### 2.2 Backend Changes

#### 2.2.1 Question Generation Service

**File**: `src/services/question_generation_service.py`

**Changes**:
1. Add `'video_mc': 0.15` to `QUESTION_TYPE_WEIGHTS` (15% chance of video questions)
2. Update `get_random_question_type()` to include video questions when videos are available
3. Add new function `generate_video_mc_question()`:

```python
def generate_video_mc_question(word: str, learning_lang: str, native_lang: str, definition_data: Dict) -> Dict:
    """
    Generate a video multiple-choice question.

    Steps:
    1. Check if word has linked videos (query word_to_video table)
    2. If no videos, fallback to another question type
    3. If videos exist, select one randomly (weighted by relevance_score if available)
    4. Generate 3 distractor definitions (from similar words or LLM)
    5. Return question_data with video_id
    """
    pass
```

**Video Selection Logic**:
```sql
-- Get available videos for a word
SELECT v.id, v.name, wtv.relevance_score
FROM word_to_video wtv
JOIN videos v ON v.id = wtv.video_id
WHERE wtv.word = %s
  AND wtv.learning_language = %s
ORDER BY wtv.relevance_score DESC NULLS LAST, RANDOM()
LIMIT 1;
```

#### 2.2.2 Review Questions Table

**No schema change needed** - `review_questions.question_data` is already JSONB and supports arbitrary question structures.

**Cache behavior**:
- Cache key: `(word, learning_language, native_language, 'video_mc')`
- Since video_id is in question_data, each cached question is tied to a specific video
- Multiple video_mc questions for same word = multiple cache entries (not ideal, but acceptable for v1)

#### 2.2.3 Reviews Table

**No schema change needed** - `reviews.question_type` already accepts varchar(50), just add `'video_mc'` to valid values.

Update comment:
```sql
COMMENT ON COLUMN reviews.question_type IS 'Type of question shown during review: recognition, mc_definition, mc_word, fill_blank, pronounce_sentence, video_mc';
```

#### 2.2.4 Video Endpoint

**New endpoint**: `/v3/videos/<int:video_id>`

```python
@v3_api.route('/videos/<int:video_id>', methods=['GET'])
def get_video(video_id: int):
    """
    Serve video binary data for CDN caching.

    Response:
    - Content-Type: video/mp4 (or video/{format})
    - Cache-Control: public, max-age=31536000, immutable
    - Body: Raw video bytes
    """
    video = db_fetch_one("SELECT video_data, format FROM videos WHERE id = %s", (video_id,))

    if not video:
        return jsonify({"error": "Video not found"}), 404

    return Response(
        video['video_data'],
        mimetype=f"video/{video['format']}",
        headers={
            'Cache-Control': 'public, max-age=31536000, immutable',
            'X-Content-Type-Options': 'nosniff'
        }
    )
```

**Why separate endpoint?**:
- CDN (Cloudflare) can cache individual videos indefinitely
- Batch API stays lightweight (only returns video IDs, not blobs)
- iOS can prefetch videos in background

---

## 3. iOS Changes

### 3.1 Model Updates

**File**: `ios/dogetionary/dogetionary/Core/Models/DictionaryModels.swift`

#### 3.1.1 Update `ReviewQuestion` struct

```swift
struct ReviewQuestion: Codable {
    let question_type: String  // Add: "video_mc"
    let word: String
    let question_text: String
    let options: [QuestionOption]?
    let correct_answer: String?
    let sentence: String?
    let sentence_translation: String?
    let show_definition: Bool?
    let audio_url: String?
    let evaluation_threshold: Double?

    // NEW: Video question fields
    let video_id: Int?  // Present for video_mc type
    let show_word_before_video: Bool?  // If true, reveal word before playing video

    private enum CodingKeys: String, CodingKey {
        case question_type, word, question_text, options, correct_answer
        case sentence, sentence_translation, show_definition, audio_url
        case evaluation_threshold, video_id, show_word_before_video
    }
}
```

### 3.2 Video Service

**New file**: `ios/dogetionary/dogetionary/Core/Services/VideoService.swift`

```swift
import Foundation
import Combine

class VideoService {
    static let shared = VideoService()
    private let baseURL: String

    init() {
        #if DEBUG
        baseURL = "http://localhost:5001"
        #else
        baseURL = "https://kwafy.com/api"
        #endif
    }

    /// Download video from backend
    func fetchVideo(videoId: Int) -> AnyPublisher<URL, Error> {
        // 1. Check local cache first (FileManager)
        // 2. If not cached, download from /v3/videos/{videoId}
        // 3. Save to cache and return local file URL
    }

    /// Preload videos for upcoming questions
    func preloadVideos(videoIds: [Int]) {
        // Background download for better UX
    }

    /// Clear old cached videos (LRU policy)
    func clearCache(olderThanDays: Int = 7) {
        // Cleanup to save space
    }
}
```

### 3.3 UI Components

#### 3.3.1 New View: `VideoQuestionView.swift`

```swift
import SwiftUI
import AVKit

struct VideoQuestionView: View {
    let question: ReviewQuestion
    let onAnswer: (String) -> Void

    @State private var videoURL: URL?
    @State private var isLoading = true
    @State private var showWord = false

    var body: some View {
        VStack(spacing: 20) {
            // Word display (conditional)
            if showWord || question.show_word_before_video == true {
                Text(question.word)
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }

            // Video player
            if let url = videoURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 300)
                    .cornerRadius(12)
            } else if isLoading {
                ProgressView("Loading video...")
                    .frame(height: 300)
            }

            // Question text
            Text(question.question_text)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()

            // Multiple choice options
            ForEach(question.options ?? [], id: \.id) { option in
                Button(action: {
                    onAnswer(option.id)
                    showWord = true  // Reveal word after answering
                }) {
                    Text(option.text)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .onAppear {
            loadVideo()
        }
    }

    private func loadVideo() {
        guard let videoId = question.video_id else {
            isLoading = false
            return
        }

        VideoService.shared.fetchVideo(videoId: videoId)
            .sink(
                receiveCompletion: { _ in isLoading = false },
                receiveValue: { url in
                    videoURL = url
                    isLoading = false
                }
            )
            .store(in: &cancellables)
    }
}
```

#### 3.3.2 Update `ReviewView.swift`

Add switch case for rendering `video_mc` questions:

```swift
func questionView(for question: ReviewQuestion) -> some View {
    switch question.question_type {
    case "recognition":
        return AnyView(RecognitionQuestionView(...))
    case "mc_definition", "mc_word":
        return AnyView(MultipleChoiceView(...))
    case "fill_blank":
        return AnyView(FillBlankView(...))
    case "pronounce_sentence":
        return AnyView(PronunciationView(...))
    case "video_mc":
        return AnyView(VideoQuestionView(question: question, onAnswer: submitAnswer))
    default:
        return AnyView(Text("Unknown question type"))
    }
}
```

### 3.4 Video Caching Strategy

**Cache Location**: `FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)/videos/`

**Cache Policy**:
- Max cache size: 500 MB
- LRU eviction when cache is full
- Videos persist across app launches (not cleared on app restart)

**Prefetching**:
- When batch API returns questions, extract all `video_id` values
- Trigger background download for all videos in parallel
- User can start reviewing while videos download (show loading spinner if not ready)

---

## 4. Question Generation Logic

### 4.1 When to Show Video Questions

**Conditions**:
1. Word has at least 1 linked video in `word_to_video` table
2. Random selection picks `video_mc` type (15% weight)
3. Video file exists and is accessible

**Fallback**: If video unavailable (deleted, corrupt), silently fallback to `mc_definition` type.

### 4.2 Distractor Generation

For video_mc questions, we need 3 incorrect options + 1 correct definition.

**Strategy 1: Semantic similarity (preferred)**
```sql
-- Find words with similar meanings (requires embeddings or manual tagging)
SELECT definition_data->>'short_definition' as distractor
FROM definitions
WHERE learning_language = %s
  AND word != %s
  AND word IN (SELECT similar_word FROM word_similarity WHERE word = %s)
LIMIT 3;
```

**Strategy 2: Random from same difficulty level (fallback)**
```sql
-- Get random definitions from test vocabulary at same level
SELECT definition_data->>'short_definition' as distractor
FROM definitions
WHERE learning_language = %s
  AND word != %s
  AND word IN (SELECT word FROM test_vocabulary WHERE vocabulary_type = %s)
ORDER BY RANDOM()
LIMIT 3;
```

**Strategy 3: LLM generation (highest quality, slower)**
```python
# Prompt: "Generate 3 plausible but incorrect definitions for '{word}'
# that could confuse learners. The correct definition is: '{correct_def}'"
```

### 4.3 Relevance Scoring

**Initial population** (script):
- All video links get `relevance_score = NULL` initially
- No ranking, videos selected randomly

**Future improvements**:
- Track user engagement (video completion rate, answer correctness)
- Videos with higher answer accuracy get higher relevance scores
- Videos with low engagement get deprioritized or removed

---

## 5. Implementation Phases

### Phase 1: Database Setup (1 hour)
- [x] Create `videos` table (already done)
- [ ] Create `word_to_video` table migration
- [ ] Write script to populate `word_to_video` from existing video metadata
- [ ] Verify data integrity

### Phase 2: Backend Implementation (4 hours)
- [ ] Add `/v3/videos/<id>` endpoint
- [ ] Update `question_generation_service.py` to support `video_mc`
- [ ] Add video question generation logic
- [ ] Update `QUESTION_TYPE_WEIGHTS` to include `video_mc`
- [ ] Write integration tests for video questions

### Phase 3: iOS Implementation (8 hours)
- [ ] Update `ReviewQuestion` model with video fields
- [ ] Create `VideoService` for fetching/caching videos
- [ ] Implement `VideoQuestionView` component
- [ ] Integrate video questions into review flow
- [ ] Add video prefetching logic
- [ ] Test on real device with real videos

### Phase 4: Testing & Refinement (3 hours)
- [ ] Test with production videos
- [ ] Verify CDN caching works correctly
- [ ] Measure video load times and optimize
- [ ] Gather user feedback on question difficulty
- [ ] Tune distractor generation quality

**Total Estimated Time**: ~16 hours

---

## 6. API Contract Examples

### 6.1 Batch Review Response with Video Question

**Request**: `GET /v3/review/batch?limit=10`

**Response**:
```json
{
  "questions": [
    {
      "word": "abdominal",
      "saved_word_id": 123,
      "source": "test_practice",
      "position": 0,
      "learning_language": "en",
      "native_language": "zh",
      "question": {
        "question_type": "video_mc",
        "word": "abdominal",
        "question_text": "Watch the video. What word is being demonstrated?",
        "video_id": 12,
        "show_word_before_video": false,
        "options": [
          {"id": "A", "text": "relating to the abdomen", "is_correct": true},
          {"id": "B", "text": "relating to the chest", "is_correct": false},
          {"id": "C", "text": "relating to the head", "is_correct": false},
          {"id": "D", "text": "relating to the arms", "is_correct": false}
        ],
        "correct_answer": "A"
      },
      "definition": { ... }
    },
    ...
  ],
  "total_available": 25,
  "has_more": true
}
```

### 6.2 Video Fetch Request

**Request**: `GET /v3/videos/12`

**Response**:
```
HTTP/1.1 200 OK
Content-Type: video/mp4
Content-Length: 4380446
Cache-Control: public, max-age=31536000, immutable
X-Content-Type-Options: nosniff

<binary video data>
```

### 6.3 Submit Review with Video Question

**Request**: `POST /v3/review`

```json
{
  "user_id": "uuid",
  "word": "abdominal",
  "learning_language": "en",
  "native_language": "zh",
  "response": true,
  "question_type": "video_mc"
}
```

**Response**: (same as existing review submission)

---

## 7. Edge Cases & Error Handling

### 7.1 Video Not Available
- **Scenario**: Video deleted or corrupted after question was cached
- **Handling**:
  - Backend returns 404 for `/v3/videos/{id}`
  - iOS shows error message: "Video unavailable, showing text question instead"
  - Fallback to `mc_definition` question type automatically

### 7.2 No Videos for Word
- **Scenario**: Word has no linked videos in `word_to_video`
- **Handling**:
  - `generate_video_mc_question()` returns None
  - Question generation service falls back to another question type
  - User never sees an error (seamless fallback)

### 7.3 Video Download Fails
- **Scenario**: Network timeout, server error during video fetch
- **Handling**:
  - Show retry button in iOS
  - After 3 retries, skip to next question
  - Log error for monitoring

### 7.4 Slow Video Loading
- **Scenario**: Large video file on slow connection
- **Handling**:
  - Show progress bar during download
  - Cache videos ahead of time (prefetch on batch load)
  - Consider video compression if files too large (>10MB)

---

## 8. Future Enhancements

### 8.1 Video Quality Variants
- Store multiple resolutions (480p, 720p, 1080p)
- Serve appropriate quality based on device/connection

### 8.2 Adaptive Difficulty
- Track which videos are too easy/hard
- Adjust video selection based on user proficiency

### 8.3 User-Generated Videos
- Allow users to submit videos for words
- Crowdsource video content moderation

### 8.4 Video Playlists
- "Watch 5 videos and answer questions" mode
- Binge-learning for visual learners

### 8.5 Subtitle Support
- Extract subtitles from video metadata
- Show/hide subtitles toggle in player

---

## 9. Migration Script Design

### 9.1 Populate `word_to_video` Table

**Script**: `scripts/populate_word_to_video.py`

```python
#!/usr/bin/env python3
"""
Populate word_to_video linking table from existing video metadata.

Reads all videos from the database, extracts the vocabulary_word from metadata,
and creates links in the word_to_video table.
"""

import psycopg2
import json

def populate_links():
    conn = psycopg2.connect(
        host='localhost',
        database='dogetionary',
        user='dogeuser',
        password='dogepass'
    )

    cursor = conn.cursor()

    # Fetch all videos with metadata
    cursor.execute("""
        SELECT id, metadata
        FROM videos
        WHERE metadata->>'word' IS NOT NULL
    """)

    videos = cursor.fetchall()

    links_created = 0
    for video_id, metadata in videos:
        word = metadata.get('word')
        # Assume English for now (can be enhanced to detect from metadata)
        learning_language = metadata.get('language', 'en')

        if word:
            cursor.execute("""
                INSERT INTO word_to_video (word, learning_language, video_id)
                VALUES (%s, %s, %s)
                ON CONFLICT (word, learning_language, video_id) DO NOTHING
            """, (word, learning_language, video_id))

            links_created += cursor.rowcount

    conn.commit()
    print(f"Created {links_created} word-to-video links")

    cursor.close()
    conn.close()

if __name__ == '__main__':
    populate_links()
```

---

## 10. Monitoring & Metrics

**Metrics to track**:
- Video question frequency (% of total questions)
- Video load success rate
- Average video load time
- User answer accuracy for video_mc vs other types
- Most popular videos (by view count)
- Cache hit rate

**Logging**:
- Log every video question generation
- Log video fetch failures
- Log cache hits/misses

---

## Summary

This design adds a flexible, scalable video question system to dogetionary:

1. **`word_to_video` table**: Many-to-many linking with optional relevance scoring
2. **`video_mc` question type**: Video multiple-choice questions with 4 options
3. **Backend**: New `/v3/videos/{id}` endpoint + question generation logic
4. **iOS**: Video player component + caching service
5. **16-hour implementation** across 4 phases

The design reuses existing infrastructure (JSONB question_data, batch API, CDN caching) and gracefully handles edge cases with fallbacks. Videos enhance learning through visual context while maintaining system performance.
