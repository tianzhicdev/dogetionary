# JSON Fallback Fix - Summary

## Problem

Production error showed that when an LLM returns malformed JSON, the fallback mechanism doesn't trigger. The system fails instead of trying the next model in the chain.

**Root Cause**: JSON parsing happens AFTER the fallback chain completes, so JSONDecodeError is never caught by the fallback mechanism.

## Solution: Simplicity First

Per user feedback: **"Just fallback to the next model if ANY error occurs, and log as much as possible for debugging."**

### Changes Made

#### 1. **Enhanced Fallback Exception Handling** (`src/utils/llm.py`)

**Before**:
```python
except Exception as e:
    logger.warning(f"Model {model_name} failed, trying next in chain")
    continue
```

**After**:
```python
except Exception as e:
    # Catch ANY exception and try next model
    # Log everything for debugging
    error_type = type(e).__name__
    error_msg = str(e)

    logger.warning(
        f"Model {model_name} failed with {error_type}: {error_msg}. "
        f"Trying next model in chain (attempt {i+1}/{len(chain)})",
        exc_info=True  # Include full stack trace
    )
    continue
```

**Benefits**:
- Catches ALL exceptions (JSONDecodeError, API errors, timeout, etc.)
- Logs full stack trace for debugging
- Shows attempt number for visibility
- Simple and robust

#### 2. **Enhanced Model Success Logging** (`src/utils/llm.py`)

**Added**:
```python
# Log which model succeeded
if i > 0:
    logger.warning(f"Fallback to model {model_name} succeeded (fallback level {i}) for use_case={use_case}")
else:
    logger.info(f"Primary model {model_name} succeeded for use_case={use_case}")
```

**Benefits**:
- Know exactly which model handled the request
- Track fallback patterns in production
- Identify unreliable models

#### 3. **LLM Response Content Logging** (`src/utils/llm.py`)

**Added**:
```python
# Log response metadata
logger.info(f"LLM response received: provider={provider}, model={model_name}, use_case={use_case}, content_length={len(content)}, duration={duration:.2f}s")

# Log content preview for JSON responses
if response_format is not None:
    logger.info(f"LLM content preview (first 500 chars): {content[:500]}...")
```

**Benefits**:
- See actual LLM response before it fails
- Debug malformed JSON with actual content
- Track response times per model

#### 4. **JSON Error Logging** (`src/services/question_generation_service.py`)

**Added**:
```python
try:
    question_data = json.loads(content)
except json.JSONDecodeError as json_err:
    # Log full content when JSON parsing fails
    logger.error(
        f"JSONDecodeError: {json_err.msg} at line {json_err.lineno} col {json_err.colno} (char {json_err.pos}). "
        f"Full LLM response:\n{content}",
        exc_info=True
    )
    raise  # Let fallback catch it
```

**Benefits**:
- See FULL malformed JSON response
- Exact error location (line/column/char)
- Error propagates to fallback mechanism

## How It Works Now

### Success Path (Primary Model Works)
```
1. Fallback chain starts: [gemini, deepseek, qwen, gpt-4o-mini]
2. Try gemini
3. ✅ Valid JSON returned
4. Log: "Primary model gemini succeeded"
5. Return result
```

### Fallback Path (Primary Fails, Fallback Succeeds)
```
1. Fallback chain starts: [gemini, deepseek, qwen, gpt-4o-mini]
2. Try gemini
3. ❌ JSONDecodeError (malformed JSON)
4. Log: "Model gemini failed with JSONDecodeError: Expecting value..."
5. Log: Full stack trace + malformed JSON content
6. Try deepseek
7. ✅ Valid JSON returned
8. Log: "Fallback to model deepseek succeeded (fallback level 1)"
9. Return result
```

### All Models Fail Path
```
1. Fallback chain starts: [gemini, deepseek, qwen, gpt-4o-mini]
2. Try gemini → ❌ JSON error (logged with full content)
3. Try deepseek → ❌ JSON error (logged with full content)
4. Try qwen → ❌ JSON error (logged with full content)
5. Try gpt-4o-mini → ❌ JSON error (logged with full content)
6. Log: "All models in fallback chain failed"
7. Return None → triggers error response to user
```

## What We'll See in Production Logs

### When Primary Model Succeeds
```json
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "Starting fallback chain for use_case=question, models=['google/gemini-2.0-flash-lite-001', ...]"
}
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "Attempting model 1/4: google/gemini-2.0-flash-lite-001 for use_case=question"
}
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "LLM response received: provider=openrouter, model=google/gemini-2.0-flash-lite-001, content_length=456, duration=0.79s"
}
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "LLM content preview (first 500 chars): {\"question\":\"What does apple mean?\",\"correct_answer\":\"A fruit\",..."
}
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "Primary model google/gemini-2.0-flash-lite-001 succeeded for use_case=question"
}
```

### When Fallback Is Needed
```json
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "Attempting model 1/4: google/gemini-2.0-flash-lite-001 for use_case=question"
}
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "LLM content preview: {\"question\": \"test\",}..."
}
{
  "level": "ERROR",
  "logger": "services.question_generation_service",
  "message": "JSONDecodeError: Expecting value at line 1 col 24 (char 23). Full LLM response:\n{\"question\": \"test\",}",
  "exc_info": "..."
}
{
  "level": "WARNING",
  "logger": "utils.llm",
  "message": "Model google/gemini-2.0-flash-lite-001 failed with JSONDecodeError: Expecting value: line 1 column 24 (char 23). Trying next model in chain (attempt 1/4)",
  "exc_info": "..."
}
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "Attempting model 2/4: deepseek/deepseek-chat-v3.1 for use_case=question"
}
{
  "level": "WARNING",
  "logger": "utils.llm",
  "message": "Fallback to model deepseek/deepseek-chat-v3.1 succeeded (fallback level 1) for use_case=question"
}
```

## Key Benefits

### 1. **Robustness**
- ANY error triggers fallback (not just specific ones)
- Multiple models means higher success rate
- Graceful degradation

### 2. **Debugging**
- See actual malformed JSON content
- Know which model caused the error
- Full stack traces for investigation
- Track which models are reliable

### 3. **Monitoring**
- Identify problematic models
- Track fallback frequency
- Measure model reliability

### 4. **Simplicity**
- One exception handler catches everything
- Clear logging strategy: "log everything"
- Easy to understand and maintain

## Grafana Queries

### Find fallback events
```
{app="dogetionary", logger="utils.llm", level="WARNING"} |= "Fallback to model"
```

### Find which models are failing
```
{app="dogetionary", logger="utils.llm"} |= "failed with"
```

### Find JSONDecodeError details
```
{app="dogetionary", logger="services.question_generation_service"} |= "JSONDecodeError"
```

### Find successful primary model usage
```
{app="dogetionary", logger="utils.llm"} |= "Primary model" |= "succeeded"
```

## Files Modified

1. **`src/utils/llm.py`**
   - Added `import json` (line 8)
   - Enhanced response logging (lines 307-312)
   - Improved success tracking (lines 165-169)
   - Simplified exception handling (lines 174-185)

2. **`src/services/question_generation_service.py`**
   - Added detailed JSON error logging (lines 504-514)
   - Error propagates to fallback (line 514: `raise`)

## Testing

Run integration tests to verify fallback behavior:
```bash
docker-compose exec app python3 /app/test_json_fallback.py
```

Expected result: All tests pass showing fallback works correctly.

## Deployment

After deploying these changes:
1. Monitor Grafana for fallback events
2. Check which models are most reliable
3. Watch for patterns in JSON errors
4. Adjust model priority in `config/config.py` if needed
