# Logging Configuration for Loki Integration

This document describes the logging implementation in the Dogetionary backend and how to query logs in Loki.

## Overview

The backend now uses **structured JSON logging** with Loki-friendly labels, making it easy to query, filter, and analyze logs in Grafana Loki.

## Key Changes

### 1. JSON-Formatted Logs

All logs are now output in JSON format with consistent fields:

```json
{
  "asctime": "2025-12-14 14:30:45,123",
  "name": "handlers.words",
  "levelname": "ERROR",
  "pathname": "/app/src/handlers/words.py",
  "lineno": 123,
  "message": "Failed to fetch word definition",
  "app": "dogetionary",
  "service": "backend",
  "level": "ERROR",
  "logger": "handlers.words",
  "file": "/app/src/handlers/words.py",
  "line": 123,
  "request_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "user_id": "user-uuid-here",
  "endpoint": "get_word_definition_v4",
  "method": "GET",
  "path": "/word",
  "error_type": "DatabaseError",
  "error_message": "Connection timeout"
}
```

### 2. Loki Labels

All logs include these standard labels:

- **`app`**: `dogetionary` (application name)
- **`service`**: `backend` (service name)
- **`level`**: Log level (INFO, WARNING, ERROR, CRITICAL)
- **`logger`**: Logger name (e.g., `handlers.words`)

### 3. Request Correlation

Every HTTP request gets a unique `request_id` (UUID) that's included in all logs for that request. This allows you to trace all log entries for a single request.

### 4. Full Stack Traces

All error logs now include full Python stack traces via `exc_info=True`, making debugging much easier.

## Log Files

Logs are written to three locations:

1. **Console** (stdout): JSON format, INFO level+
2. **`/app/logs/app.log`**: All logs (INFO+), rotated at 100MB, 50 backups (5GB total)
3. **`/app/logs/error.log`**: Error logs only (ERROR+), rotated at 50MB, 20 backups (1GB total)

## Querying Logs in Loki

### Basic Queries

**All error logs:**
```logql
{app="dogetionary"} | json | level="ERROR"
```

**Logs from a specific handler:**
```logql
{app="dogetionary"} | json | logger="handlers.words"
```

**Logs for a specific user:**
```logql
{app="dogetionary"} | json | user_id="your-user-uuid"
```

**Logs for a specific request:**
```logql
{app="dogetionary"} | json | request_id="your-request-uuid"
```

### Advanced Queries

**Errors by type:**
```logql
{app="dogetionary"} | json | error_type="DatabaseError"
```

**Slow requests (duration > 1000ms):**
```logql
{app="dogetionary"} | json | message="RESPONSE" | duration_ms > 1000
```

**Errors for a specific endpoint:**
```logql
{app="dogetionary"} | json | level="ERROR" | endpoint="get_word_definition_v4"
```

**Count errors by type (last hour):**
```logql
sum by (error_type) (
  count_over_time(
    {app="dogetionary"} | json | level="ERROR" [1h]
  )
)
```

**Top error-generating endpoints:**
```logql
topk(10,
  sum by (endpoint) (
    count_over_time(
      {app="dogetionary"} | json | level="ERROR" [1h]
    )
  )
)
```

### Request Tracing

To trace a complete request lifecycle:

1. Find the request_id from an error log
2. Query all logs for that request:

```logql
{app="dogetionary"} | json | request_id="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
```

This will show:
- REQUEST log (incoming request details)
- All processing logs
- Any errors
- RESPONSE log (with duration)

## Error Logging Helper

For new code, you can use the `log_error()` helper function:

```python
from middleware.logging import log_error

try:
    # Your code here
    result = save_word(user_id, word, language)
except Exception as e:
    log_error(
        logger,
        "Failed to save word",
        user_id=user_id,
        word=word,
        language=language
    )
    return jsonify({"error": "Failed to save word"}), 500
```

This automatically:
- Logs with `exc_info=True` (full stack trace)
- Adds request_id from request context
- Adds user_id from request context
- Includes error_type and error_message
- Includes any custom context you provide

## Monitoring Recommendations

### Key Metrics to Monitor

1. **Error Rate by Endpoint**
   ```logql
   rate({app="dogetionary"} | json | level="ERROR" [5m])
   ```

2. **P95 Response Time**
   ```logql
   histogram_quantile(0.95,
     sum(rate({app="dogetionary"} | json | message="RESPONSE" | unwrap duration_ms [5m])) by (le)
   )
   ```

3. **Database Errors**
   ```logql
   {app="dogetionary"} | json | level="ERROR" | error_type=~".*Database.*"
   ```

4. **User-Specific Issues**
   ```logql
   {app="dogetionary"} | json | level="ERROR" | user_id=~".+"
   ```

### Alerts to Configure

1. **High Error Rate**: > 10 errors/minute
2. **Slow Responses**: P95 > 2000ms
3. **Database Connection Errors**: Any occurrence
4. **4xx Rate Spike**: > 20% increase

## Log Levels

- **DEBUG**: Development/troubleshooting (not currently used in production)
- **INFO**: Normal operations (requests, responses, workflow steps)
- **WARNING**: Non-critical issues (missing data, fallback behavior)
- **ERROR**: Exceptions and errors that need attention
- **CRITICAL**: Not currently used

## Development vs Production

The log level is currently set to **INFO** for both development and production. All log formatters use the same JSON format for consistency.

## Migration Notes

### What Changed

1. **Log Format**: Plain text → JSON
2. **Stack Traces**: Added `exc_info=True` to all error logs (26 files updated)
3. **Request IDs**: Added to all HTTP requests
4. **Loki Labels**: Added app, service, level, logger fields

### What Stayed the Same

- Log files locations (`/app/logs/`)
- File rotation settings
- Log levels (INFO minimum)
- Logger initialization pattern

### Backward Compatibility

The changes are backward compatible. Existing log parsing tools may need updates to handle JSON format, but the logs contain all the same information (and more).

## Testing

To test the logging changes:

1. **Start the backend:**
   ```bash
   docker-compose down
   docker-compose build app --no-cache
   docker-compose up -d
   ```

2. **Make a request:**
   ```bash
   curl "http://localhost:5000/word?w=hello&user_id=test-uuid&learning_lang=en&native_lang=zh"
   ```

3. **Check the logs:**
   ```bash
   docker-compose logs app | tail -20
   ```

   You should see JSON-formatted logs with request_id, endpoint, etc.

4. **Trigger an error:**
   ```bash
   curl "http://localhost:5000/word?w=hello"  # Missing required params
   ```

5. **Check error logs:**
   ```bash
   docker exec -it dogetionary-app-1 cat /app/logs/error.log | tail -1 | jq .
   ```

   You should see a JSON error log with full stack trace.

## Next Steps

1. **Deploy**: Rebuild and deploy the backend with the new logging
2. **Configure Loki**: Ensure Loki is scraping `/app/logs/app.log`
3. **Create Dashboards**: Use the LogQL queries above to create Grafana dashboards
4. **Set Up Alerts**: Configure alerts for high error rates and slow responses
5. **Train Team**: Share this documentation with the team

## Troubleshooting

**Problem**: Logs are not appearing in Loki
- Check Loki scrape config includes `/app/logs/app.log`
- Verify file permissions on log files
- Check Loki agent is running

**Problem**: Logs are not in JSON format
- Verify `python-json-logger` is installed: `pip list | grep python-json-logger`
- Check `middleware/logging.py` is using `LokiJsonFormatter`
- Restart the backend after changes

**Problem**: request_id is missing
- Ensure `log_request_info()` middleware is registered in `app.py`
- Check that the request is going through Flask (not bypassing middleware)

**Problem**: Stack traces are missing
- Verify `exc_info=True` is in the logger.error call
- Check that you're actually in an exception handler (`except` block)
