# Cloudflare Video Caching Setup

This guide explains how to configure Cloudflare to cache video files for optimal performance.

## Overview

Video files are served from `/api/v3/videos/<video_id>` with the following optimizations:
- **Browser Cache**: 1 year (365 days)
- **CDN Cache**: 1 year (365 days)
- **ETag Support**: For cache validation
- **Range Requests**: For video seeking

## Backend Configuration

The backend (`src/handlers/videos.py`) already includes optimized headers:

```python
headers={
    # Browser caching
    'Cache-Control': 'public, max-age=31536000, immutable',
    # Cloudflare CDN caching
    'CDN-Cache-Control': 'public, max-age=31536000, immutable',
    'Cloudflare-CDN-Cache-Control': 'public, max-age=31536000',
    # Cache validation
    'ETag': f'"{video_id}"',
    # Video seeking support
    'Accept-Ranges': 'bytes'
}
```

## Cloudflare Cache Rules Setup

⚠️ **IMPORTANT**: Cloudflare doesn't cache everything by default, even with `Cache-Control` headers. You must configure Cache Rules.

### Option 1: Cache Rules (Recommended - New Interface)

1. **Go to Cloudflare Dashboard**
   - Select your domain (kwafy.com)
   - Navigate to: **Caching** → **Cache Rules**

2. **Create a New Cache Rule**
   - Click "Create Rule"
   - Rule name: `Cache Videos API`

3. **Configure Rule Matching**
   - Field: `URL`
   - Operator: `matches`
   - Value: `*kwafy.com/api/v3/videos/*`

4. **Configure Cache Settings**
   - **Eligible for cache**: `Yes` (or "All" if option available)
   - **Edge Cache TTL**: `Respect origin` (or set to 1 year = 31536000 seconds)
   - **Browser Cache TTL**: `Respect origin`
   - **Cache on Cookie**: Disabled (videos don't need cookies)

5. **Save and Deploy**

### Option 2: Page Rules (Legacy Method)

If Cache Rules aren't available, use Page Rules:

1. **Go to Cloudflare Dashboard**
   - Navigate to: **Rules** → **Page Rules**

2. **Create Page Rule**
   - URL Pattern: `*kwafy.com/api/v3/videos/*`

3. **Add Settings**
   - **Cache Level**: `Cache Everything`
   - **Edge Cache TTL**: `a year` (or 31536000 seconds)
   - **Browser Cache TTL**: `Respect Existing Headers`
   - **Origin Cache Control**: `On`

4. **Save and Deploy**

### Option 3: Configuration Rules (Alternative)

For more granular control:

1. **Navigate to**: **Rules** → **Configuration Rules**
2. Create rule matching `/api/v3/videos/*`
3. Set cache settings accordingly

## Verification

### 1. Using the Measurement Script

Test both localhost and production:

```bash
# Make script executable
chmod +x scripts/measure_video_cache.sh

# Test localhost (no Cloudflare)
./scripts/measure_video_cache.sh 4463

# Test production (with Cloudflare)
./scripts/measure_video_cache.sh 4463 https://kwafy.com
```

### 2. Manual curl Testing

Test cache headers:

```bash
# Check headers
curl -I https://kwafy.com/api/v3/videos/4463

# Look for these Cloudflare headers:
# cf-cache-status: HIT    (cached)
# cf-cache-status: MISS   (not cached, first request)
# cf-cache-status: BYPASS (not being cached - check rules!)
```

### 3. Expected Results

**First Request (MISS)**:
```
cf-cache-status: MISS
Time: ~500-2000ms (depends on video size and origin latency)
```

**Second Request (HIT)**:
```
cf-cache-status: HIT
age: 123 (seconds since cached)
Time: ~50-200ms (90% faster from edge)
```

## Performance Expectations

| Scenario | Origin Server | Cloudflare Edge | Improvement |
|----------|--------------|----------------|-------------|
| 1MB video | 500-1000ms | 50-100ms | 80-90% faster |
| 5MB video | 2000-4000ms | 100-200ms | 90-95% faster |

## Troubleshooting

### Cache Status: BYPASS or DYNAMIC

**Problem**: Videos aren't being cached

**Solutions**:
1. Verify Cache Rules are created and enabled
2. Check rule URL pattern matches your endpoint
3. Ensure "Cache Everything" is enabled
4. Verify no other rules are conflicting
5. Check if you have the correct Cloudflare plan (Free tier supports caching)

### Cache Status: EXPIRED

**Problem**: Cache expires too quickly

**Solutions**:
1. Check `Edge Cache TTL` is set to 1 year
2. Verify `CDN-Cache-Control` header is present
3. Ensure origin returns proper `Cache-Control` headers

### No cf-cache-status Header

**Problem**: Not seeing Cloudflare headers

**Solutions**:
1. Verify you're accessing through Cloudflare (not direct origin)
2. Check DNS is pointing to Cloudflare
3. Ensure SSL/TLS is properly configured

## Monitoring Cache Performance

### Using Cloudflare Analytics

1. Go to **Analytics** → **Caching**
2. Monitor:
   - **Cache Ratio**: Should be >90% after warm-up
   - **Bandwidth Saved**: Shows origin offload
   - **Requests by Status**: HIT vs MISS distribution

### Using Backend Logs

Check `src/handlers/videos.py` logs to see origin hits:
```bash
# Low log volume = high cache hit rate = good!
docker logs dogetionary-app-1 | grep "Serving video"
```

### Prometheus Metrics

If you have Prometheus setup, track:
- Request counts by endpoint
- Response times
- Origin vs cached requests

## Cost Optimization

### Origin Bandwidth Savings

With 90% cache hit rate:
- **Before**: 1000 requests × 2MB = 2GB origin bandwidth
- **After**: 100 requests × 2MB = 200MB origin bandwidth
- **Savings**: 1.8GB (90% reduction)

### Database Load Reduction

Each cached video avoids:
- 1 PostgreSQL query
- 1 BYTEA data fetch
- Python serialization overhead

## Best Practices

1. **Always Use ETag**: Enables conditional requests
2. **Set immutable**: Videos never change (use new ID for updates)
3. **Monitor Cache Ratio**: Target >90% hit rate
4. **Purge Selectively**: Only purge specific videos if updated
5. **Test After Deployment**: Always verify cache is working

## iOS App Integration

The iOS app benefits automatically once caching is configured:

```swift
// VideoService.swift already includes proper cache headers
// No changes needed on iOS side
```

Videos will load much faster on subsequent plays!

## Deployment Checklist

- [ ] Updated `src/handlers/videos.py` with new cache headers
- [ ] Rebuilt backend: `docker-compose build app --no-cache`
- [ ] Deployed to production
- [ ] Created Cloudflare Cache Rule for `/api/v3/videos/*`
- [ ] Tested with `measure_video_cache.sh` script
- [ ] Verified `cf-cache-status: HIT` on second request
- [ ] Monitored Cloudflare Analytics cache ratio
- [ ] Tested video playback in iOS app

## Additional Resources

- [Cloudflare Cache Rules Documentation](https://developers.cloudflare.com/cache/how-to/cache-rules/)
- [Cloudflare Page Rules Documentation](https://developers.cloudflare.com/rules/page-rules/)
- [CDN-Cache-Control Header](https://developers.cloudflare.com/cache/about/cdn-cache-control/)
