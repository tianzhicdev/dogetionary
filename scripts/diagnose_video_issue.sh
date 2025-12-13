#!/bin/bash
# Diagnose iOS video playback issue

echo "================================================================================"
echo "iOS VIDEO PLAYBACK DIAGNOSTIC"
echo "================================================================================"
echo ""

# Check if local backend is running
echo "1. Checking local backend..."
if curl -s http://localhost:5001/health > /dev/null 2>&1; then
    echo "   ✓ Local backend is running"
else
    echo "   ✗ Local backend is NOT running"
    echo "   Start it with: docker-compose up -d"
fi

# Check if remote backend is accessible
echo ""
echo "2. Checking remote backend..."
if curl -s https://kwafy.com/api/health > /dev/null 2>&1; then
    echo "   ✓ Remote backend is accessible"
else
    echo "   ✗ Remote backend is NOT accessible"
fi

# Download and compare a video from both
echo ""
echo "3. Downloading test video from LOCAL backend..."
LOCAL_VIDEO_ID=11
if curl -s http://localhost:5001/v3/videos/$LOCAL_VIDEO_ID --output /tmp/diagnostic_local.mp4 2>&1 | grep -q "200"; then
    LOCAL_SIZE=$(stat -f%z /tmp/diagnostic_local.mp4 2>/dev/null || stat -c%s /tmp/diagnostic_local.mp4)
    echo "   ✓ Downloaded local video (${LOCAL_SIZE} bytes)"

    echo "   Local video streams:"
    ffprobe -v error -show_entries stream=codec_type /tmp/diagnostic_local.mp4 2>&1 | grep codec_type | sed 's/^/     /'
else
    echo "   ✗ Failed to download local video"
fi

echo ""
echo "4. Downloading test video from REMOTE backend..."
REMOTE_VIDEO_ID=724
if curl -s https://kwafy.com/api/v3/videos/$REMOTE_VIDEO_ID --output /tmp/diagnostic_remote.mp4 2>&1 | grep -q "200"; then
    REMOTE_SIZE=$(stat -f%z /tmp/diagnostic_remote.mp4 2>/dev/null || stat -c%s /tmp/diagnostic_remote.mp4)
    echo "   ✓ Downloaded remote video (${REMOTE_SIZE} bytes)"

    echo "   Remote video streams:"
    ffprobe -v error -show_entries stream=codec_type /tmp/diagnostic_remote.mp4 2>&1 | grep codec_type | sed 's/^/     /'
else
    echo "   ✗ Failed to download remote video"
fi

echo ""
echo "5. Testing video playback with QuickTime..."
echo "   Opening local video..."
qlmanage -p /tmp/diagnostic_local.mp4 > /dev/null 2>&1 &
sleep 2
killall qlmanage 2>/dev/null

echo "   Opening remote video..."
qlmanage -p /tmp/diagnostic_remote.mp4 > /dev/null 2>&1 &
sleep 2
killall qlmanage 2>/dev/null

echo ""
echo "6. Checking video compatibility..."
echo "   Local video codec:"
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,profile,level /tmp/diagnostic_local.mp4 2>&1 | grep -E "codec_name|profile|level" | sed 's/^/     /'

echo ""
echo "   Remote video codec:"
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,profile,level /tmp/diagnostic_remote.mp4 2>&1 | grep -E "codec_name|profile|level" | sed 's/^/     /'

echo ""
echo "================================================================================"
echo "SUMMARY"
echo "================================================================================"

# Compare
if [ -f /tmp/diagnostic_local.mp4 ] && [ -f /tmp/diagnostic_remote.mp4 ]; then
    LOCAL_STREAMS=$(ffprobe -v error -show_entries stream=codec_type /tmp/diagnostic_local.mp4 2>&1 | grep -c "codec_type")
    REMOTE_STREAMS=$(ffprobe -v error -show_entries stream=codec_type /tmp/diagnostic_remote.mp4 2>&1 | grep -c "codec_type")

    echo "Local video: $LOCAL_STREAMS streams"
    echo "Remote video: $REMOTE_STREAMS streams"

    if [ "$LOCAL_STREAMS" != "$REMOTE_STREAMS" ]; then
        echo ""
        echo "⚠️  DIFFERENCE FOUND: Videos have different number of streams"
        echo "This may be causing the iOS playback issue."
    else
        echo ""
        echo "✓ Both videos have the same number of streams"
        echo "The issue may be elsewhere (network, SSL, app config, etc.)"
    fi
fi

echo ""
echo "================================================================================"
echo "NEXT STEPS"
echo "================================================================================"
echo "1. Test iOS app in simulator pointing to localhost"
echo "   - Should work if local backend is properly configured"
echo ""
echo "2. Test iOS app in simulator pointing to production"
echo "   - Set UserDefaults forceProduction = true"
echo "   - Or build in Release mode"
echo ""
echo "3. Check Xcode console logs when video fails to play"
echo "   - Look for AVPlayer errors"
echo "   - Look for network errors"
echo ""
echo "4. Use Network Inspector in Xcode to see actual HTTP traffic"
echo "================================================================================"
