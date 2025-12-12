# Video Discovery Pipeline - Usage Guide

## Overview

The `find_videos.sh` script orchestrates an end-to-end pipeline that:
1. Searches ClipCafe API for videos containing vocabulary words
2. Analyzes videos with LLM (GPT-4o-mini) to identify teachable words
3. Downloads quality videos
4. Uploads videos and word-to-video mappings to the backend database

**Key Features:**
- ✅ **Idempotent**: Safe to resume after interruption, won't duplicate data
- ✅ **Cached**: All intermediate results cached locally (metadata, analysis, videos)
- ✅ **Parameterized**: Configurable storage dir, backend URL, word list
- ✅ **Quality-filtered**: Only uploads videos with relevance score ≥ 0.6
- ✅ **Transcript-validated**: Ensures mapped words actually appear in transcript

---

## Quick Start

### Prerequisites

1. **API Keys**: Ensure `.env.secrets` file exists with:
   ```
   CLIPCAFE=<your-clipcafe-api-key>
   OPENAI_API_KEY=<your-openai-api-key>
   ```

2. **Backend Running**: Start the backend server (Docker or local)
   ```bash
   docker-compose up -d
   ```

3. **Python Dependencies**: Ensure required packages are installed
   ```bash
   pip install requests python-dotenv
   ```

### Basic Usage

```bash
# Test with local backend (default)
./scripts/find_videos.sh --csv scripts/test_words.csv

# Production with kwafy.com backend
./scripts/find_videos.sh --csv resources/toefl-4889.csv --backend-url https://kwafy.com/api

# Custom storage location
./scripts/find_videos.sh --csv words.csv --storage-dir /custom/path
```

---

## Command-Line Options

```
--csv <file>           Path to CSV file with word list (REQUIRED)
--storage-dir <dir>    Base directory for caching (default: /Volumes/databank/dogetionary-pipeline)
--backend-url <url>    Backend API URL (default: http://localhost:5000)
--max-videos <n>       Max videos per word (default: 100)
--min-score <float>    Min relevance score (default: 0.6)
```

### Examples

```bash
# Test with 3 videos per word, localhost backend
./scripts/find_videos.sh --csv test.csv --max-videos 3 --backend-url http://localhost:5001

# Production run with higher quality threshold
./scripts/find_videos.sh --csv toefl.csv --backend-url https://kwafy.com/api --min-score 0.7

# Resume interrupted pipeline (uses cached state)
./scripts/find_videos.sh --csv toefl.csv  # Just re-run the same command!
```

---

## Directory Structure

The pipeline creates this structure in the storage directory:

```
/Volumes/databank/dogetionary-pipeline/
├── metadata/                    # ClipCafe API responses
│   ├── emergency/
│   │   ├── clip-slug-1.json
│   │   └── clip-slug-2.json
│   └── injury/
│       └── ...
│
├── analysis/                    # LLM analysis results
│   ├── emergency/
│   │   ├── clip-slug-1_analysis.json
│   │   └── ...
│   └── injury/
│       └── ...
│
├── videos/                      # Downloaded video files
│   ├── clip-slug-1.mp4
│   ├── clip-slug-2.mp4
│   └── ...
│
├── state/
│   ├── processed_words.txt      # Words completed
│   ├── uploaded_videos.txt      # Videos uploaded to DB
│   └── failed_uploads.jsonl     # Failed attempts
│
└── logs/
    └── ...
```

---

## Pipeline Stages

### Stage 1: Search ClipCafe
- Searches ClipCafe API for videos containing the word
- Fetches top N videos (default: 100) sorted by popularity
- Caches metadata JSON locally
- **Idempotency**: Skips if metadata already cached

### Stage 2: LLM Analysis
- For each video:
  - Extracts words from transcript
  - Queries GPT-4o-mini: "Which vocabulary words does this video teach well?"
  - Validates word appears in transcript (prevents hallucination)
  - Filters by relevance score threshold (default: ≥ 0.6)
- Caches analysis results locally
- **Idempotency**: Skips if analysis already cached

### Stage 3: Download Videos
- Downloads video files from ClipCafe (only quality videos)
- Caches locally as MP4 files
- **Idempotency**: Skips if video already downloaded

### Stage 4: Upload to Backend
- Uploads video binary + metadata to `/v3/admin/videos/batch-upload`
- Creates word-to-video mappings with relevance scores
- Tracks uploaded videos in state
- **Idempotency**: Skips if video already uploaded

---

## Resumability & Idempotency

The pipeline is fully resumable. If interrupted:

```bash
# Just re-run the same command - it will resume where it left off
./scripts/find_videos.sh --csv words.csv
```

**What gets cached:**
- ✅ ClipCafe metadata (avoid re-downloading)
- ✅ LLM analysis results (avoid re-querying API, saves $$)
- ✅ Video files (avoid re-downloading)
- ✅ Upload status (avoid re-uploading to DB)

**State tracking:**
- `processed_words.txt`: Words fully completed
- `uploaded_videos.txt`: Videos successfully uploaded
- `failed_uploads.jsonl`: Failed attempts for manual review

---

## Cost Estimates

### ClipCafe API
- **Cost**: Free (10 requests/minute limit)
- **Usage**: 1 request per word

### OpenAI API (GPT-4o-mini)
- **Cost**: $0.15 per 1M input tokens, $0.60 per 1M output tokens
- **Usage**: ~800 tokens per video (500 input + 300 output)
- **Estimate**:
  - 100 videos/word × 4,889 words = 488,900 videos
  - ~$150 for full TOEFL corpus

### Storage
- **Metadata**: ~5 KB per video → ~2.4 GB for 488k videos
- **Videos**: ~2 MB per video → ~976 GB for 488k videos (selective download reduces this)
- **Recommended**: Keep top 10 videos/word → ~100 GB total

---

## Troubleshooting

### "404 Not Found" on upload endpoint

**Problem**: Backend doesn't have the new endpoint

**Solution**: Rebuild Docker container
```bash
docker-compose build app --no-cache
docker-compose up -d app
```

### "Missing API keys" error

**Problem**: `.env.secrets` file not found or missing keys

**Solution**: Check file exists at `src/.env.secrets` with:
```
CLIPCAFE=<key>
OPENAI_API_KEY=<key>
```

### Pipeline running too slow

**Problem**: LLM API calls are sequential

**Solution**: Current implementation is single-threaded. For production, consider:
- Running multiple instances for different word ranges
- Using faster LLM model (Groq, local model)

### Database connection errors

**Problem**: Backend database not accessible

**Solution**:
```bash
# Check Docker status
docker-compose ps

# Check backend health
curl http://localhost:5001/v3/health

# Restart if needed
docker-compose restart app postgres
```

---

## Production Deployment

### For kwafy.com backend

```bash
./scripts/find_videos.sh \
  --csv resources/toefl-4889.csv \
  --backend-url https://kwafy.com/api \
  --storage-dir /Volumes/databank/dogetionary-pipeline \
  --max-videos 20 \
  --min-score 0.7
```

**Recommendations:**
- Run on a machine with good bandwidth (downloading videos)
- Use `nohup` or `tmux` for long-running process
- Monitor logs in `storage-dir/logs/`
- Expect 24-48 hours for full TOEFL corpus

### Monitoring Progress

```bash
# Check processed words
wc -l /Volumes/databank/dogetionary-pipeline/state/processed_words.txt

# Check uploaded videos
wc -l /Volumes/databank/dogetionary-pipeline/state/uploaded_videos.txt

# Check failed uploads
cat /Volumes/databank/dogetionary-pipeline/state/failed_uploads.jsonl

# Watch live logs
tail -f /Volumes/databank/dogetionary-pipeline/logs/*.log
```

---

## Testing

### Test with single word

```bash
# Create test file
echo "emergency" > test_word.csv

# Run pipeline
./scripts/find_videos.sh --csv test_word.csv --max-videos 3

# Verify in database
docker exec dogetionary-postgres-1 psql -U dogeuser -d dogetionary -c \
  "SELECT word, COUNT(*) FROM word_to_video GROUP BY word;"
```

### Test video retrieval

```bash
# Get video ID from database
VIDEO_ID=9251

# Fetch video (should return binary data)
curl http://localhost:5001/v3/videos/$VIDEO_ID --output test_video.mp4

# Play video
open test_video.mp4
```

---

## Database Queries

### Check word-to-video mappings

```sql
-- Count videos per word
SELECT word, learning_language, COUNT(*) as video_count
FROM word_to_video
GROUP BY word, learning_language
ORDER BY video_count DESC
LIMIT 20;

-- Get videos for specific word
SELECT w.word, v.name, w.relevance_score
FROM word_to_video w
JOIN videos v ON v.id = w.video_id
WHERE w.word = 'emergency'
ORDER BY w.relevance_score DESC;

-- Find words with no videos
SELECT DISTINCT word
FROM saved_words
WHERE word NOT IN (SELECT DISTINCT word FROM word_to_video);
```

---

## Next Steps

1. **Test with small word list** (3-5 words) to validate pipeline
2. **Review LLM analysis quality** - check `analysis/` directory
3. **Run full TOEFL corpus** after validation
4. **Monitor costs** - OpenAI API usage dashboard
5. **Optimize**: Consider local LLM for production scale

---

## Support

For issues or questions:
- Check logs in `storage-dir/logs/`
- Review `failed_uploads.jsonl` for errors
- Test backend health: `curl http://localhost:5001/v3/health`
- File issue with full error message and logs
