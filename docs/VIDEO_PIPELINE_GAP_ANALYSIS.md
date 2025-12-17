# Video Pipeline Gap Analysis

**Date**: December 15, 2025
**Current Script**: `scripts/find_videos.py` (1193 lines)
**Desired Command**:
```bash
python scripts/find_videos.py \
  --backend-url https://kwafy.com/api \
  --output-dir /Volumes/databank/shortfilms \
  --education-min-score 0.6 \
  --context-min-score 0.6 \
  --bundle toefl_beginner
```

---

## Current Pipeline Steps

### Stage 1: ClipCafe Metadata Search
**Method**: `search_clipcafe(word: str)`
**Idempotent**: ✅ Yes (caches to `metadata_dir/<word>/<slug>.json`)
**LLM**: ❌ No
**Input**: Word string
**Output**: List of ClipCafe metadata JSON objects

**Process**:
1. Check cache directory `metadata_dir/<word>/` for existing JSON files
2. If cached, load and return
3. Otherwise, query ClipCafe API:
   - Endpoint: `https://api.clip.cafe/`
   - Parameters: `transcript=<word>`, `movie_language=English`, `duration=1-15`, `sort=views`, `size=100`
4. Save each clip metadata to cache: `metadata_dir/<word>/<slug>.json`
5. Return list of metadata objects

**Idempotency**: Skips API call if cache files exist

---

### Stage 2: Candidate Selection (Metadata Transcript)
**Method**: `analyze_candidates(metadata, search_word, vocab_list)`
**Idempotent**: ✅ Yes (caches to `candidates_dir/<word>/<slug>_candidates.json`)
**LLM**: ✅ Yes (GPT-4o-mini via OpenAI API)
**Input**: ClipCafe metadata, search word, full vocabulary list
**Output**: Candidate analysis JSON with word mappings

**Process**:
1. Check cache: `candidates_dir/<word>/<slug>_candidates.json`
2. If cached, return immediately
3. Validate transcript (must be >10 words)
4. Find vocabulary words in ClipCafe transcript using regex
5. Build LLM prompt with:
   - Movie title, plot, duration
   - ClipCafe transcript
   - Candidate words found in transcript
6. Query LLM (GPT-4o-mini) for relevance scoring
7. Validate LLM response:
   - Word must actually appear in transcript (prevent hallucination)
   - Score must be ≥ `min_relevance_score` (default 0.6)
8. Sort by score, limit to top `max_mappings_per_video` (default 5)
9. Cache result
10. Return: `{"slug": "...", "mappings": [{"word": "...", "relevance_score": 0.85, "reason": "..."}]}`

**Idempotency**: Skips LLM call if cache exists

**Current LLM Prompt Criteria** (SINGLE SCORE):
```
A word should be scored highly if:
1. The word appears clearly in the transcript (spoken)
2. The context makes the meaning clear
3. The scene likely has visual cues that reinforce the word's meaning
4. The usage is natural and memorable

Returns:
- relevance_score: 0.0-1.0 (how well this video teaches the word)
```

---

### Stage 3A: Audio Transcript Extraction (Whisper)
**Method**: `extract_audio_transcript(video_path, slug)`
**Idempotent**: ✅ Yes (caches to `audio_transcripts_dir/<slug>_whisper.json`)
**LLM**: ❌ No (uses Whisper API, not GPT)
**Input**: Video file path, slug
**Output**: Whisper transcript JSON with word-level timestamps

**Process**:
1. Check cache: `audio_transcripts_dir/<slug>_whisper.json`
2. If cached, return immediately
3. Call Whisper API:
   - Endpoint: `https://api.openai.com/v1/audio/transcriptions`
   - Model: `whisper-1`
   - Format: `verbose_json` with word-level timestamps
4. Extract clean transcript data:
   - `text`: Full transcript
   - `words`: Word-level timestamps `[{"word": "...", "start": 1.5, "end": 2.0}, ...]`
   - `duration`: Audio duration
   - `segments`: Whisper segments
5. Cache result
6. Return audio transcript object

**Idempotency**: Skips Whisper API call if cache exists

---

### Stage 3B: Final Analysis (Audio Verification)
**Method**: `analyze_final(metadata, audio_transcript, search_word, vocab_list)`
**Idempotent**: ✅ Yes (caches to `final_analysis_dir/<word>/<slug>_final.json`)
**LLM**: ✅ Yes (GPT-4o-mini via OpenAI API)
**Input**: ClipCafe metadata, Whisper audio transcript, search word, vocab list
**Output**: Final analysis JSON with verified word mappings

**Process**:
1. Check cache: `final_analysis_dir/<word>/<slug>_final.json`
2. If cached, return immediately
3. Use clean Whisper transcript (not ClipCafe subtitle)
4. Validate transcript (must be >10 words)
5. Find vocabulary words in clean audio transcript
6. Build final LLM prompt with:
   - Movie title, plot, duration
   - Clean Whisper transcript
   - Candidate words found in audio
7. Query LLM (GPT-4o-mini) for verified scoring
8. Validate LLM response:
   - Word must appear in audio transcript
   - Score must be ≥ `min_relevance_score` (default 0.6)
9. Find word timestamps from Whisper word-level data
10. Sort by score, limit to top `max_mappings_per_video` (default 5)
11. Cache result
12. Return: `{"slug": "...", "mappings": [...], "audio_verified": True}`

**Idempotency**: Skips second LLM call if cache exists

**Current LLM Prompt Criteria** (SINGLE SCORE):
```
A word should be scored highly if:
1. The word appears clearly in the audio transcript (actually spoken)
2. The context makes the meaning clear
3. The scene likely has visual cues that reinforce the word's meaning
4. The usage is natural and memorable

Returns:
- relevance_score: 0.0-1.0 (how well this video teaches the word)

Note: "This is a VERIFIED audio transcript - be more confident in your assessments"
```

---

### Stage 4: Video Download
**Method**: `download_video(metadata)`
**Idempotent**: ✅ Yes (caches to `videos_dir/<slug>.mp4`)
**LLM**: ❌ No
**Input**: ClipCafe metadata
**Output**: Path to downloaded MP4 file

**Process**:
1. Check cache: `videos_dir/<slug>.mp4`
2. If exists, validate size (<5MB), return path
3. Otherwise, download from ClipCafe `download` URL
4. Stream download to `videos_dir/<slug>.mp4`
5. Validate size (<5MB limit)
6. If too large, delete and return None
7. Return video path

**Idempotency**: Skips download if video file exists

---

### Stage 5A: Save to Directory (Download-Only Mode)
**Method**: `save_video_to_directory(metadata, analysis, video_path, audio_transcript)`
**Idempotent**: ✅ Yes (tracks in `state_dir/saved_videos.txt`)
**LLM**: ❌ No
**Input**: Metadata, final analysis, video path, audio transcript
**Output**: Directory with MP3 + metadata.json

**Process**:
1. Check if slug in `saved_videos` set (loaded from `state_dir/saved_videos.txt`)
2. If already saved, skip
3. Create directory: `output_dir/<slug>/`
4. Extract MP3 audio using ffmpeg:
   - Command: `ffmpeg -i video.mp4 -vn -acodec libmp3lame -q:a 2 -y audio.mp3`
   - Output: `output_dir/<slug>/<slug>.mp3`
5. Create `metadata.json` with:
   - `slug`, `name`, `format`: "mp3"
   - `source_id`: "clipcafe"
   - `transcript`: ClipCafe subtitle transcript
   - `audio_transcript`: Whisper clean transcript
   - `audio_transcript_verified`: True
   - `whisper_metadata`: Full Whisper response
   - `clipcafe_metadata`: Movie title, year, plot, IMDB ID, etc.
   - `word_mappings`: Array of word mappings with scores and timestamps
6. Write `metadata.json` to `output_dir/<slug>/metadata.json`
7. Mark as saved: append slug to `state_dir/saved_videos.txt`
8. Return result dictionary

**Idempotency**: Skips if slug already in saved_videos.txt

**Output Structure**:
```
output_dir/
  <slug>/
    <slug>.mp3           # Extracted audio
    metadata.json        # Full metadata + word mappings
```

---

### Stage 5B: Upload to Backend (Upload Mode)
**Method**: `upload_to_backend(metadata, analysis, video_path, audio_transcript)`
**Idempotent**: ✅ Yes (tracks in `state_dir/uploaded_videos.txt`)
**LLM**: ❌ No
**Input**: Metadata, final analysis, video path, audio transcript
**Output**: Upload result from backend API

**Process**:
1. Check if slug in `uploaded_videos` set (loaded from `state_dir/uploaded_videos.txt`)
2. If already uploaded, skip
3. Read video file, encode as base64
4. Prepare payload for batch upload endpoint:
   - `source_id`: "clipcafe"
   - `videos`: Array with single video object containing:
     - Video data (base64), metadata, transcripts
     - `word_mappings`: Array of mappings with scores and timestamps
5. POST to `/v3/admin/videos/batch-upload`
6. Parse response, extract `video_id` and `mappings_created`
7. Mark as uploaded: append slug to `state_dir/uploaded_videos.txt`
8. Return upload result

**Idempotency**: Skips if slug already in uploaded_videos.txt

---

## State Tracking (Idempotency)

The pipeline maintains state files in `state_dir/`:

1. **`processed_words.txt`**: Words that have been processed (Stage 1 completed)
   - One word per line
   - Loaded at startup, prevents re-processing entire word

2. **`uploaded_videos.txt`**: Video slugs that have been uploaded to backend
   - One slug per line
   - Prevents duplicate uploads

3. **`saved_videos.txt`**: Video slugs that have been saved to output directory
   - One slug per line
   - Prevents duplicate saves in download-only mode

4. **`failed_uploads.jsonl`**: Failed upload attempts
   - JSONL format: `{"slug": "...", "error": "...", "timestamp": "..."}`
   - Used for debugging and retry logic

**Resume Capability**:
- If pipeline crashes or is stopped, it can resume from where it left off
- All cache directories and state files are preserved
- Next run will skip already-processed words and already-uploaded videos

---

## LLM Usage Summary

| Stage | LLM Used | Model | Purpose | Caching |
|-------|----------|-------|---------|---------|
| Stage 1 | ❌ No | N/A | ClipCafe API search | ✅ Cached |
| Stage 2 | ✅ Yes | GPT-4o-mini | Candidate selection (metadata transcript) | ✅ Cached |
| Stage 3A | ❌ No | Whisper-1 | Audio transcription (not GPT) | ✅ Cached |
| Stage 3B | ✅ Yes | GPT-4o-mini | Final verification (audio transcript) | ✅ Cached |
| Stage 4 | ❌ No | N/A | Video download | ✅ Cached |
| Stage 5 | ❌ No | N/A | Save/Upload | ✅ Tracked |

**LLM Calls Per Word**:
- Best case: 0 LLM calls (all cached)
- Worst case (new word, 100 videos found, 20 candidates pass):
  - Stage 2: 100 LLM calls (one per video for candidate selection)
  - Stage 3B: 20 LLM calls (one per candidate video for final verification)
  - **Total: ~120 LLM calls**

**Cost Estimate** (GPT-4o-mini at $0.15/1M input, $0.60/1M output):
- Average prompt: ~500 tokens input, ~200 tokens output
- Cost per LLM call: ~$0.0001
- Cost per word (100 videos, 20 candidates): ~$0.012
- Cost for 1000 words: ~$12

---

## Current vs Desired State

### Current Command Format
```bash
python scripts/find_videos.py \
  --csv word_list.csv \
  --storage-dir /Volumes/databank/dogetionary-pipeline \
  --backend-url http://localhost:5001 \
  --max-videos 100 \
  --min-score 0.6 \
  --download-only \
  --output-dir /path/to/output
```

### Desired Command Format
```bash
python scripts/find_videos.py \
  --backend-url https://kwafy.com/api \
  --output-dir /Volumes/databank/shortfilms \
  --education-min-score 0.6 \
  --context-min-score 0.6 \
  --bundle toefl_beginner
```

---

## Gap Analysis

### ✅ Already Implemented (No Changes Needed)

1. **Download-only mode**: Script already supports `--download-only` flag
2. **MP3 extraction**: Already extracts audio as MP3 using ffmpeg
3. **Audio transcript generation**: Already uses Whisper API for clean transcripts
4. **Metadata.json format**: Already generates comprehensive metadata with word mappings
5. **Idempotency**: Already implements full state tracking and resume capability
6. **Video size limit**: Already enforces 5MB limit
7. **Caching system**: Already caches all intermediate results
8. **Word-level timestamps**: Already extracts from Whisper API
9. **Movie metadata**: Already includes title, year, plot, IMDB ID

### ❌ Missing Features (Need Implementation)

#### 1. Bundle Vocabulary Query Endpoint
**Current**: Reads words from CSV file (`--csv word_list.csv`)
**Desired**: Query backend API for words from bundle that need videos

**Backend Changes Needed**:
- **Endpoint**: `GET /v3/admin/bundles/{bundle_name}/words-needing-videos`
- **Query**:
  ```sql
  SELECT DISTINCT bv.word
  FROM bundle_vocabularies bv
  WHERE bv.bundle_name = ?
    AND NOT EXISTS (
      SELECT 1 FROM word_to_video wtv
      WHERE wtv.word = bv.word
        AND wtv.learning_language = bv.learning_language
    )
  ORDER BY bv.word
  ```
- **Response**: `{"words": ["abandon", "ability", ...]}`

**Script Changes Needed**:
- Replace `--csv` parameter with `--bundle`
- Add method `fetch_bundle_words(bundle_name: str) -> List[str]`
- Query backend endpoint instead of reading CSV

**Effort**: 2-3 hours (1 hour backend, 1 hour script, 1 hour testing)

---

#### 2. Dual-Criteria Scoring (Education + Context)
**Current**: Single `relevance_score` (0.0-1.0) evaluating overall teaching quality
**Desired**: Two separate scores:
- **Education Score**: Does video illustrate word meaning well?
- **Context Score**: Is video independent with sufficient context?

**LLM Prompt Changes Needed**:

**Stage 2 Prompt** (`_build_llm_prompt`):
```python
# CURRENT
"""
A word should be scored highly if:
1. The word appears clearly in the transcript (spoken)
2. The context makes the meaning clear
3. The scene likely has visual cues that reinforce the word's meaning
4. The usage is natural and memorable

Returns:
- relevance_score: 0.0-1.0 (how well this video teaches the word)
"""

# DESIRED
"""
Evaluate each word on TWO separate criteria:

1. EDUCATION SCORE (0.0-1.0): How well does this video illustrate the word's meaning?
   - Does the word appear clearly in the transcript?
   - Are there visual cues that reinforce the meaning?
   - Is the usage natural and memorable?

2. CONTEXT SCORE (0.0-1.0): Can this video stand alone?
   - Does the scene have sufficient context to be understood independently?
   - Would a learner understand what's happening without watching the full movie?
   - Is the emotional/narrative context clear?

Returns:
{
  "mappings": [
    {
      "word": "example",
      "education_score": 0.85,
      "context_score": 0.70,
      "reason": "Word used clearly with visual reinforcement. Scene needs some movie context."
    }
  ]
}
"""
```

**Stage 3B Prompt** (`_build_final_llm_prompt`):
- Same changes as Stage 2, but emphasize verified audio transcript

**Validation Logic Changes**:
- Current: `if score < self.min_relevance_score`
- Desired: `if education_score < self.education_min_score or context_score < self.context_min_score`

**Metadata Changes**:
- Word mappings now include:
  ```json
  {
    "word": "abandon",
    "education_score": 0.85,
    "context_score": 0.70,
    "reason": "..."
  }
  ```

**Effort**: 4-6 hours
- 2 hours: Update LLM prompts and response parsing
- 2 hours: Update validation logic and filtering
- 1 hour: Update metadata structures
- 1 hour: Testing and validation

---

#### 3. Command-Line Parameter Changes
**Current Parameters**:
- `--csv` (required): CSV file path
- `--min-score` (default 0.6): Single threshold
- `--storage-dir` (default): Storage directory
- `--download-only` (flag): Enable download mode
- `--output-dir` (optional): Output directory for download mode

**Desired Parameters**:
- `--bundle` (required): Bundle name (e.g., "toefl_beginner")
- `--education-min-score` (default 0.6): Education threshold
- `--context-min-score` (default 0.6): Context threshold
- `--output-dir` (required): Output directory
- `--backend-url` (required): Backend API URL

**Removed/Changed**:
- Remove `--csv` (replaced by `--bundle`)
- Remove `--min-score` (replaced by dual scores)
- Remove `--download-only` (now default behavior)
- Remove `--storage-dir` (derive from output-dir)

**New Defaults**:
- Storage dir: `<output-dir>/.cache`
- Download-only mode: Always enabled (no upload support in new version)

**Effort**: 1-2 hours
- 1 hour: Update argument parser
- 30 min: Update script initialization
- 30 min: Testing

---

#### 4. Database Table Rename
**Current**: Script queries from hypothetical table (not in schema yet)
**Desired**: Query from `bundle_vocabularies` table

**Database Changes**:
- Rename `test_vocabularies` → `bundle_vocabularies` (if it exists)
- Or create new `bundle_vocabularies` table if doesn't exist

**Schema**:
```sql
CREATE TABLE bundle_vocabularies (
  id SERIAL PRIMARY KEY,
  bundle_name VARCHAR(100) NOT NULL,
  word VARCHAR(100) NOT NULL,
  learning_language VARCHAR(10) NOT NULL DEFAULT 'en',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(bundle_name, word, learning_language)
);

CREATE INDEX idx_bundle_vocabularies_bundle ON bundle_vocabularies(bundle_name);
CREATE INDEX idx_bundle_vocabularies_word ON bundle_vocabularies(word, learning_language);
```

**Effort**: 1 hour (migration script + testing)

---

## Total Implementation Effort

| Task | Effort | Priority |
|------|--------|----------|
| 1. Bundle vocabulary endpoint (backend + script) | 2-3 hours | High |
| 2. Dual-criteria scoring (prompts + validation) | 4-6 hours | High |
| 3. Command-line parameter changes | 1-2 hours | Medium |
| 4. Database table rename/creation | 1 hour | High |
| **Testing & Integration** | 2-3 hours | High |
| **Documentation** | 1 hour | Medium |

**Total Estimated Effort**: 11-16 hours

---

## Implementation Plan

### Phase 1: Backend Setup (2-4 hours)
1. Create or rename `bundle_vocabularies` table (30 min)
2. Add bundle query endpoint `/v3/admin/bundles/{bundle}/words-needing-videos` (1 hour)
3. Test endpoint with sample data (30 min)
4. Integration test (1 hour)

### Phase 2: Script Modifications (6-9 hours)
1. Update LLM prompts for dual-criteria scoring (2 hours)
2. Update response parsing and validation logic (2 hours)
3. Update metadata structures for dual scores (1 hour)
4. Update command-line parameters (1 hour)
5. Add `fetch_bundle_words()` method (30 min)
6. Update initialization logic (30 min)
7. Testing with sample data (2 hours)

### Phase 3: Integration & Testing (3-4 hours)
1. End-to-end test with real bundle (1 hour)
2. Verify dual-score filtering works correctly (1 hour)
3. Verify idempotency and resume capability (1 hour)
4. Test error handling and edge cases (1 hour)

### Phase 4: Documentation (1 hour)
1. Update script help text (15 min)
2. Create usage examples (15 min)
3. Update pipeline documentation (30 min)

---

## Risk Assessment

### Low Risk
- ✅ Bundle endpoint implementation (straightforward SQL query)
- ✅ Command-line parameter changes (simple refactoring)

### Medium Risk
- ⚠️ LLM prompt changes (need to validate LLM understands dual criteria)
- ⚠️ Response parsing (LLM may return unexpected formats)

### Mitigation Strategies
1. **LLM Prompt Testing**: Test prompts with sample videos before full deployment
2. **Response Validation**: Add strict JSON schema validation for LLM responses
3. **Fallback Logic**: If LLM returns single score instead of dual, use it for both criteria
4. **Gradual Rollout**: Test with small bundle (10-20 words) before processing large bundles

---

## Backward Compatibility

**Breaking Changes**:
- Command-line interface completely changed (not compatible with old scripts)
- Output format includes dual scores (metadata.json structure changed)

**Migration Path**:
1. Keep old script as `scripts/find_videos_v1.py`
2. New script is `scripts/find_videos.py`
3. Update documentation to reflect new usage

---

## Success Criteria

1. ✅ Can query backend for words from bundle that need videos
2. ✅ LLM returns dual scores (education + context) for each word
3. ✅ Filtering works with independent thresholds for each score
4. ✅ Metadata.json includes both scores for each word mapping
5. ✅ Idempotency preserved (can resume after crash)
6. ✅ Command matches desired format exactly

---

**Status**: 📝 Planning Complete - Ready for Implementation
**Next Step**: Begin Phase 1 (Backend Setup)
