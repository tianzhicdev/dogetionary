# LLM Logging Improvements

## Problem
Production JSONDecodeError in question generation couldn't be debugged because:
1. We didn't know which model in the fallback chain was actually used
2. We didn't see the actual LLM response content that failed to parse
3. We couldn't determine if the issue was with a specific model or a general problem

## Solution: Enhanced Diagnostic Logging

### Changes Made

#### 1. `src/utils/llm.py` - LLM Client Layer

**Line 151**: Enhanced fallback chain attempt logging
```python
# Before:
logger.debug(f"Attempting model {i+1}/{len(chain)}: {model_name}")

# After:
logger.info(f"Attempting model {i+1}/{len(chain)}: {model_name} for use_case={use_case}")
```

**Lines 165-171**: Track which model succeeded
```python
# Before:
if result:
    if i > 0:
        logger.info(f"Fallback successful: {model_name} (level {i})")
    return result

# After:
if result:
    if i > 0:
        logger.warning(f"Fallback to model {model_name} succeeded (fallback level {i}) for use_case={use_case}")
    else:
        logger.info(f"Primary model {model_name} succeeded for use_case={use_case}")
    return result
```

**Line 298**: Log response metadata
```python
# New:
logger.info(f"LLM response received: provider={provider}, model={model_name}, use_case={use_case}, content_length={len(content) if content else 0}, duration={duration:.2f}s")
```

#### 2. `src/services/question_generation_service.py` - Question Generation Layer

**Lines 504-512**: Capture actual LLM response before JSON parsing
```python
# Before:
question_data = json.loads(content)

# After:
# Log the actual LLM response before attempting to parse
logger.info(f"LLM returned content for question generation (length={len(content)}): {content[:500]}...")  # Log first 500 chars

try:
    question_data = json.loads(content)
except json.JSONDecodeError as json_err:
    # Log the full content when JSON parsing fails
    logger.error(f"JSON parsing failed. Full LLM response:\n{content}", exc_info=True)
    logger.error(f"JSON error details: {json_err.msg} at line {json_err.lineno} column {json_err.colno} (char {json_err.pos})")
    raise
```

## What We'll See in Production Logs

### Before Error (Normal Flow)
```json
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "Starting fallback chain for use_case=question, models=['google/gemini-2.0-flash-lite-001', 'deepseek/deepseek-chat-v3.1', 'qwen/qwen-2.5-7b-instruct', 'openai/gpt-4o-mini']"
}
```

```json
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "Attempting model 1/4: google/gemini-2.0-flash-lite-001 for use_case=question"
}
```

```json
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "LLM response received: provider=openrouter, model=google/gemini-2.0-flash-lite-001, use_case=question, content_length=456, duration=0.79s"
}
```

```json
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "Primary model google/gemini-2.0-flash-lite-001 succeeded for use_case=question"
}
```

```json
{
  "level": "INFO",
  "logger": "services.question_generation_service",
  "message": "LLM returned content for question generation (length=456): {\"question\":\"What does 'apple' mean?\",\"correct_answer\":\"A fruit\",..."
}
```

### When JSON Parsing Fails
```json
{
  "level": "ERROR",
  "logger": "services.question_generation_service",
  "message": "JSON parsing failed. Full LLM response:\n```json\n{\"question\": \"What does 'apple' mean?\",}\n```",
  "exc_info": "..."
}
```

```json
{
  "level": "ERROR",
  "logger": "services.question_generation_service",
  "message": "JSON error details: Expecting value at line 8 column 3 (char 332)"
}
```

### When Fallback Occurs
```json
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "Attempting model 1/4: google/gemini-2.0-flash-lite-001 for use_case=question"
}
```

```json
{
  "level": "WARNING",
  "logger": "utils.llm",
  "message": "Model google/gemini-2.0-flash-lite-001 failed with JSONDecodeError: Expecting value: line 8 column 3 (char 332), trying next in chain"
}
```

```json
{
  "level": "INFO",
  "logger": "utils.llm",
  "message": "Attempting model 2/4: deepseek/deepseek-chat-v3.1 for use_case=question"
}
```

```json
{
  "level": "WARNING",
  "logger": "utils.llm",
  "message": "Fallback to model deepseek/deepseek-chat-v3.1 succeeded (fallback level 1) for use_case=question"
}
```

## Benefits

1. **Identify Problematic Models**: We can now see exactly which model in the fallback chain is causing issues
2. **Debug JSON Errors**: We capture the full malformed response for analysis
3. **Track Fallback Patterns**: We can see when and how often we fall back to alternative models
4. **Monitor Performance**: Duration tracking helps identify slow models
5. **Root Cause Analysis**: With actual response content, we can determine if it's:
   - Markdown wrapping (```json ... ```)
   - Trailing commas
   - Incomplete JSON
   - Model-specific formatting issues

## Next Steps After Deployment

After deploying these changes, when the next JSONDecodeError occurs:

1. **Query Loki for the request ID** to get full log sequence
2. **Look for**: `"LLM returned content for question generation"` log entry
3. **Analyze** the actual malformed JSON response
4. **Determine** if it's a specific model issue or all models
5. **Implement** targeted fix based on actual failure pattern

## Grafana Query Examples

### Find all JSON parsing failures
```
{app="dogetionary", logger="services.question_generation_service"} |= "JSON parsing failed"
```

### Find which models are being used
```
{app="dogetionary", logger="utils.llm"} |= "Primary model" or "Fallback to model"
```

### Find all fallback events
```
{app="dogetionary", logger="utils.llm", level="WARNING"} |= "Fallback to model"
```

### Find malformed JSON responses
```
{app="dogetionary", logger="services.question_generation_service"} |= "Full LLM response"
```
