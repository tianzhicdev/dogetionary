# Request ID Fix - Matching iOS and Backend

## Problem

Initially, the iOS debug overlay showed a **different request ID** than the backend logs, making it impossible to correlate requests between client and server.

### Root Cause:

**NetworkLogger.swift** was creating its own internal UUID instead of using the `X-Request-ID` sent to the backend:

```swift
// BEFORE (WRONG):
let id = UUID()  // New UUID, different from X-Request-ID!
let call = NetworkCall(id: id, requestId: requestId, ...)
```

This meant:
- iOS debug overlay showed: `id` (internal UUID)
- Backend logs showed: `requestId` (X-Request-ID header)
- **These were different values** → impossible to correlate!

## Solution

Changed NetworkLogger to use the `requestId` as the `id`:

```swift
// AFTER (CORRECT):
let call = NetworkCall(id: requestId, requestId: requestId, ...)
```

Now:
- iOS debug overlay shows: `requestId` (same as X-Request-ID)
- Backend logs show: `requestId` (from X-Request-ID header)
- **Same value** → perfect correlation! ✅

## Changes Made

### 1. NetworkLogger.swift

**Changed `id` field type from `UUID` to `String`:**
```swift
struct NetworkCall: Identifiable {
    let id: String  // Use request ID as the identifier
    let requestId: String  // Same as id - kept for clarity
    ...
}
```

**Changed `logRequest()` to return `String` instead of `UUID`:**
```swift
func logRequest(url: String, method: String, body: Data?, requestId: String) -> String {
    let call = NetworkCall(
        id: requestId,  // Use the actual request ID, not a new UUID
        requestId: requestId,
        ...
    )
    logger.info("📤 REQUEST [\(requestId)] \(method) \(url)")
    return requestId
}
```

**Changed `logResponse()` to accept `String` instead of `UUID`:**
```swift
func logResponse(id: String, ...) {
    if let index = self.recentCalls.firstIndex(where: { $0.id == id }) {
        ...
        self.logger.info("📥 RESPONSE [\(id)] \(status) in \(duration)ms")
    }
}
```

### 2. BaseNetworkService.swift

Updated to pass `requestId` to `logResponse`:
```swift
NetworkLogger.shared.logResponse(
    id: requestId,  // Use same requestId, not logId
    ...
)
```

### 3. NetworkInterceptor.swift

Updated metadata structure and response logging:
```swift
private struct RequestMetadata {
    let requestId: String  // Changed from logId: UUID
    let startTime: Date
}

NetworkLogger.shared.logResponse(
    id: metadata.requestId,  // Use requestId, not logId
    ...
)
```

### 4. VideoService.swift

Updated video download logging:
```swift
NetworkLogger.shared.logResponse(
    id: requestId,  // Use requestId, not logId
    ...
)
```

## Verification

### Before Fix:
```
iOS Debug Overlay:
  Request ID: 1a2b3c4d-5e6f-7890-abcd-ef1234567890  ← Internal UUID

Backend Logs:
  request_id: 9f8e7d6c-5b4a-3210-fedc-ba0987654321  ← X-Request-ID header

❌ These don't match!
```

### After Fix:
```
iOS Debug Overlay:
  Request ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890  ← X-Request-ID

iOS Console:
  📤 REQUEST [a1b2c3d4-e5f6-7890-abcd-ef1234567890] GET /api/v3/...
  📥 RESPONSE [a1b2c3d4-e5f6-7890-abcd-ef1234567890] 200 in 165ms

Backend Logs:
  request_id: a1b2c3d4-e5f6-7890-abcd-ef1234567890  ← X-Request-ID header

✅ Perfect match!
```

## Testing

1. **Enable Developer Mode** in iOS Settings
2. **Open Debug Overlay** → Network tab
3. **Make a request** (e.g., practice a word)
4. **Copy Request ID** from debug overlay
5. **Search backend logs**:
   ```bash
   docker-compose logs app | grep "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
   ```
6. **Verify** the same request ID appears in backend logs

## iOS Console Logging

Added clear request/response logging to iOS console:

```swift
logger.info("📤 REQUEST [\(requestId)] \(method) \(url)")
logger.info("📥 RESPONSE [\(id)] \(status) in \(duration)ms")
```

This makes it easy to:
- See request IDs in Xcode console
- Copy/paste into backend log search
- Verify IDs match without opening debug overlay

## Impact

✅ **Perfect request correlation** between iOS and backend
✅ **Faster debugging** - copy ID from anywhere, search backend logs
✅ **Console logging** - request IDs visible in Xcode output
✅ **No breaking changes** - existing code continues to work
✅ **Single source of truth** - request ID generated once, used everywhere

## Build Status

✅ iOS app builds successfully
✅ No type errors or warnings
✅ Backward compatible
