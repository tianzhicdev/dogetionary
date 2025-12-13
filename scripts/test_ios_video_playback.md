# Test iOS Video Playback - Verification Steps

## Goal
Verify that the issue is with remote videos specifically, not with the iOS app or video format.

## Test Plan

### Step 1: Confirm local videos work in iOS app
1. Make sure iOS app is pointing to localhost (`forceProduction = false`)
2. Launch iOS app in simulator
3. Navigate to a video question
4. Confirm video plays successfully

### Step 2: Test the EXACT same video from production
1. Find a video that works locally
2. Upload it to production
3. Point iOS app to production (`forceProduction = true`)
4. Test if that same video plays

### Step 3: Compare local vs remote video data

**Test with video ID 11 (which works locally):**

```bash
# Download from local backend
curl http://localhost:5001/v3/videos/11 --output /tmp/local_11.mp4

# Check streams
ffprobe -v error -show_entries stream=codec_type,codec_name /tmp/local_11.mp4

# Upload to production (if needed)
# ... use batch-upload API ...

# Download same video from production
curl https://kwafy.com/api/v3/videos/PRODUCTION_ID --output /tmp/remote_11.mp4

# Compare
diff <(ffprobe -v error -show_format -show_streams /tmp/local_11.mp4) \
     <(ffprobe -v error -show_format -show_streams /tmp/remote_11.mp4)
```

### Step 4: Check Configuration.swift

The iOS app determines which backend to use based on:
- `#if DEBUG` → uses localhost (development)
- `#else` → uses production
- `UserDefaults forceProduction` → can override

**Verify current setting:**
```swift
// In Configuration.swift
static var forceProduction: Bool {
    UserDefaults.standard.bool(forKey: "forceProduction")
}
```

**To test production videos in debug build:**
1. Add this line in iOS app somewhere that runs on launch:
   ```swift
   UserDefaults.standard.set(true, forKey: "forceProduction")
   ```
2. Rebuild and run
3. App will now use production backend

### Step 5: Check actual iOS error logs

When video fails to play, check Xcode console for AVPlayer errors:
1. Open Xcode
2. Run app with production backend
3. Try to play a video
4. Look for error messages in console like:
   - "Failed to load video"
   - AVPlayer error codes
   - Network errors (403, 404, etc.)

### Step 6: Network inspection

Use Charles Proxy or Xcode Network Inspector to see:
1. Is the video being downloaded?
2. What's the HTTP status code?
3. What's the actual Content-Type header?
4. Is there a CORS error?

## Expected Results

If local videos work but remote don't, the issue is likely:
- [ ] Different video encoding/format
- [ ] Network/CDN issue (Cloudflare)
- [ ] CORS/security headers
- [ ] Video size limits
- [ ] SSL/TLS certificate issue

If both local and remote videos fail:
- [ ] iOS app bug
- [ ] VideoService download logic
- [ ] AVPlayer initialization issue

If both work when tested directly but fail in app:
- [ ] App configuration issue
- [ ] Caching problem
- [ ] File permissions
