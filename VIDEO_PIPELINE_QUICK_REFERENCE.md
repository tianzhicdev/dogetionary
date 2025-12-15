# Video Pipeline - Quick Reference Guide

## Database Tables

### `videos` (Primary Storage)
```sql
id | name | format | video_data (BYTEA) | transcript | audio_transcript | 
size_bytes | source_id | metadata (JSONB) | created_at
```
- Stores binary video files and metadata
- Supports Whisper API audio transcriptions
- Tracks pipeline source runs

### `word_to_video` (Many-to-Many Mapping)
```sql
id | word | learning_language | video_id | relevance_score (0.00-1.00) |
transcript_source ('metadata'|'audio') | verified_at | source_id | created_at
```
- Links words to videos
- Quality scores from LLM evaluation
- Tracks verification status

### `bundle_vocabularies` (Vocabulary Levels)
```sql
word | language | is_toefl_beginner | is_toefl_intermediate | is_toefl_advanced |
is_ielts_beginner | is_ielts_intermediate | is_ielts_advanced | is_demo |
business_english | everyday_english
```
- Links words to learning bundles/levels

---

## Key Scripts

| Script | Purpose | Input | Output |
|--------|---------|-------|--------|
| `find_videos.py` | 3-stage pipeline (search, analyze, upload) | CSV word list | Videos in DB + word mappings |
| `download_clipcafe_metadata.py` | Fetch metadata only | CSV word list | JSON metadata files |
| `download_clipcafe_videos.py` | Download MP4 files | CSV word list | MP4 files + metadata |
| `upload_videos.py` | Upload to backend | Directory structure | API upload response |
| `populate_word_to_video.py` | Create word-video links | Videos table | word_to_video table |
| `llm_approve_videos.py` | Quality assessment | Videos | Approval/rejection |
| `videos_eval_v3.py` | Generate v3.json + catalog | Videos | JSON + CSV |

---

## 3-Stage Pipeline Flow

### Stage 1: ClipCafe Search
```
Word → ClipCafe API → 100 metadata files (cached)
```
- Filters: English, 1-15s duration, sorted by views
- Rate limit: 10 req/min
- Cache: `metadata/<word>/*.json`

### Stage 2: LLM Candidate Analysis
```
Metadata → GPT-4o-mini → Relevance scores → Filter (score >= 0.6)
```
- Extracts candidate words from transcript
- Validates word appears in transcript
- Cache: `candidates/<word>/*_candidates.json`

### Stage 3: Audio + Final Analysis
```
Video → Download → Whisper API (audio transcript) → Final LLM → Upload
```
- Extracts audio → Whisper for word-level timestamps
- Final LLM validation with audio transcript
- Uploads to `/v3/admin/videos/batch-upload`

---

## API Endpoint

### Upload Videos
```
POST /v3/admin/videos/batch-upload

Request:
{
  "source_id": "find_videos_20251211_143022",
  "videos": [{
    "slug": "emergency-scene",
    "format": "mp4",
    "video_data_base64": "...",
    "size_bytes": 2097152,
    "transcript": "...",
    "audio_transcript": "...",
    "audio_transcript_verified": true,
    "whisper_metadata": {...},
    "metadata": {...},
    "word_mappings": [{
      "word": "emergency",
      "learning_language": "en",
      "relevance_score": 0.95,
      "transcript_source": "audio"
    }]
  }]
}

Response:
{
  "success": true,
  "results": [{
    "slug": "emergency-scene",
    "video_id": 42,
    "status": "created",
    "mappings_created": 3
  }],
  "total_videos": 1,
  "total_mappings": 3
}
```

### Retrieve Video
```
GET /v3/videos/<video_id>
→ Binary video data with CDN cache headers
```

---

## Metadata Formats

### ClipCafe Metadata
```json
{
  "clip_id": 398016,
  "clip_title": "Superb",
  "clip_slug": "superb",
  "duration_seconds": 4,
  "transcript": "...",
  "movie_title": "17 Miracles",
  "movie_year": 2011,
  "download_url": "https://api.clip.cafe/?...",
  "file_size_mb": 0.79
}
```

### Whisper Metadata
```json
{
  "words": [
    {"word": "emergency", "start": 0.5, "end": 1.2, "confidence": 0.98}
  ],
  "full_transcript": "...",
  "language": "en",
  "duration_seconds": 12.5
}
```

### LLM Assessment Schema
```json
{
  "educational_value_score": 0.92,
  "contextual_sufficiency_score": 0.88,
  "overall_approved": false,
  "illustrated_words": ["emergency", "situation"],
  "difficulty_level": "intermediate"
}
```

---

## Running the Pipeline

### Full Pipeline
```bash
python scripts/find_videos.py \
  --csv resources/toefl-4889.csv \
  --backend-url http://localhost:5001 \
  --max-videos 100 \
  --min-score 0.6
```

### Resume Interrupted Run
```bash
# Just re-run the same command - resumes from last checkpoint
python scripts/find_videos.py --csv resources/toefl-4889.csv
```

### Test with Single Word
```bash
echo "emergency" > test.csv
python scripts/find_videos.py --csv test.csv --max-videos 3
```

---

## Important Configurations

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `max_videos_per_word` | 100 | ClipCafe search limit |
| `min_relevance_score` | 0.6 | Quality threshold (0.0-1.0) |
| `max_mappings_per_video` | 5 | Max words per video |
| `duration` | 1-15s | Video length filter |
| `sort` | views | ClipCafe sort order |

---

## Directory Structure

```
/Volumes/databank/dogetionary-pipeline/
├── metadata/                    # Stage 1: ClipCafe responses
├── candidates/                  # Stage 2: LLM analysis
├── audio_transcripts/           # Stage 3: Whisper results
├── final_analysis/              # Stage 3: Final LLM scoring
├── videos/                      # Downloaded MP4s
├── state/                       # Resumability tracking
│   ├── processed_words.txt
│   ├── uploaded_videos.txt
│   └── failed_uploads.jsonl
└── logs/
```

---

## Cost Estimates

### ClipCafe
- **Cost**: Free (10 req/min limit on PRO)
- **Usage**: 1 request per word

### OpenAI (GPT-4o-mini)
- **Cost**: $0.15/1M input, $0.60/1M output tokens
- **Usage**: ~800 tokens per video
- **Estimate**: ~$150 for full 4,889 TOEFL words

### Storage
- **Metadata**: ~5 KB/video → ~2.4 GB for 488k videos
- **Videos**: ~2 MB/video → ~976 GB (but selective download ~100 GB)

---

## Key SQL Queries

### Get videos for a word
```sql
SELECT w.word, v.name, v.format, w.relevance_score
FROM word_to_video w
JOIN videos v ON v.id = w.video_id
WHERE w.word = 'emergency'
ORDER BY w.relevance_score DESC;
```

### Count videos per word
```sql
SELECT word, COUNT(*) as video_count
FROM word_to_video
GROUP BY word
ORDER BY video_count DESC;
```

### Find unverified videos
```sql
SELECT v.id, v.name, COUNT(*) as mapping_count
FROM videos v
LEFT JOIN word_to_video w ON v.id = w.video_id
WHERE v.audio_transcript_verified = FALSE
GROUP BY v.id;
```

---

## Common Issues & Solutions

| Problem | Solution |
|---------|----------|
| 404 on upload endpoint | Rebuild Docker: `docker-compose build app --no-cache` |
| Missing API keys | Add to `.env.secrets` in `src/` directory |
| ClipCafe 429 rate limit | Built-in retry with exponential backoff (max 5 attempts) |
| Download URL expired | Must download within 5 minutes of search |
| Slow LLM queries | Currently sequential; consider parallel processing |

---

## Environment Setup

### Required
```bash
CLIPCAFE=<api-key>
OPENAI_API_KEY=<api-key>
```

### Backend Health Check
```bash
curl http://localhost:5001/v3/health
```

### Database Connection
```bash
docker exec dogetionary-postgres-1 psql -U dogeuser -d dogetionary
```

---

## Performance Notes

- **Per word processing**: 5-10 minutes (search + LLM + audio extraction)
- **Full TOEFL (4,889 words)**: 24-48 hours sequential
- **State tracking**: Fully resumable with checkpoint system
- **Caching**: All intermediate results cached to avoid re-processing

---

## Next Steps for Integration

1. **Short term**: Add `/v3/words/<word>/videos` endpoint for video question selection
2. **Medium term**: Implement parallel word processing for speed
3. **Long term**: CDN caching, quality dashboard, bundle assignment automation

---

**Last Updated**: December 14, 2025
**Source**: VIDEO_PIPELINE_RESEARCH.md
