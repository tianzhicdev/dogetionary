# Video Production Automation Script

Automates video discovery and production for vocabulary words from `vocabulary_merged.csv`.

## Overview

This script:
1. Reads all words from `/resources/words/vocabulary_merged.csv` (4,042 words)
2. Checks each word to see if it has any associated videos
3. Triggers video production workflow for words without videos
4. Tracks progress and generates detailed reports

## Features

- **Smart checking**: Only triggers production for words without videos
- **Exponential backoff**: Handles 429 rate limit errors automatically
- **Resume capability**: Can resume from last checkpoint if interrupted
- **Progress tracking**: Saves checkpoints every 10 words
- **Dry run mode**: Test without actually triggering production
- **Detailed reporting**: JSON and CSV reports of all actions

## Usage

### Basic Usage

```bash
cd /Users/biubiu/projects/dogetionary/scripts

# Dry run first to see what would happen
python3 trigger_video_production.py --dry-run --limit 10

# Process first 10 words for real
python3 trigger_video_production.py --limit 10

# Process all 4,042 words (this will take a long time!)
python3 trigger_video_production.py
```

### Common Options

```bash
# Dry run to preview actions
python3 trigger_video_production.py --dry-run

# Process first 50 words
python3 trigger_video_production.py --limit 50

# Resume from last checkpoint (after interruption)
python3 trigger_video_production.py --resume

# Custom delay between requests (default: 2 seconds)
python3 trigger_video_production.py --delay 5

# Use --interval for production (recommended: 5-10 seconds)
python3 trigger_video_production.py --interval 10

# Use different API URL
python3 trigger_video_production.py --api-url http://production-url:5001
```

### All Options

```
--api-url URL           API base URL (default: http://localhost:5001)
--words-file PATH       Path to vocabulary CSV file
--language LANG         Learning language code (default: en)
--delay SECONDS         Delay between API calls (default: 2)
--interval SECONDS      Alias for --delay, overrides --delay if provided
--limit N               Process only first N words
--resume                Resume from last checkpoint
--dry-run               Simulate without triggering production
--checkpoint-interval N Save progress every N words (default: 10)
--max-retries N         Max retries for failed calls (default: 3)
```

## How It Works

### Workflow

For each word in vocabulary_merged.csv:

1. **Check**: Call `GET /v3/api/check-word-videos?word={word}&lang=en`
   - If `has_videos == true`: Skip word (already has videos)
   - If `has_videos == false`: Continue to step 2

2. **Trigger**: Call `POST /v3/api/trigger-video-search`
   ```json
   {
     "word": "example",
     "learning_language": "en"
   }
   ```
   - This starts background video discovery pipeline
   - Video finder will search ClipCafe, download, and verify videos

3. **Wait**: Delay only after triggering production (configurable with `--delay` or `--interval`)
   - Default: 2 seconds
   - Production: 10 seconds recommended
   - **Note**: No delay for skipped words (already have videos)

4. **Checkpoint**: Every 10 words, save progress to `video_production_progress.json`

### Error Handling

- **429 Rate Limit**: Automatically retries with exponential backoff
- **Network errors**: Retries up to 3 times with increasing delays
- **Interruption**: Saves progress, resume with `--resume`
- **Failed words**: Logged and included in report for manual review

## Output Files

### video_production_progress.json
Checkpoint file for resuming interrupted runs:
```json
{
  "last_index": 49,
  "timestamp": "2025-12-25T21:57:22.793447",
  "stats": {...},
  "triggered_words": ["abandon", "abbreviate", ...],
  "words_with_videos": ["ability", ...]
}
```

### video_production_report.json
Final summary report:
```json
{
  "summary": {
    "total_words": 4042,
    "processed": 50,
    "has_videos": 10,
    "triggered": 40,
    "failed": 0
  },
  "triggered_words": [...],
  "words_with_videos": [...],
  "failed_words": [...]
}
```

### video_production_report.csv
CSV format for analysis:
```csv
word,action,status
ability,skipped,has_videos
abandon,triggered,success
...
```

## Examples

### Test with first 5 words (dry run)
```bash
python3 trigger_video_production.py --dry-run --limit 5
```
Output:
```
[2025-12-25 21:57:14] INFO: Processing 5 words (index 0 to 4)
[2025-12-25 21:57:14] INFO: [1/5] Checking word: 'abandon'
[2025-12-25 21:57:14] INFO:   → Word 'abandon' has no videos (triggering production)
[2025-12-25 21:57:14] INFO: [DRY RUN] Would trigger video search for: abandon
...
Total words processed: 5
Words with existing videos (skipped): 1
Words triggered for production: 4
```

### Process first batch of 100 words
```bash
python3 trigger_video_production.py --limit 100
```
- Takes ~3-4 minutes (2 seconds per word)
- Saves checkpoints every 10 words
- Can be interrupted with Ctrl+C

### Resume after interruption
```bash
# First run (interrupted after 50 words)
python3 trigger_video_production.py --limit 100
^C  # User presses Ctrl+C

# Resume where it left off
python3 trigger_video_production.py --resume --limit 100
```

### Process all 4,042 words
```bash
# This will take approximately 2.2 hours
# (4042 words × 2 seconds per word = 8084 seconds = 2.2 hours)
python3 trigger_video_production.py

# Can safely interrupt and resume
python3 trigger_video_production.py --resume
```

## Monitoring Progress

### Real-time logs
The script outputs detailed progress:
```
[2025-12-25 21:57:14] INFO: [1/4042] Checking word: 'abandon'
[2025-12-25 21:57:14] INFO:   → Word 'abandon' has no videos (triggering production)
[2025-12-25 21:57:14] INFO: ✓ Triggered video search for: abandon
[2025-12-25 21:57:16] INFO: [2/4042] Checking word: 'abbreviate'
...
[2025-12-25 21:57:30] INFO:   Checkpoint: 10 words processed, 8 triggered, 2 skipped
```

### Check backend logs
Video production runs in background. Monitor with:
```bash
docker-compose logs app --tail=50 -f | grep "Processing word"
```

### Check progress file
```bash
cat video_production_progress.json | python3 -m json.tool
```

## Safety Features

1. **Confirmation prompt**: Asks before starting (skipped in dry-run)
   ```
   Ready to process 4042 words. Continue? (y/n):
   ```

2. **Dry run mode**: Test without making changes
   ```bash
   python3 trigger_video_production.py --dry-run
   ```

3. **Checkpoints**: Progress saved every 10 words
   - Safe to interrupt with Ctrl+C
   - Resume with `--resume` flag

4. **Rate limiting**: Configurable delay between requests
   - Default: 2 seconds
   - Prevents overwhelming API/ClipCafe

## Troubleshooting

### Script fails to connect to API
```
Error: Failed to check word 'abandon' after 3 attempts: Connection refused
```
**Solution**: Ensure backend is running:
```bash
docker-compose ps app
docker-compose up -d app
```

### Rate limiting (429 errors)
```
Rate limited (429) for word 'example'. Waiting 4s...
```
**Solution**: Script handles this automatically with exponential backoff. If persistent, increase delay:
```bash
python3 trigger_video_production.py --delay 5
```

### Progress file corrupted
```
Failed to load progress file: JSON decode error
```
**Solution**: Delete progress file and start fresh:
```bash
rm video_production_progress.json
python3 trigger_video_production.py
```

## Performance Estimates

With default settings (2 second delay):

- **10 words**: ~20 seconds
- **100 words**: ~3-4 minutes
- **500 words**: ~17 minutes
- **1000 words**: ~34 minutes
- **4042 words** (all): ~2.2 hours

Actual time may vary based on:
- API response times
- Network latency
- Number of words already having videos (skipped faster)
- Rate limiting delays

## Production Recommendations

### For Production Servers

When running on production servers, use these settings to avoid overloading:

```bash
# Recommended production settings
python3 trigger_video_production.py \
  --api-url https://your-production-url.com/api \
  --interval 10 \
  --limit 100 \
  --resume

# Why these settings:
# --interval 10: 10 seconds between requests prevents server overload
# --limit 100: Process in small batches for better control
# --resume: Continue from where you left off if interrupted
```

**Key Differences from Local Development:**
- **Local development**: `--delay 2` (2 seconds) is fine
- **Production**: `--interval 10` (10 seconds) recommended to:
  - Prevent server resource exhaustion
  - Allow video processing pipeline to complete
  - Avoid overwhelming ClipCafe API
  - Reduce risk of container crashes

### Batch Processing Strategy

Process the full vocabulary in manageable chunks:

```bash
# First batch (words 0-99)
python3 trigger_video_production.py --interval 10 --limit 100

# Second batch (words 100-199)
python3 trigger_video_production.py --interval 10 --resume --limit 200

# Continue until all 4,042 words processed
```

## Tips

1. **Start with a dry run** to see what would happen:
   ```bash
   python3 trigger_video_production.py --dry-run --limit 10
   ```

2. **Process in batches** for better control:
   ```bash
   python3 trigger_video_production.py --limit 100  # First 100
   python3 trigger_video_production.py --resume --limit 200  # Next 100
   ```

3. **Monitor backend** to see video processing:
   ```bash
   docker-compose logs app -f | grep "Stage"
   ```

4. **Check reports** to see results:
   ```bash
   cat video_production_report.json | python3 -m json.tool
   open video_production_report.csv  # In Excel/Numbers
   ```

## Integration with Video Pipeline

This script triggers the video discovery pipeline, which:

1. **Stage 1**: Searches ClipCafe for video clips
2. **Stage 2**: Scores videos using metadata transcript (before download)
3. **Stage 3**: Downloads videos, transcribes with Whisper, extracts word mappings

Each triggered word may result in:
- 0-20 videos downloaded (depending on ClipCafe results and quality scores)
- Multiple word mappings per video (not just the search word)
- Videos uploaded to database with verified audio transcripts

Monitor the full pipeline in backend logs:
```bash
docker-compose logs app -f
```
