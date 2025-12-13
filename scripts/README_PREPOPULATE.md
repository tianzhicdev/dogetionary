# Local Question Pre-population

This script runs question pre-population **directly inside Docker**, bypassing HTTP/Cloudflare entirely.

## Why Local?

**Before** (HTTP approach):
- ❌ Cloudflare 100-second timeout
- ❌ HTTP overhead
- ❌ Needs Cloudflare configuration
- ❌ Network dependency

**After** (Local approach):
- ✅ No timeouts - runs as long as needed
- ✅ Direct Python function calls
- ✅ No Cloudflare configuration needed
- ✅ Reuses 100% of Flask code

## Quick Start

### Simple Usage

```bash
# Process 10 words
./scripts/run_prepopulate.sh --source tianz_test --num-words 10

# Continuous mode - process until all complete
./scripts/run_prepopulate.sh --source tianz_test --num-words 10 --continuous
```

### Options

```bash
./scripts/run_prepopulate.sh [OPTIONS]

Options:
  --source SOURCE              Vocabulary source (tianz_test, toefl, ielts, etc.)
  --num-words N               Number of words per batch (default: 10)
  --learning-lang LANG        Learning language (default: en)
  --native-lang LANG          Native language (default: zh)
  --strategy STRATEGY         Selection strategy (default: missing_any)
                              Choices: missing_any, missing_definition, missing_questions, missing_video_questions
  --continuous                Keep running until all words complete

Examples:
  # Process 50 words at a time in continuous mode
  ./scripts/run_prepopulate.sh --source tianz_test --num-words 50 --continuous

  # Only process words missing definitions
  ./scripts/run_prepopulate.sh --source tianz_test --strategy missing_definition --num-words 10

  # Process TOEFL vocabulary
  ./scripts/run_prepopulate.sh --source toefl --num-words 20
```

## Performance

### Expected Timing
- **1 word**: ~100-150 seconds
  - Definition generation: ~10s
  - 5 question types: ~20s each
- **10 words**: ~15-20 minutes
- **100 words**: ~2.5-3 hours

### Output Example

```
================================================================================
🧠 LOCAL QUESTION PRE-POPULATION
================================================================================
Source: tianz_test
Batch Size: 1 words
Learning Language: en
Native Language: zh
Strategy: missing_any
Continuous Mode: False
================================================================================

================================================================================
📦 BATCH 1
================================================================================

✅ Batch Complete
────────────────────────────────────────────────────────────────────────────────
Words Processed: 1
Definitions Created: 1
Definitions Cached: 0
Questions Generated: 5
Questions Cached: 0
Errors: 0
Duration: 133.41s
Avg per word: 133.41s

📊 Overall Progress
────────────────────────────────────────────────────────────────────────────────
Total Words: 615
Completed: 78 (12.7%)
Remaining: 537

Question Types Generated:
  - mc_definition: 1
  - mc_word: 1
  - fill_blank: 1
  - pronounce_sentence: 1
  - video_mc: 1
```

## How It Works

1. **Wrapper script** (`run_prepopulate.sh`):
   - Loads API keys from `src/.env.secrets`
   - Copies Python script to Docker container
   - Runs script with environment variables

2. **Python script** (`prepopulate_local.py`):
   - Imports existing Flask functions directly
   - Reuses all logic from `handlers/admin_questions_smart.py`
   - Connects to database inside Docker network
   - Generates definitions and questions

3. **No HTTP layer**:
   - Direct Python function calls
   - No Cloudflare timeouts
   - No network overhead

## For Production Server

Same commands work on production - just SSH in first:

```bash
# SSH to production
ssh your-server

# Navigate to project
cd /path/to/dogetionary

# Run the script
./scripts/run_prepopulate.sh --source tianz_test --num-words 50 --continuous
```

## Troubleshooting

### Missing API Keys

```
Error: src/.env.secrets not found!
```

**Solution**: Ensure `src/.env.secrets` contains:
```bash
GROQ_API_KEY=your_groq_key
OPENAI_API_KEY="your_openai_key"
```

### Container Not Running

```
Error: No such container: dogetionary-app-1
```

**Solution**: Start Docker services:
```bash
docker-compose up -d
```

### Script Errors

View detailed logs in the output - the script shows all LLM calls and errors.

## Monitoring Progress

The script shows:
- Words processed
- Definitions created/cached
- Questions generated/cached
- Errors
- Overall progress percentage
- Remaining words

## Stopping the Script

Press `Ctrl+C` to stop gracefully at any time.

## Comparison with HTTP Approach

| Feature | HTTP (`prepopulate_smart.py`) | Local (`run_prepopulate.sh`) |
|---------|------------------------------|------------------------------|
| Timeout | Cloudflare 100s limit ❌ | No limit ✅ |
| Speed | HTTP overhead | Faster (direct calls) |
| Setup | Need Cloudflare bypass rule | No setup needed |
| Error handling | HTTP errors | Python exceptions |
| Logs | Flask logs | Direct output |
| Production | Need special config | Works out of box |

## Files

- `scripts/prepopulate_local.py` - Main Python script
- `scripts/run_prepopulate.sh` - Convenience wrapper
- `scripts/prepopulate_smart.py` - Old HTTP-based script (deprecated)

## Summary

Use `run_prepopulate.sh` for all question pre-population. It's simpler, faster, and has no timeout issues.
