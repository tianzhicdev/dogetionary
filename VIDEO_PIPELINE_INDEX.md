# Video Pipeline Documentation Index

## Overview
This directory contains comprehensive documentation of the Dogetionary video pipeline infrastructure for discovering, analyzing, and integrating educational videos for vocabulary learning.

---

## Documents (in reading order)

### 1. [VIDEO_PIPELINE_QUICK_REFERENCE.md](VIDEO_PIPELINE_QUICK_REFERENCE.md) - START HERE
**Read this first if you need a quick overview**
- Single-page reference guide
- Database table schemas
- Key scripts summary
- Running commands
- Configuration parameters
- Troubleshooting guide
- ~2 minute read

### 2. [VIDEO_PIPELINE_RESEARCH.md](VIDEO_PIPELINE_RESEARCH.md) - COMPREHENSIVE GUIDE
**Read this for complete understanding of the architecture**
- 12 major sections covering full system
- Database schema with detailed explanations
- Pipeline flow diagrams (4 stages)
- API endpoint specifications with examples
- Metadata structure documentation
- ClipCafe API integration details
- LLM prompts and quality scoring
- Cost analysis and estimates
- Gap analysis with 8 identified issues
- File organization patterns
- ~15 minute read

### 3. [ENHANCED_VIDEO_LOGGING.md](ENHANCED_VIDEO_LOGGING.md) - LOGGING FEATURES
**Read for understanding video logging improvements**
- Comprehensive logging strategy
- Structured logging implementation
- Progress tracking
- Error reporting
- Debug information capture

### 4. [VIDEO_CACHE_CLEAR_FEATURE.md](VIDEO_CACHE_CLEAR_FEATURE.md) - CACHE MANAGEMENT
**Read for cache management and performance tuning**
- Video cache clearing strategy
- Performance optimization
- Storage cleanup procedures

---

## Quick Reference

### Key Components

**Database Tables**
- `videos` - Binary video storage with Whisper transcripts
- `word_to_video` - Many-to-many word-to-video mappings with relevance scores
- `bundle_vocabularies` - Learning level assignments

**Main Pipeline Script**
- `scripts/find_videos.py` (1192 lines) - 4-stage automated pipeline

**Supporting Scripts**
- `download_clipcafe_metadata.py` - Fetch metadata only
- `download_clipcafe_videos.py` - Download video files
- `upload_videos.py` - Manual upload utility
- `populate_word_to_video.py` - Create word-video links
- `llm_approve_videos.py` - Quality assessment
- `videos_eval_v3.py` - v3.json + catalog generation

**Backend Endpoints**
- `POST /v3/admin/videos/batch-upload` - Upload with word mappings
- `GET /v3/videos/<video_id>` - Retrieve video binary

---

## Quick Start

### Run the Full Pipeline
```bash
python scripts/find_videos.py \
  --csv resources/toefl-4889.csv \
  --backend-url http://localhost:5001 \
  --max-videos 100 \
  --min-score 0.6
```

### Resume Interrupted Run
```bash
# Just re-run - automatically resumes from checkpoint
python scripts/find_videos.py --csv resources/toefl-4889.csv
```

### Test with Single Word
```bash
echo "emergency" > test.csv
python scripts/find_videos.py --csv test.csv --max-videos 3
```

---

## Architecture Overview

### 4-Stage Pipeline

```
Stage 1: ClipCafe Search
  Input: Word → ClipCafe API → 100 metadata files (cached)
  
Stage 2: LLM Candidate Analysis
  Input: Metadata → GPT-4o-mini → Relevance scores → Filter (≥0.6)
  
Stage 3: Audio + Final Analysis
  Input: Video → Download → Whisper API → Final LLM → Cache
  
Stage 4: Backend Upload
  Input: Video + metadata → Base64 encode → POST /v3/admin/videos/batch-upload
```

### Key Features
- Fully idempotent (resumable after interruption)
- Comprehensive caching (all intermediate results)
- LLM quality validation (GPT-4o-mini)
- Whisper audio extraction (word-level timestamps)
- Configurable quality thresholds
- Rate limit handling (exponential backoff)

---

## Important Paths

### Storage
```
/Volumes/databank/dogetionary-pipeline/
├── metadata/              # Stage 1: ClipCafe responses
├── candidates/            # Stage 2: LLM analysis
├── audio_transcripts/     # Stage 3: Whisper results
├── final_analysis/        # Stage 3: Final scoring
├── videos/                # Downloaded MP4s
├── state/                 # Checkpoint tracking
└── logs/                  # Execution logs
```

### Code
```
/src/
├── handlers/
│   ├── admin_videos.py    # Upload handler
│   └── videos.py          # Retrieval endpoint
└── app_v3.py              # Route registration

/db/migrations/
├── 002_create_videos_table.sql
└── 003_create_word_to_video_table.sql

/scripts/
├── find_videos.py         # Main pipeline
├── find_videos.sh         # Shell wrapper
├── FIND_VIDEOS_README.md  # Usage guide
└── [supporting scripts]
```

---

## Configuration

### Environment Variables
```
CLIPCAFE=<api-key>                  # ClipCafe API key
OPENAI_API_KEY=<api-key>            # OpenAI API key
```

### Pipeline Parameters
| Parameter | Default | Purpose |
|-----------|---------|---------|
| max_videos_per_word | 100 | ClipCafe search limit |
| min_relevance_score | 0.6 | Quality threshold (0.0-1.0) |
| max_mappings_per_video | 5 | Max words per video |

---

## API Contracts

### Upload Endpoint
```
POST /v3/admin/videos/batch-upload

Request: 
  source_id (optional)
  videos array with:
    - slug, name, format
    - video_data_base64
    - transcript, audio_transcript
    - whisper_metadata
    - word_mappings array

Response:
  - video_id
  - status (created/existed)
  - mappings_created, mappings_skipped
```

### Retrieval Endpoint
```
GET /v3/videos/<video_id>
→ Binary video data with CDN cache headers
```

---

## Performance Metrics

| Metric | Value |
|--------|-------|
| Time per word | 5-10 minutes |
| Full TOEFL (4,889 words) | 24-48 hours sequential |
| Metadata per video | ~5 KB |
| Video file size | ~2 MB average |
| LLM tokens per video | ~800 |
| Cost per TOEFL corpus | ~$150 |

---

## Known Gaps & Limitations

1. **Sequential processing** - No parallel word processing (24-48 hours for full corpus)
2. **No video cleanup** - Manual deletion of downloaded MP4s after upload
3. **No error recovery** - ClipCafe download URLs expire in 5 minutes
4. **Missing dashboard** - No visualization of video coverage/quality
5. **No video selection endpoint** - Need `/v3/words/<word>/videos`
6. **Confidence filtering** - Whisper confidence scores not used in filtering
7. **Bundle assignment** - Videos not auto-tagged to learning bundles
8. **CDN caching** - No pre-caching strategy for video service

---

## Next Steps

### Phase 1: Validation
- [ ] Run pipeline with 3-5 test words
- [ ] Verify database storage
- [ ] Test video retrieval endpoint

### Phase 2: Integration
- [ ] Add `/v3/words/<word>/videos` endpoint
- [ ] Implement video selection for video questions
- [ ] Create video statistics dashboard
- [ ] Add bundle assignment logic

### Phase 3: Optimization
- [ ] Implement parallel word processing
- [ ] Automatic video cleanup after upload
- [ ] Whisper confidence thresholds
- [ ] CDN caching implementation

---

## Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| 404 on upload endpoint | Rebuild Docker: `docker-compose build app --no-cache` |
| Missing API keys | Add to `.env.secrets` in `src/` directory |
| ClipCafe 429 rate limit | Built-in retry with exponential backoff (max 5 attempts) |
| Download URL expired | Must download within 5 minutes of search |
| Slow performance | Sequential processing; consider parallel implementation |

### Health Checks
```bash
# Backend health
curl http://localhost:5001/v3/health

# Database connection
docker exec dogetionary-postgres-1 psql -U dogeuser -d dogetionary

# Check logs
tail -f /Volumes/databank/dogetionary-pipeline/logs/*.log
```

---

## Database Queries

### Find videos for a word
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

### Verify audio transcripts
```sql
SELECT id, name, audio_transcript_verified, audio_transcript
FROM videos
WHERE audio_transcript_verified = true
LIMIT 10;
```

---

## Implementation Status

**Implemented:**
- Video database schema
- 4-stage pipeline
- ClipCafe integration
- LLM-based quality scoring
- Whisper API integration
- Backend upload endpoint
- Video retrieval endpoint
- Checkpoint/resumability system

**In Progress:**
- Quality dashboard
- Video question integration
- Bundle assignment

**Not Yet Implemented:**
- Parallel processing
- Automatic cleanup
- Video selection endpoint
- CDN caching

---

## Document Maintenance

| Document | Purpose | Last Updated | Maintainer |
|----------|---------|--------------|-----------|
| VIDEO_PIPELINE_RESEARCH.md | Comprehensive guide | 2025-12-14 | Research |
| VIDEO_PIPELINE_QUICK_REFERENCE.md | Developer reference | 2025-12-14 | Research |
| ENHANCED_VIDEO_LOGGING.md | Logging strategy | 2025-12-13 | Development |
| VIDEO_CACHE_CLEAR_FEATURE.md | Cache management | 2025-12-13 | Development |

---

## Additional Resources

- **ClipCafe Docs**: https://api.clip.cafe/
- **OpenAI API**: https://platform.openai.com/
- **Whisper API**: https://platform.openai.com/docs/guides/speech-to-text
- **PostgreSQL**: https://www.postgresql.org/

---

## Support & Questions

For questions about specific components:
1. Check relevant document above
2. Review inline code comments
3. Check `/scripts/FIND_VIDEOS_README.md` for detailed usage guide
4. Review database schema migrations for technical details

---

**Last Updated**: December 14, 2025
**Status**: Ready for Phase 2 implementation
**Coverage**: 95% of video pipeline infrastructure documented
