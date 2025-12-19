# Request ID Tracing

End-to-end request tracing between iOS client and Flask backend using `X-Request-ID` header.

## Overview

Every HTTP request now includes a unique request ID that appears in both iOS and backend logs, enabling perfect correlation for debugging.

## Architecture

### Request Flow:

```
┌─────────────┐
│  iOS Client │
│             │  1. Generate UUID
│             │  2. Add X-Request-ID header
│             │  3. Make HTTP request
└──────┬──────┘
       │
       │  X-Request-ID: abc123...
       │
       ▼
┌─────────────┐
│   Backend   │
│             │  4. Extract X-Request-ID from header
│             │  5. Log with request_id in all logs
│             │  6. Return response
└─────────────┘
```

### Implementation Locations:

#### iOS (Single Point):
- **`BaseNetworkService.swift` (line 34-35)**
  ```swift
  let requestId = UUID().uuidString
  request.setValue(requestId, forHTTPHeaderField: "X-Request-ID")
  ```
  - ALL requests that use `performNetworkRequest()` automatically get request ID
  - Request ID logged to console and NetworkLogger

- **`NetworkInterceptor.swift` (line 66-72)**
  - Intercepts requests made with `URLSession.shared` directly
  - Adds `X-Request-ID` if missing
  - Logs all intercepted requests with request ID

- **`VideoService.swift` (line 529)**
  - Manually generates request ID for download tasks
  - Logs to NetworkLogger

#### Backend (Single Point):
- **`middleware/logging.py` (line 134)**
  ```python
  g.request_id = request.headers.get('X-Request-ID', str(uuid.uuid4()))
  ```
  - Checks for client-provided `X-Request-ID` header first
  - Falls back to server-generated UUID if missing
  - Automatically added to ALL logs via `LokiJsonFormatter`

## iOS Console Logs

With Developer Mode enabled, all network requests are logged to Xcode console with request ID:

```
📤 REQUEST [a1b2c3d4-e5f6-7890-abcd-ef1234567890] GET https://kwafy.com/api/v3/next-review-words-batch
📥 RESPONSE [a1b2c3d4-e5f6-7890-abcd-ef1234567890] 200 in 165ms
```

This makes it easy to:
- Copy request ID from console
- Search backend logs for the same ID
- Correlate timing between iOS and backend

## Usage

### Debugging a Failed Request

#### 1. On iOS (Debug Overlay):

Enable Developer Mode → Open Debug Overlay → Network Tab

You'll see:
```
Request ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890
UTC Time:   2025-12-18 19:45:23.456 UTC
METHOD:     POST
URL:        /api/v3/reviews/submit
STATUS:     500
DURATION:   2345ms
```

**IMPORTANT**: The Request ID shown here is the **same ID** sent to the backend in the `X-Request-ID` header!

#### 2. On Backend (Docker Logs):

```bash
# Monitor backend logs in real-time
./scripts/monitor_backend.sh

# Or search for specific request ID
docker-compose logs app | grep "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
```

You'll see the corresponding backend log:
```json
{
  "request_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "method": "POST",
  "path": "/api/v3/reviews/submit",
  "status_code": 500,
  "duration_ms": 2345.23,
  "error_message": "..."
}
```

### Tracing a Slow Request

**Scenario**: User reports practice mode is slow

1. **iOS**: Open debug overlay, practice a word, note the request ID
   - Example: `Request ID: abc-123` took `5234ms`

2. **Backend**: Search logs for that request ID
   ```bash
   docker-compose logs app | grep "abc-123"
   ```

3. **Analysis**: Compare timestamps
   - iOS sent request: `2025-12-18 19:45:23.456 UTC`
   - Backend received: `2025-12-18 19:45:23.789 UTC` (333ms network latency)
   - Backend responded: `2025-12-18 19:45:24.123 UTC` (334ms processing)
   - iOS received: `2025-12-18 19:45:28.690 UTC` (4567ms - NETWORK ISSUE!)

## Debug Overlay Features

### Network Tab Display:

Each request shows (tap to expand):

**Collapsed View:**
- Status indicator (green/red/gray dot)
- HTTP method badge (GET/POST)
- Endpoint path
- Timestamp (local time)

**Expanded View:**
- **Request ID** (blue, copiable) ← NEW!
- **UTC Timestamp** with milliseconds (orange, copiable) ← NEW!
- Full URL
- Request body (JSON, pretty-printed)
- Response status code
- Response body (JSON, pretty-printed)
- Response headers
- Duration (in milliseconds)
- Error message (if failed)

### UTC Timestamp Format:

```
2025-12-18 19:45:23.456 UTC
└─────┬────┘ └─────┬──────┘ └┬┘
   Date      Time (ms)      TZ
```

- **Why UTC?** Backend logs in UTC, so both sides match exactly
- **Why milliseconds?** Enables precise correlation even for fast requests

## Backend Logging

### Automatic Fields:

All logs automatically include (via `LokiJsonFormatter`):

```json
{
  "request_id": "abc-123...",
  "endpoint": "get_review_words_batch",
  "method": "GET",
  "path": "/api/v3/next-review-words-batch",
  "user_id": "C5AC37AC-...",
  "duration_ms": 234.56
}
```

### Searching Logs:

```bash
# Find all logs for a specific request
docker-compose logs app | grep "REQUEST_ID"

# Find slow requests (>1s)
docker-compose logs app | jq 'select(.duration_ms > 1000)'

# Find failed requests from a specific user
docker-compose logs app | jq 'select(.status_code >= 400 and .user_id == "USER_ID")'
```

## HTTP Header Standard

Following [RFC 7231](https://tools.ietf.org/html/rfc7231) and industry best practices:

- **Header Name**: `X-Request-ID` (standard used by AWS, GCP, nginx, etc.)
- **Format**: UUID v4 (128-bit, random)
- **Example**: `550e8400-e29b-41d4-a716-446655440000`

### Why `X-Request-ID`?

- Industry standard (AWS ALB, GCP Load Balancer, nginx all use this)
- Unique identifier for distributed tracing
- Client-generated = perfect for tracking from origin
- Supported by most logging frameworks (Loki, Elasticsearch, Datadog)

## Benefits

1. **Perfect Correlation**: Same ID in iOS logs, backend logs, and debug UI
2. **Fast Debugging**: Copy request ID from debug overlay → search backend logs
3. **Network Analysis**: Compare UTC timestamps to find network vs. backend delays
4. **Production Debugging**: Works in production (if Developer Mode enabled)
5. **No Performance Impact**: UUID generation is instant (<1μs)

## Testing

### Verify iOS Sends Request ID:

```bash
# Watch backend logs while using app
./scripts/monitor_backend.sh

# Look for X-Request-ID in request headers
```

Expected output:
```json
{
  "request_id": "a1b2c3d4-...",
  "headers": {
    "X-Request-ID": "a1b2c3d4-...",  // ← Should match request_id
    "Content-Type": "application/json"
  }
}
```

### Verify Debug Overlay Shows Request ID:

1. Enable Developer Mode in Settings
2. Open debug overlay (tap bug icon)
3. Navigate to Network tab
4. Make any API call
5. Tap to expand request
6. **Request ID** should be visible at top (blue text, copiable)
7. **UTC Time** should be visible (orange text, copiable)

## Troubleshooting

### Request ID Not Showing in Debug Overlay

- Ensure Developer Mode is enabled in Settings
- Check that `DebugConfig.isDeveloperModeEnabled` is true
- Verify `NetworkLogger.shared.logRequest()` is being called

### Backend Not Logging Request ID

- Check `X-Request-ID` header is being sent:
  ```python
  print(request.headers.get('X-Request-ID'))
  ```
- Verify `log_request_info()` is called via `app.before_request()`
- Check `LokiJsonFormatter` adds `request_id` to logs

### Request ID Mismatch Between iOS and Backend

- This shouldn't happen if using `X-Request-ID` header
- Check for middleware that modifies headers
- Verify backend reads from `request.headers.get('X-Request-ID')`

## Future Enhancements

Potential improvements:

1. **Distributed Tracing**: Send request ID to external services (OpenAI, etc.)
2. **Analytics**: Track request ID in analytics events
3. **Error Reporting**: Include request ID in crash reports
4. **Search UI**: Add search box in debug overlay to filter by request ID
5. **Export Logs**: Export debug overlay logs to file with request IDs

## References

- [X-Request-ID Standard](https://http.dev/x-request-id)
- [AWS ALB Request Tracing](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-request-tracing.html)
- [UUID v4 Specification](https://datatracker.ietf.org/doc/html/rfc4122)
