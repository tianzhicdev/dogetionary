#!/bin/bash
# Video Cache Performance Measurement Script
# Tests both cache MISS (first request) and cache HIT (subsequent requests)
#
# Usage:
#   ./scripts/measure_video_cache.sh <video_id> [domain]
#
# Examples:
#   # Test localhost
#   ./scripts/measure_video_cache.sh 4463
#
#   # Test production with Cloudflare
#   ./scripts/measure_video_cache.sh 4463 https://kwafy.com

VIDEO_ID=${1:-4463}
DOMAIN=${2:-http://localhost:5001}
VIDEO_URL="${DOMAIN}/api/v3/videos/${VIDEO_ID}"

echo "======================================"
echo "Video Cache Performance Test"
echo "======================================"
echo "Video ID: ${VIDEO_ID}"
echo "Domain: ${DOMAIN}"
echo "URL: ${VIDEO_URL}"
echo ""

# Clear local curl cache
rm -f /tmp/curl_cache_*

echo "Test 1: CACHE MISS (First Request - Origin Server)"
echo "--------------------------------------"
RESULT1=$(curl -s -o /tmp/test_video_1.mp4 -w "HTTP Status: %{http_code}\nTime Connect: %{time_connect}s\nTime Start Transfer: %{time_starttransfer}s\nTime Total: %{time_total}s\nSize Downloaded: %{size_download} bytes\nSpeed Download: %{speed_download} bytes/s\n" \
  -H "Cache-Control: no-cache" \
  -H "Pragma: no-cache" \
  "${VIDEO_URL}" 2>&1)

echo "$RESULT1"
echo ""

# Extract Cloudflare cache status if available
echo "Cache Headers:"
curl -s -I "${VIDEO_URL}" | grep -i "cf-cache-status\|cache-control\|cdn-cache-control\|etag\|x-cache" || echo "No Cloudflare headers detected (testing localhost?)"
echo ""

# Wait a moment
sleep 2

echo "Test 2: CACHE HIT (Second Request - Should be from CDN)"
echo "--------------------------------------"
RESULT2=$(curl -s -o /tmp/test_video_2.mp4 -w "HTTP Status: %{http_code}\nTime Connect: %{time_connect}s\nTime Start Transfer: %{time_starttransfer}s\nTime Total: %{time_total}s\nSize Downloaded: %{size_download} bytes\nSpeed Download: %{speed_download} bytes/s\n" \
  "${VIDEO_URL}" 2>&1)

echo "$RESULT2"
echo ""

echo "Cache Headers (2nd request):"
curl -s -I "${VIDEO_URL}" | grep -i "cf-cache-status\|cache-control\|cdn-cache-control\|etag\|x-cache\|age" || echo "No Cloudflare headers detected"
echo ""

# Calculate improvement
TIME1=$(echo "$RESULT1" | grep "Time Total:" | awk '{print $3}' | sed 's/s//')
TIME2=$(echo "$RESULT2" | grep "Time Total:" | awk '{print $3}' | sed 's/s//')

if [ -n "$TIME1" ] && [ -n "$TIME2" ]; then
    IMPROVEMENT=$(echo "scale=2; ($TIME1 - $TIME2) / $TIME1 * 100" | bc)
    echo "======================================"
    echo "Performance Summary"
    echo "======================================"
    echo "1st Request (MISS): ${TIME1}s"
    echo "2nd Request (HIT):  ${TIME2}s"
    echo "Improvement:        ${IMPROVEMENT}%"
    echo ""

    # Speed comparison
    SPEED1=$(echo "$RESULT1" | grep "Speed Download:" | awk '{print $3}')
    SPEED2=$(echo "$RESULT2" | grep "Speed Download:" | awk '{print $3}')

    if [ -n "$SPEED1" ] && [ -n "$SPEED2" ]; then
        SPEED1_MB=$(echo "scale=2; $SPEED1 / 1048576" | bc)
        SPEED2_MB=$(echo "scale=2; $SPEED2 / 1048576" | bc)
        echo "1st Request Speed: ${SPEED1_MB} MB/s"
        echo "2nd Request Speed: ${SPEED2_MB} MB/s"
    fi
fi

echo ""
echo "Cloudflare Cache Status Meanings:"
echo "  HIT        - Served from Cloudflare cache"
echo "  MISS       - Not in cache, fetched from origin"
echo "  EXPIRED    - Was cached but expired, revalidated"
echo "  BYPASS     - Not cached (check cache rules)"
echo "  DYNAMIC    - Cloudflare doesn't cache by default"
echo ""
echo "If you see 'BYPASS' or 'DYNAMIC', configure Cloudflare Cache Rules:"
echo "  1. Go to Cloudflare Dashboard > Caching > Cache Rules"
echo "  2. Create rule: URL matches '/api/v3/videos/*'"
echo "  3. Set: Cache Everything, Edge TTL 1 year"
