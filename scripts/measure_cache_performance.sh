#!/bin/bash
# Enhanced Cache Performance Measurement Script
# Tests cache performance for Videos, Audio, and Definitions
#
# Usage:
#   ./scripts/measure_cache_performance.sh [domain]
#
# Examples:
#   # Test localhost (no Cloudflare)
#   ./scripts/measure_cache_performance.sh
#
#   # Test production with Cloudflare
#   ./scripts/measure_cache_performance.sh https://kwafy.com

DOMAIN=${1:-http://localhost:5001}

# Test data
VIDEO_ID=4463
AUDIO_TEXT="hello"
AUDIO_LANG="en"
WORD="hello"
LEARNING_LANG="en"
NATIVE_LANG="zh"
USER_ID="test-cache-user"

# Build URLs
VIDEO_URL="${DOMAIN}/api/v3/videos/${VIDEO_ID}"
AUDIO_URL="${DOMAIN}/api/v3/audio/${AUDIO_TEXT}/${AUDIO_LANG}"
DEFINITION_URL="${DOMAIN}/api/v3/word?w=${WORD}&learning_lang=${LEARNING_LANG}&native_lang=${NATIVE_LANG}&user_id=${USER_ID}"

echo "=============================================="
echo "  Cache Performance Test - ALL ENDPOINTS"
echo "=============================================="
echo "Domain: ${DOMAIN}"
echo ""

# Clear local curl cache
rm -f /tmp/cache_test_*

#############################################
# Test Function
#############################################
test_endpoint() {
    local NAME=$1
    local URL=$2
    local OUTPUT_FILE=$3

    echo "=============================================="
    echo "Testing: ${NAME}"
    echo "=============================================="
    echo "URL: ${URL}"
    echo ""

    echo "Request 1: CACHE MISS (should fetch from origin)"
    echo "----------------------------------------------"
    RESULT1=$(curl -s -o "${OUTPUT_FILE}_1" -w "HTTP: %{http_code} | Time: %{time_total}s | Size: %{size_download} bytes | Speed: %{speed_download} bytes/s\n" \
      -H "Cache-Control: no-cache" \
      -H "Pragma: no-cache" \
      "${URL}" 2>&1)

    echo "$RESULT1"

    # Show cache headers
    echo "Cache Headers:"
    curl -s -I "${URL}" | grep -i "cf-cache-status\|cache-control\|cdn-cache-control\|etag\|vary" || echo "  (No Cloudflare headers - testing localhost?)"
    echo ""

    # Wait for cache to settle
    sleep 1

    echo "Request 2: CACHE HIT (should be from Cloudflare edge)"
    echo "----------------------------------------------"
    RESULT2=$(curl -s -o "${OUTPUT_FILE}_2" -w "HTTP: %{http_code} | Time: %{time_total}s | Size: %{size_download} bytes | Speed: %{speed_download} bytes/s\n" \
      "${URL}" 2>&1)

    echo "$RESULT2"

    # Show cache headers for second request
    echo "Cache Headers (2nd request):"
    curl -s -I "${URL}" | grep -i "cf-cache-status\|age\|etag" || echo "  (No Cloudflare headers)"
    echo ""

    # Calculate improvement
    TIME1=$(echo "$RESULT1" | grep -o "Time: [0-9.]*s" | awk '{print $2}' | sed 's/s//')
    TIME2=$(echo "$RESULT2" | grep -o "Time: [0-9.]*s" | awk '{print $2}' | sed 's/s//')

    if [ -n "$TIME1" ] && [ -n "$TIME2" ] && [ "$TIME1" != "0.000" ] && [ "$TIME2" != "0.000" ]; then
        IMPROVEMENT=$(echo "scale=1; ($TIME1 - $TIME2) / $TIME1 * 100" | bc 2>/dev/null || echo "N/A")
        SPEEDUP=$(echo "scale=1; $TIME1 / $TIME2" | bc 2>/dev/null || echo "N/A")

        echo "Performance Summary:"
        echo "  1st Request (MISS): ${TIME1}s"
        echo "  2nd Request (HIT):  ${TIME2}s"
        echo "  Improvement:        ${IMPROVEMENT}%"
        echo "  Speedup:            ${SPEEDUP}x faster"
    else
        echo "Performance Summary: Unable to calculate (times too small or invalid)"
    fi

    echo ""
}

#############################################
# Run Tests
#############################################

test_endpoint "VIDEO" "$VIDEO_URL" "/tmp/cache_test_video"
test_endpoint "AUDIO" "$AUDIO_URL" "/tmp/cache_test_audio"
test_endpoint "DEFINITION" "$DEFINITION_URL" "/tmp/cache_test_definition"

#############################################
# Final Summary
#############################################

echo "=============================================="
echo "  CLOUDFLARE CACHE STATUS GUIDE"
echo "=============================================="
echo "  HIT        ✅ Served from Cloudflare cache"
echo "  MISS       ⚠️  Not in cache, fetched from origin"
echo "  EXPIRED    🔄 Was cached but expired, revalidated"
echo "  BYPASS     ❌ Not cached (check cache rules!)"
echo "  DYNAMIC    ❌ Cloudflare won't cache by default"
echo ""
echo "If you see 'BYPASS' or 'DYNAMIC':"
echo "  1. Go to Cloudflare Dashboard > Caching > Cache Rules"
echo "  2. Create rules for:"
echo "     - *kwafy.com/api/v3/videos/*"
echo "     - *kwafy.com/api/v3/audio/*"
echo "     - *kwafy.com/api/v3/word?*"
echo "  3. Set: Eligible for cache = Yes, Respect origin TTL"
echo ""
echo "Expected Results (Production with Cloudflare):"
echo "  - First request: cf-cache-status: MISS"
echo "  - Second request: cf-cache-status: HIT"
echo "  - Performance: 70-95% faster on cache HIT"
echo ""
echo "Documentation: docs/CLOUDFLARE_CACHING_PLAN.md"
echo "=============================================="
