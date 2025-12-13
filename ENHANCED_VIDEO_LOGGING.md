# Enhanced Video Logging - Diagnostic Guide

## What Was Added

I've added comprehensive logging to both `VideoService.swift` and `VideoQuestionView.swift` to capture detailed information about video downloads and playback.

## Changes Made

### 1. VideoService.swift (ios/dogetionary/dogetionary/Core/Services/VideoService.swift)

Enhanced the `downloadVideo()` method with detailed logging:

- **Download start**: Logs video ID, URL, and base URL
- **Network errors**: Logs error details including domain and code
- **HTTP response**: Logs status code and all headers
- **Temp file**: Logs downloaded file size and path
- **Cache operation**: Logs file move operations and final cache location
- **File verification**: Confirms cached file size and location

### 2. VideoQuestionView.swift (ios/dogetionary/dogetionary/Features/Review/VideoQuestionView.swift)

Enhanced the `loadVideo()` method with:

- **Download completion errors**: Full error details with domain, code, and userInfo
- **File existence check**: Verifies downloaded file exists and is readable
- **File size verification**: Logs actual file size in bytes
- **AVPlayer status monitoring**: Observes player status changes in real-time
- **AVPlayerItem status monitoring**: Observes playback item status
- **Detailed error reporting**: Captures AVPlayer and AVPlayerItem errors

## How to Use

### Test with Local Backend (Working Videos)

1. **Ensure local backend is running**:
   ```bash
   docker-compose up -d
   ```

2. **Build and run iOS app in Xcode**:
   - Open `ios/dogetionary/dogetionary.xcodeproj`
   - Select a simulator (e.g., iPhone 16e)
   - Build and Run (⌘R)
   - Ensure `forceProduction = false` (default for DEBUG builds)

3. **Navigate to a video question** and check Xcode console

4. **Expected logs** (successful local video):
   ```
   📥 VideoService: Starting download for video 11
      URL: http://localhost:5001/v3/videos/11
      Base URL: http://localhost:5001
   📡 VideoService: Got HTTP response for video 11
      Status code: 200
      Headers: {content-type: video/mp4, ...}
   ✓ VideoService: Downloaded to temp file - XXXXX bytes
      Temp path: /var/folders/.../tmp_file.mp4
   ✓ VideoService: Successfully cached video 11 - XXXXX bytes
      Cache path: /Users/.../Library/Caches/videos/video_11.mp4
   ✓ VideoQuestionView: Video file exists - XXXXX bytes at /Users/.../video_11.mp4
   ✓ VideoQuestionView: Created AVPlayer for video 11
      File: video_11.mp4
      Full path: /Users/.../video_11.mp4
      Player status: 0 (0=unknown, 1=ready, 2=failed)
      Player status changed to: 1
   ✓ AVPlayer ready to play
   ```

### Test with Production Backend (Failing Videos)

1. **Switch to production backend**:

   **Option A**: Add to `AppDelegate.swift` or `Configuration.swift`:
   ```swift
   UserDefaults.standard.set(true, forKey: "forceProduction")
   ```

   **Option B**: Build in Release mode (⌘B with Release configuration)

2. **Rebuild and run the app**

3. **Navigate to a video question** and check Xcode console

4. **Look for error patterns**:

   **If download fails**:
   ```
   ❌ VideoService: Network error for video 724
      Error: The request timed out
      Domain: NSURLErrorDomain
      Code: -1001
   ```

   **If HTTP error**:
   ```
   ❌ VideoService: Bad status code 403 for video 724
   ```

   **If file doesn't exist after download**:
   ```
   ❌ VideoQuestionView: Video file does NOT exist at /path/to/video_724.mp4
   ```

   **If AVPlayer fails**:
   ```
   ❌ AVPlayer failed with error: ...
      Error domain: AVFoundationErrorDomain
      Error code: -11800
      Error description: The operation could not be completed
   ```

## What to Look For

### Scenario 1: Download Fails
If you see network errors or non-200 status codes:
- **Issue**: Backend connectivity, CORS, SSL certificate, or CDN issue
- **Location**: VideoService.swift logs

### Scenario 2: Download Succeeds, File Missing
If download completes but file doesn't exist:
- **Issue**: File system permissions or cache directory issue
- **Location**: VideoService.swift cache operation logs

### Scenario 3: Download Succeeds, AVPlayer Fails
If file exists but AVPlayer reports failure:
- **Issue**: Video format/codec incompatibility or corrupted download
- **Location**: VideoQuestionView.swift AVPlayer status logs
- **Check for**: AVFoundationErrorDomain codes

### Scenario 4: AVPlayer Status Never Changes
If player status stays at 0 (unknown):
- **Issue**: Video not loading into player
- **Location**: VideoQuestionView.swift player status logs

## Next Steps Based on Findings

### If Download Fails (Network/HTTP Error)
1. Check production backend is accessible: `curl https://kwafy.com/api/health`
2. Test video download manually: `curl https://kwafy.com/api/v3/videos/724 -o test.mp4`
3. Check response headers: `curl -I https://kwafy.com/api/v3/videos/724`
4. Investigate CDN/Cloudflare settings

### If File Operations Fail
1. Check iOS app sandbox permissions
2. Verify cache directory exists and is writable
3. Check available disk space

### If AVPlayer Fails
1. Save the downloaded file and test with QuickTime
2. Run `ffprobe` on the cached file to check format
3. Compare with working local video using `ffprobe`
4. Look for specific AVFoundation error codes in Apple documentation

## Common AVFoundation Error Codes

- **-11800**: Generic playback error
- **-11828**: Cannot decode media data
- **-11850**: Video composition error
- **-12645**: Disk I/O error
- **-12318**: Connection timeout

## Files Modified

1. `/ios/dogetionary/dogetionary/Core/Services/VideoService.swift` - Lines 135-223
2. `/ios/dogetionary/dogetionary/Features/Review/VideoQuestionView.swift` - Lines 166-248

## Reverting Changes

If you need to remove the verbose logging:

```bash
cd /Users/biubiu/projects/dogetionary
git diff ios/dogetionary/dogetionary/Core/Services/VideoService.swift
git diff ios/dogetionary/dogetionary/Features/Review/VideoQuestionView.swift

# To revert:
git checkout ios/dogetionary/dogetionary/Core/Services/VideoService.swift
git checkout ios/dogetionary/dogetionary/Features/Review/VideoQuestionView.swift
```

## Build Status

✅ iOS app builds successfully with enhanced logging
- Scheme: Shojin
- Tested on: iPhone 16e Simulator (iOS 26.1)
- Build date: 2025-12-13
