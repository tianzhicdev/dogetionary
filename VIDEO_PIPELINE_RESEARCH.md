# Video Download/Upload Pipeline - Comprehensive Research Report

## Executive Summary

The Dogetionary project has a sophisticated video pipeline infrastructure that handles:
1. **Metadata discovery** via ClipCafe API (1.2K line script)
2. **Video downloading** from movie clips with Whisper API transcription support
3. **LLM-based quality scoring** (GPT-4o-mini for educational value assessment)
4. **Database storage and mapping** with word-to-video relationships
5. **Backend API integration** for seamless upload

---

## 1. DATABASE SCHEMA

### 1.1 `videos` Table (Primary Video Storage)

**Location**: `/db/migrations/002_create_videos_table.sql`

```sql
CREATE TABLE videos (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,              -- Filename without extension
    format VARCHAR(10) NOT NULL,             -- mp4, mov, webm, etc.
    video_data BYTEA NOT NULL,               -- Binary video file content
    transcript TEXT,                          -- Metadata transcript (ClipCafe)
    
    -- Stage 3 additions (migration 005):
    audio_transcript TEXT,                    -- Audio transcript from Whisper
    audio_transcript_verified BOOLEAN,        -- Whisper extraction status
    whisper_metadata JSONB,                  -- Whisper API response data
    
    -- Additional fields (migration 006):
    size_bytes INTEGER,                       -- Video file size
    
    -- Pipeline tracking (migration 004):
    source_id VARCHAR(100),                   -- Pipeline run identifier
    
    metadata JSONB DEFAULT '{}',              -- Flexible metadata
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    CONSTRAINT unique_name_format UNIQUE(name, format)
);
```

**Key Indexes**:
- `idx_videos_name` - Query by video name
- `idx_videos_format` - Filter by format type
- `idx_videos_metadata` - GIN index on JSONB metadata
- `idx_videos_audio_verified` - Find verified transcripts
- `idx_videos_size_bytes` - Filter by file size
- `idx_videos_source_id` - Track pipeline runs

**Metadata Structure (JSONB Example)**:
```json
{
  "word": "emergency",
  "language": "en",
  "duration_seconds": 12.5,
  "resolution": "1920x1080",
  "codec": "h264",
  "bitrate": 800000,
  "fps": 30
}
```

---

### 1.2 `word_to_video` Table (Many-to-Many Mapping)

**Location**: `/db/migrations/003_create_word_to_video_table.sql`

```sql
CREATE TABLE word_to_video (
    id SERIAL PRIMARY KEY,
    word VARCHAR(255) NOT NULL,
    learning_language VARCHAR(10) NOT NULL,
    video_id INTEGER NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
    
    -- Quality/relevance scoring:
    relevance_score DECIMAL(3,2),  -- 0.00 to 1.00 (e.g., 0.95)
    
    -- Transcript source tracking:
    transcript_source VARCHAR(20) DEFAULT 'metadata',  -- 'metadata' or 'audio'
    verified_at TIMESTAMP,  -- When audio verification completed
    
    -- Pipeline tracking:
    source_id VARCHAR(100),  -- Pipeline run identifier
    
    created_at TIMESTAMP DEFAULT NOW(),
    
    CONSTRAINT unique_word_language_video UNIQUE(word, learning_language, video_id)
);
```

**Key Indexes**:
- `idx_word_to_video_word` - Find videos for a word
- `idx_word_to_video_video_id` - Find words for a video
- `idx_word_to_video_relevance` - Sort by quality score
- `idx_word_to_video_transcript_source` - Filter by source
- `idx_word_to_video_source_id` - Track pipeline runs

**Example Record**:
```
word='emergency', learning_language='en', video_id=42
relevance_score=0.92, transcript_source='audio', verified_at=2025-12-11T14:30:00Z
source_id='find_videos_20251211_143022'
```

---

### 1.3 `bundle_vocabularies` Table (formerly `test_vocabularies`)

**Location**: `/db/init.sql` and `/db/migration_009_bundle_vocabulary.sql`

```sql
CREATE TABLE bundle_vocabularies (
    word VARCHAR(100) NOT NULL,
    language VARCHAR(10) NOT NULL DEFAULT 'en',
    
    -- TOEFL levels (cumulative):
    is_toefl_beginner BOOLEAN DEFAULT FALSE,
    is_toefl_intermediate BOOLEAN DEFAULT FALSE,
    is_toefl_advanced BOOLEAN DEFAULT FALSE,
    
    -- IELTS levels (cumulative):
    is_ielts_beginner BOOLEAN DEFAULT FALSE,
    is_ielts_intermediate BOOLEAN DEFAULT FALSE,
    is_ielts_advanced BOOLEAN DEFAULT FALSE,
    
    -- New bundle types:
    is_demo BOOLEAN DEFAULT FALSE,
    business_english BOOLEAN DEFAULT FALSE,
    everyday_english BOOLEAN DEFAULT FALSE,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (word, language)
);
```

**Relevant for Video Pipeline**: Links vocabulary words to learning bundles. Videos are discovered and tagged for specific vocabulary levels.

---

## 2. EXISTING SCRIPTS - VIDEO ECOSYSTEM

### 2.1 Core Video Pipeline Scripts

#### **A. `download_clipcafe_metadata.py`** (600 lines)
- **Purpose**: Fetch metadata ONLY (no videos) from ClipCafe API
- **Input**: CSV file of vocabulary words
- **Output**: JSON metadata files organized by word
- **Key Features**:
  - Searches ClipCafe with filters: English, 1-15s duration, sorted by views
  - Saves metadata as `/Volumes/databank/dogetionary-metadata/<word>/<slug>_XXX.json`
  - Includes: movie info, transcript, subtitles, download URLs, cast/crew
  - Rate-limited: 10 requests/minute (PRO plan)

#### **B. `download_clipcafe_videos.py`** (330 lines)
- **Purpose**: Download actual video files from ClipCafe
- **Input**: CSV file of vocabulary words
- **Output**: MP4 video files + metadata JSON pairs
- **Storage**: `/Volumes/databank/dogetionary-videos/<word>/<slug>_XX.mp4`
- **Limitations**:
  - Download URLs valid for 5 minutes only
  - Must be called soon after metadata fetch
  - No quality filtering (downloads all found videos)

#### **C. `upload_videos.py`** (240 lines)
- **Purpose**: Upload MP3/video files from local directory to backend
- **Input**: Directory structure: `<slug>/<slug>.mp3` + `metadata.json`
- **Endpoint**: `POST /v3/admin/videos/batch-upload`
- **Payload Format**:
```json
{
  "source_id": "pipeline_run_identifier",
  "videos": [
    {
      "slug": "clip-slug",
      "name": "clip-name",
      "format": "mp3",
      "video_data_base64": "...",
      "size_bytes": 2097152,
      "transcript": "...",
      "audio_transcript": "...",
      "audio_transcript_verified": true,
      "whisper_metadata": {...},
      "metadata": {...},
      "word_mappings": [
        {
          "word": "emergency",
          "learning_language": "en",
          "relevance_score": 0.95
        }
      ]
    }
  ]
}
```

#### **D. `find_videos.py`** (1192 lines) - **MAIN PIPELINE**
- **Purpose**: 3-stage end-to-end video discovery, analysis, and upload
- **Stages**:
  1. **Stage 1 (Search)**: ClipCafe metadata discovery + caching
  2. **Stage 2 (Analysis)**: LLM-based candidate selection from metadata transcript
  3. **Stage 3 (Final)**: Audio transcript extraction + final LLM scoring
  4. **Stage 4 (Upload)**: Backend database upload

**Detailed Pipeline Flow**:

```
┌─────────────────────────────────────────────────────────────┐
│ STAGE 1: CLIPCAFE SEARCH (search_clipcafe)                  │
├─────────────────────────────────────────────────────────────┤
│ Input: Word from CSV                                         │
│ Output: 100 metadata JSON files (cached per word)            │
│                                                              │
│ Process:                                                     │
│ 1. Check cache first (metadata/<word>/*.json)               │
│ 2. Query ClipCafe API: transcript=word, duration=1-15s      │
│ 3. Rate limit handling (429 response + exponential backoff) │
│ 4. Save each clip metadata to metadata/<word>/<slug>.json   │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ STAGE 2: LLM CANDIDATE ANALYSIS (analyze_candidates)       │
├─────────────────────────────────────────────────────────────┤
│ Input: ClipCafe metadata, search word, vocabulary list      │
│ Output: LLM-analyzed candidate selection (cached)            │
│                                                              │
│ Process:                                                     │
│ 1. Check cache (candidates/<word>/<slug>_candidates.json)  │
│ 2. Extract candidate words from metadata transcript         │
│ 3. Build LLM prompt with video context                      │
│ 4. Query GPT-4o-mini for relevance scores                   │
│ 5. Validate: ensure mapped words in transcript              │
│ 6. Filter: score >= min_relevance_score (default 0.6)       │
│ 7. Cache results locally                                    │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ STAGE 3: AUDIO TRANSCRIPT & FINAL ANALYSIS                  │
├─────────────────────────────────────────────────────────────┤
│ Input: Candidate video selection                            │
│ Output: Final word mappings with confidence scores          │
│                                                              │
│ Process:                                                     │
│ 1. Download video from ClipCafe (download URL from stage 1) │
│ 2. Extract audio using ffmpeg (extract_audio_transcript)    │
│ 3. Call Whisper API to get word-level timestamps            │
│ 4. Build final LLM prompt with audio transcript             │
│ 5. Query GPT-4o-mini for final validation                   │
│ 6. Cache audio_transcripts/<word>/<slug>_whisper.json       │
│ 7. Cache final_analysis/<word>/<slug>_final.json            │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ STAGE 4: BACKEND UPLOAD (upload_to_backend)                 │
├─────────────────────────────────────────────────────────────┤
│ Input: Video file + metadata + final word mappings          │
│ Output: Uploaded to database, word_to_video links created   │
│                                                              │
│ Process:                                                     │
│ 1. Prepare batch payload (base64 encode video)              │
│ 2. POST to /v3/admin/videos/batch-upload                    │
│ 3. Mark as uploaded in state (uploaded_videos.txt)          │
│ 4. Handle idempotency (skip if already uploaded)            │
│ 5. Track failed uploads for retry                           │
└─────────────────────────────────────────────────────────────┘
```

**Caching & State Management**:
- `metadata/<word>/` - ClipCafe API responses
- `candidates/<word>/` - Stage 2 LLM analysis
- `audio_transcripts/<word>/` - Whisper transcriptions
- `final_analysis/<word>/` - Stage 3 final LLM analysis
- `videos/` - Downloaded MP4 files (optional, can delete after upload)
- `state/processed_words.txt` - Words completed
- `state/uploaded_videos.txt` - Videos in database
- `state/failed_uploads.jsonl` - Errors for retry

**Configuration**:
```python
max_videos_per_word=100      # Top 100 ClipCafe results
min_relevance_score=0.6      # Quality threshold
max_mappings_per_video=5     # Max words per video
```

---

### 2.2 Supporting Scripts

#### **E. `populate_word_to_video.py`**
- **Purpose**: Create word-to-video links from existing video metadata
- **Input**: Videos table with `metadata.word` field
- **Output**: Populated word_to_video table
- **Usage**: `python populate_word_to_video.py [--dry-run]`

#### **F. `llm_approve_videos.py`**
- **Purpose**: Evaluate videos with LLM for educational quality
- **Quality Criteria**:
  - `educational_value_score >= 0.9` (teaches the word well)
  - `contextual_sufficiency_score >= 0.9` (enough context)
- **Output**: Moves approved videos to `/Volumes/databank/llm_approved_videos/`
- **Schema**: Assessment schema with difficulty levels, illustrated words, rejection reasons

#### **G. `videos_eval_v3.py`**
- **Purpose**: Generate v3.json metadata with quality scores + catalog.csv
- **Output**: 
  - `<videoname>.v3.json` with quality assessment
  - `/Volumes/databank/shortfilms/catalog.csv` with all metadata
- **Idempotent**: Skips if v3.json already exists

---

## 3. BACKEND API ENDPOINTS

### 3.1 Video Upload Endpoint

**Endpoint**: `POST /v3/admin/videos/batch-upload`

**Location**: `/src/handlers/admin_videos.py`

**Request Format**:
```json
{
  "source_id": "find_videos_20251211_143022",  // Optional: pipeline identifier
  "videos": [
    {
      "slug": "emergency-scene",
      "name": "emergency-scene",
      "format": "mp4",
      "video_data_base64": "AAEBAg...",  // Base64-encoded video binary
      "size_bytes": 2097152,
      "transcript": "This is an emergency...",  // Metadata transcript
      "audio_transcript": "This is an emergency...",  // Whisper transcript
      "audio_transcript_verified": true,
      "whisper_metadata": {
        "words": [
          {"word": "emergency", "start": 0.5, "end": 1.2, "confidence": 0.98}
        ]
      },
      "metadata": {
        "clip_id": 12345,
        "duration_seconds": 14,
        "movie_title": "Example Film",
        "movie_year": 2020,
        "resolution": "1920x1080"
      },
      "word_mappings": [
        {
          "word": "emergency",
          "learning_language": "en",
          "relevance_score": 0.95,
          "transcript_source": "audio",
          "timestamp": 0.8
        }
      ]
    }
  ]
}
```

**Response Format**:
```json
{
  "success": true,
  "results": [
    {
      "slug": "emergency-scene",
      "video_id": 42,
      "status": "created",
      "mappings_created": 3,
      "mappings_skipped": 0
    }
  ],
  "total_videos": 1,
  "total_mappings": 3
}
```

**Handler Logic** (`_upload_single_video`):
1. Validate required fields (slug, video_data_base64)
2. Decode base64 video data
3. Check if video exists (idempotency)
4. Insert video with: `size_bytes`, `audio_transcript`, `whisper_metadata`, `source_id`
5. For each word mapping:
   - Insert/update in `word_to_video`
   - Track `transcript_source` ('metadata' or 'audio')
   - Set `verified_at` if audio-verified
6. Return summary with video_id and mapping counts

---

### 3.2 Video Retrieval Endpoint

**Endpoint**: `GET /v3/videos/<video_id>`

**Location**: `/src/handlers/videos.py`

**Response**:
- Binary video data with optimal caching headers
- MIME type detection (video/mp4, video/quicktime, etc.)
- `Cache-Control: public, max-age=31536000, immutable` (CDN-optimized)

---

## 4. METADATA STRUCTURE DETAILS

### 4.1 ClipCafe Metadata Format (ClipCafe API Response)

Example from `/resources/videos/superb/superb_03.json`:

```json
{
  "vocabulary_word": "superb",
  "video_index": 3,
  
  // Clip Information
  "clip_id": 398016,
  "clip_title": "Superb",
  "clip_slug": "superb",
  "duration_seconds": 4,
  "resolution": "1920x1080",
  "views": 350,
  "likes": 0,
  "date_added": "2022-12-02 15:33:38",
  
  // Content
  "transcript": "Albert:\n[repeatedly]\nSuperb! | Superb",
  "subtitles": "{\"1\":{\"TimeStart\":1,\"TimeEnd\":2.877,\"Text\":\"Superb\"}}",
  
  // Movie/Show Metadata
  "movie_title": "17 Miracles",
  "movie_year": 2011,
  "movie_director": "T.C. Christensen",
  "movie_writer": "T.C. Christensen, Gary Cook, Pat D. Smart",
  "movie_language": "English",
  "movie_country": "United States",
  "movie_runtime": "113 min",
  "movie_rated": "PG",
  "movie_plot": "The Willie Handcart Company treks across America...",
  "movie_imdb_score": "6.2",
  "movie_metascore": "N/A",
  "imdb_id": "tt1909270",
  
  // Cast
  "actors": "Travis Eberhard,",
  "characters": "Albert,",
  
  // TV-specific
  "season": 0,
  "episode": 0,
  
  // Images & Download
  "movie_poster": "https://m.media-amazon.com/images/...",
  "thumbnail_full": "https://clip.cafe/clipimg/superb.jpg",
  "thumbnail_16x9": "https://clip.cafe/img16x9/superb.jpg",
  "download_url": "https://api.clip.cafe/?api_key=...&key=...&slug=superb",
  
  "file_size_mb": 0.79,
  "file_path": "videos/superb/superb_03.mp4"
}
```

### 4.2 Whisper API Metadata Format

```json
{
  "words": [
    {
      "word": "emergency",
      "start": 0.5,
      "end": 1.2,
      "confidence": 0.98
    },
    {
      "word": "situation",
      "start": 1.5,
      "end": 2.1,
      "confidence": 0.95
    }
  ],
  "full_transcript": "This is an emergency situation...",
  "language": "en",
  "duration_seconds": 12.5
}
```

### 4.3 LLM Assessment Schema (Quality Scoring)

From `videos_eval_v3.py` and `llm_approve_videos.py`:

```json
{
  "educational_value_score": 0.92,
  "contextual_sufficiency_score": 0.88,
  "overall_approved": false,  // True if BOTH >= 0.9
  
  "illustrated_words": [
    "emergency",
    "situation",
    "help"
  ],
  
  "rejection_reason": "Educational value score 0.92 is below threshold 0.9",
  "educational_notes": "Video effectively demonstrates the word usage in context",
  "contextual_notes": "Scene provides clear visual context of emergency",
  "difficulty_level": "intermediate"
}
```

---

## 5. CLIP.CAFE API INTEGRATION

### 5.1 ClipCafe API Endpoint

**Base URL**: `https://api.clip.cafe/`

**Authentication**: API key in query parameter

**Search Parameters**:
```
api_key=<key>
transcript=<word>              // Search transcript for word
movie_language=English         // Filter by language
duration=1-15                  // Video duration range (seconds)
sort=views                     // Sort by popularity
order=desc                     // Descending
size=100                       // Number of results
```

**Rate Limit**: 10 requests/minute (PRO plan)

**Response Structure**:
```json
{
  "hits": {
    "hits": [
      {
        "_source": {
          "clip_id": 123,
          "title": "...",
          "slug": "...",
          "transcript": "...",
          "download": "https://api.clip.cafe/?...&key=...&slug=...",
          ...
        }
      }
    ]
  }
}
```

### 5.2 Download URL Validity

- Download URLs are valid for **5 minutes only** after search
- Must download immediately after search
- Used by `download_clipcafe_videos.py` and `find_videos.py`

---

## 6. FILE ORGANIZATION PATTERNS

### 6.1 Current Organization

**Test Videos** (already in repo):
```
/resources/videos/
├── superb/          # Word directory
│   ├── superb_01.mp4
│   ├── superb_01.json
│   ├── superb_02.mp4
│   ├── superb_02.json
│   └── ... (10 videos)
└── refer/
    ├── refer_01.mp4
    ├── refer_01.json
    └── ... (10 videos)
```

### 6.2 Pipeline Storage Structure

**find_videos.py Output**:
```
/Volumes/databank/dogetionary-pipeline/
├── metadata/                    # Stage 1: ClipCafe API responses
│   ├── emergency/
│   │   ├── emergency-scene-1.json
│   │   └── emergency-scene-2.json
│   └── injury/
│
├── candidates/                  # Stage 2: LLM candidate analysis
│   ├── emergency/
│   │   ├── emergency-scene-1_candidates.json
│   │   └── ...
│   └── injury/
│
├── audio_transcripts/           # Stage 3: Whisper API results
│   ├── emergency/
│   │   ├── emergency-scene-1_whisper.json
│   │   └── emergency-scene-1.wav
│   └── injury/
│
├── final_analysis/              # Stage 3: Final LLM scoring
│   ├── emergency/
│   │   ├── emergency-scene-1_final.json
│   │   └── ...
│   └── injury/
│
├── videos/                      # Downloaded MP4 files
│   ├── emergency-scene-1.mp4
│   ├── emergency-scene-2.mp4
│   └── ...
│
├── state/                       # Resumability tracking
│   ├── processed_words.txt      # Words completed
│   ├── uploaded_videos.txt      # Videos in database
│   └── failed_uploads.jsonl     # Errors for manual review
│
└── logs/
    └── find_videos_20251211.log
```

### 6.3 Naming Conventions

- **Video files**: `{slug}.{format}` or `{slug}_{index:02d}.{format}`
  - Example: `emergency-scene.mp4` or `emergency-scene_01.mp4`

- **Metadata files**: `{slug}.json` or `{slug}_{index:03d}.json`
  - Example: `emergency-scene.json`

- **Analysis files**: `{slug}_candidates.json`, `{slug}_final.json`, `{slug}_whisper.json`

- **State tracking**: Plain text, newline-separated
  - Example: `processed_words.txt` contains one word per line

---

## 7. LLM INTEGRATION FOR SCORING

### 7.1 OpenAI API Usage

**Model**: GPT-4o-2024-08-06

**Cost**: ~$150 for full 4,889 TOEFL words at ~800 tokens/video

### 7.2 Stage 2: Candidate Selection Prompt

```
You are an expert English language teacher evaluating video clips for vocabulary learning.

VOCABULARY WORD: "emergency"
VOCABULARY LIST: [emergency, injury, situation, critical, ...]

VIDEO INFORMATION:
- Title: "Emergency Room Scene"
- Transcript: "[Full video transcript]"
- Duration: 12 seconds

TASK:
Analyze whether this video effectively teaches any of the listed vocabulary words.

For each vocabulary word that appears in the transcript AND would be effectively taught 
by this video, provide:
1. The word
2. A relevance score (0.0 to 1.0)
3. Why this video teaches the word well

Return JSON with structure:
{
  "mappings": [
    {
      "word": "emergency",
      "relevance_score": 0.95,
      "reason": "Video shows a clear emergency situation..."
    }
  ]
}
```

### 7.3 Stage 3: Final Validation Prompt (with Audio Transcript)

```
You are evaluating if a video is suitable for teaching vocabulary words.

VIDEO: "Emergency Room Scene"
METADATA TRANSCRIPT: "[ClipCafe transcript]"
AUDIO TRANSCRIPT (from Whisper): "[Extracted from audio]"

CANDIDATE WORDS (from Stage 2): [emergency, situation, critical]

TASK:
Using BOTH the metadata AND audio transcripts, confirm if these words are 
effectively demonstrated in the video.

Return:
{
  "final_approval": true/false,
  "approved_words": ["emergency", "situation"],
  "final_scores": {
    "emergency": 0.92,
    "situation": 0.87
  }
}
```

---

## 8. PIPELINE EXECUTION

### 8.1 Command-Line Interface

**Script**: `/scripts/find_videos.sh` (shell wrapper) or Python directly

**Full Pipeline**:
```bash
python scripts/find_videos.py \
  --csv resources/toefl-4889.csv \
  --storage-dir /Volumes/databank/dogetionary-pipeline \
  --backend-url http://localhost:5001 \
  --max-videos 100 \
  --min-score 0.6
```

**Resume Interrupted Run**:
```bash
# Same command - automatically resumes from checkpoint
python scripts/find_videos.py --csv resources/toefl-4889.csv
```

### 8.2 Environment Variables

**Required** in `.env.secrets`:
```
CLIPCAFE=<clipcafe-api-key>
OPENAI_API_KEY=<openai-api-key>
```

### 8.3 Execution Time Estimates

- **Per word**: 
  - Search ClipCafe: ~6-8 seconds
  - LLM analysis (100 videos × ~2 seconds): ~200 seconds
  - Audio extraction: ~30 seconds per video
  - Total: ~5-10 minutes per word
  
- **Full TOEFL (4,889 words)**:
  - Sequential: ~24-48 hours
  - Recommended: 24-48 hour run on dedicated machine

### 8.4 Monitoring Progress

```bash
# Check processed words
wc -l /Volumes/databank/dogetionary-pipeline/state/processed_words.txt

# Check uploaded videos
wc -l /Volumes/databank/dogetionary-pipeline/state/uploaded_videos.txt

# Monitor in real-time
tail -f /Volumes/databank/dogetionary-pipeline/logs/find_videos.log
```

---

## 9. GAP ANALYSIS & MISSING PIECES

### 9.1 Known Gaps

1. **No Distributed Processing**
   - Currently single-threaded/sequential
   - Could benefit from parallel word processing

2. **Video Download Deletion**
   - After upload, downloaded MP4s aren't automatically deleted
   - Storage management is manual

3. **Error Recovery**
   - ClipCafe 5-minute URL expiration means failed downloads lose access
   - No re-download mechanism if upload fails

4. **Quality Metrics Dashboard**
   - No visualization of:
     - Videos per bundle (TOEFL beginner, intermediate, advanced)
     - Coverage percentage
     - Quality score distribution

5. **Video Selection for Questions**
   - No endpoint to query "get video for word X"
   - Need to add `/v3/words/<word>/videos` endpoint

6. **Transcript Confidence**
   - Whisper confidence scores captured but not used in filtering
   - Could set minimum confidence threshold

7. **Bundle Assignment**
   - Videos not yet tagged to vocabulary bundles (TOEFL_BEGINNER, etc.)
   - Need mechanism to assign videos to bundles based on word difficulty

8. **Caching Strategy**
   - No CDN caching configured for video service
   - Videos served from database every time (could pre-cache)

---

## 10. RECOMMENDED NEXT STEPS

### Phase 1: Understand Current State
- [x] Review database schema
- [x] Understand pipeline architecture
- [x] Review metadata structures
- [ ] Run pipeline with test words (3-5 words) to validate

### Phase 2: Implementation
- [ ] Add `/v3/words/<word>/videos` endpoint
- [ ] Implement video selection for video questions
- [ ] Add bundle assignment logic
- [ ] Create video statistics dashboard

### Phase 3: Optimization
- [ ] Implement parallel word processing
- [ ] Add video cleanup after upload
- [ ] Set Whisper confidence thresholds
- [ ] Implement CDN caching strategy

---

## 11. CRITICAL FILES SUMMARY

| File | Lines | Purpose |
|------|-------|---------|
| `/scripts/find_videos.py` | 1192 | Main 3-stage pipeline |
| `/src/handlers/admin_videos.py` | 224 | Video batch upload handler |
| `/src/handlers/videos.py` | 86 | Video retrieval endpoint |
| `/db/migrations/002_create_videos_table.sql` | 59 | Videos table schema |
| `/db/migrations/003_create_word_to_video_table.sql` | 32 | Mapping table schema |
| `/scripts/download_clipcafe_metadata.py` | 301 | Metadata-only downloader |
| `/scripts/download_clipcafe_videos.py` | 330 | Video file downloader |
| `/scripts/upload_videos.py` | 240 | Manual upload utility |
| `/scripts/FIND_VIDEOS_README.md` | 348 | Comprehensive usage guide |

---

## 12. KEY API CONTRACTS

### Upload Request/Response
```
POST /v3/admin/videos/batch-upload
Request: Videos + word mappings with base64 video data
Response: video_id, mappings_created, status (created/existed)
```

### Video Retrieval
```
GET /v3/videos/<video_id>
Response: Binary video data with CDN cache headers
```

### Word-to-Video Query (SQL)
```sql
SELECT w.word, v.name, v.format, w.relevance_score
FROM word_to_video w
JOIN videos v ON v.id = w.video_id
WHERE w.word = 'emergency'
ORDER BY w.relevance_score DESC;
```

---

**Generated**: December 14, 2025
**Project**: Dogetionary - AI-Powered Vocabulary Learning
**Status**: Ready for Phase 2 implementation
