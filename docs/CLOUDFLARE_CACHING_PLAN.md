# Cloudflare Caching Implementation Plan

## Summary

This document outlines the caching strategy for audio, video, and definition endpoints to optimize performance and reduce origin server load.

## ✅ Changes Implemented

### 1. Backend Cache Headers Added

#### Audio Endpoint (`/v3/audio/{text}/{language}`)
- **File**: `/src/handlers/words.py:422-480`
- **Cache Headers Added**:
  ```python
  response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
  response.headers['CDN-Cache-Control'] = 'public, max-age=31536000, immutable'
  response.headers['Cloudflare-CDN-Cache-Control'] = 'public, max-age=31536000'
  response.headers['ETag'] = f'"{etag}"'  # MD5 hash of text:language
  response.headers['X-Content-Type-Options'] = 'nosniff'
  ```
- **Cacheable**: ✅ YES (based on text+language only, no user-specific data)

#### Definition Endpoint (`/v3/word?w={word}&learning_lang=en&native_lang=zh`)
- **File**: `/src/handlers/words.py:246-277`
- **Cache Headers Added**:
  ```python
  response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
  response.headers['CDN-Cache-Control'] = 'public, max-age=31536000, immutable'
  response.headers['Cloudflare-CDN-Cache-Control'] = 'public, max-age=31536000'
  response.headers['ETag'] = f'"{etag}"'  # MD5 hash of word:learning_lang:native_lang
  response.headers['X-Content-Type-Options'] = 'nosniff'
  response.headers['Vary'] = 'Accept, Accept-Encoding'
  ```
- **Cacheable**: ✅ YES (based on word+learning_lang+native_lang, user_id only for preference fallback)
- **Note**: iOS app already sends both language codes, so user_id doesn't affect cache

#### Video Endpoint (`/v3/videos/{video_id}`)
- **File**: `/src/handlers/videos.py:69-88`
- **Status**: ✅ Already implemented (reference implementation)

## 📋 Cloudflare Configuration URLs

### Cache Rules to Create

You need to configure **3 Cache Rules** in Cloudflare Dashboard:

#### Rule 1: Cache Videos
1. **Go to**: [Cloudflare Dashboard](https://dash.cloudflare.com) → Select `kwafy.com` → **Caching** → **Cache Rules**
2. **Click**: "Create Rule"
3. **Rule Name**: `Cache Videos API`
4. **When incoming requests match**:
   - Field: `URL`
   - Operator: `matches`
   - Value: `*kwafy.com/api/v3/videos/*`
5. **Then**:
   - Eligible for cache: `Yes`
   - Edge Cache TTL: `Respect origin` (already set to 1 year in headers)
   - Browser Cache TTL: `Respect origin`
6. **Save and Deploy**

#### Rule 2: Cache Audio
1. **Rule Name**: `Cache Audio API`
2. **When incoming requests match**:
   - Field: `URL`
   - Operator: `matches`
   - Value: `*kwafy.com/api/v3/audio/*`
3. **Then**:
   - Eligible for cache: `Yes`
   - Edge Cache TTL: `Respect origin`
   - Browser Cache TTL: `Respect origin`
4. **Save and Deploy**

#### Rule 3: Cache Definitions
1. **Rule Name**: `Cache Definitions API`
2. **When incoming requests match**:
   - Field: `URL`
   - Operator: `matches`
   - Value: `*kwafy.com/api/v3/word?*`
3. **Then**:
   - Eligible for cache: `Yes`
   - Edge Cache TTL: `Respect origin`
   - Browser Cache TTL: `Respect origin`
   - **Cache on Cookie**: Disabled
4. **Save and Deploy**

### Alternative: Page Rules (if Cache Rules unavailable)

If you're on an older Cloudflare plan without Cache Rules:

1. **Go to**: **Rules** → **Page Rules**
2. **Create 3 Page Rules**:
   - `*kwafy.com/api/v3/videos/*` → Cache Level: Cache Everything, Edge TTL: 1 year
   - `*kwafy.com/api/v3/audio/*` → Cache Level: Cache Everything, Edge TTL: 1 year
   - `*kwafy.com/api/v3/word*` → Cache Level: Cache Everything, Edge TTL: 1 year

## 🧪 Testing

### Enhanced Test Script

The test script has been enhanced to test all three endpoints:

**Location**: `/scripts/measure_cache_performance.sh`

**Usage**:
```bash
# Test localhost (no Cloudflare)
./scripts/measure_cache_performance.sh

# Test production (with Cloudflare)
./scripts/measure_cache_performance.sh https://kwafy.com
```

**What it tests**:
1. **Videos**: `/api/v3/videos/4463` (existing test)
2. **Audio**: `/api/v3/audio/hello/en` (NEW)
3. **Definitions**: `/api/v3/word?w=hello&learning_lang=en&native_lang=zh&user_id=test` (NEW)

**Expected Results**:
- First request: `cf-cache-status: MISS` (fetching from origin)
- Second request: `cf-cache-status: HIT` (served from Cloudflare edge)
- Performance: 80-95% faster on cache HIT

## 📊 Expected Performance Improvements

| Endpoint | Origin Time | Cached Time | Improvement |
|----------|-------------|-------------|-------------|
| Videos (1MB) | 500-1000ms | 50-100ms | 80-90% |
| Audio (50KB) | 100-300ms | 20-50ms | 70-80% |
| Definitions (5KB) | 50-200ms | 10-30ms | 75-85% |

## ⚠️ Important Notes

### Why Definitions Are Cacheable Despite user_id

Looking at `/src/handlers/words.py:190-205`:
```python
user_id = request.args.get('user_id')
learning_lang = request.args.get('learning_lang')
native_lang = request.args.get('native_lang')

# user_id is ONLY used if langs not provided
if not learning_lang or not native_lang:
    user_learning_lang, user_native_lang, _, _ = get_user_preferences(user_id)
    learning_lang = learning_lang or user_learning_lang
    native_lang = native_lang or user_native_lang
```

**Key Insight**: The iOS app **always sends both language codes** (learning_lang and native_lang), so `user_id` is never actually used for definition lookup. It's purely for backward compatibility.

This means definitions are effectively keyed by `word + learning_lang + native_lang` only, making them perfectly cacheable.

### Cache Key Handling

Cloudflare will cache based on the full URL including query parameters. Since different users with the same word+language combination will get identical responses, caching is safe and beneficial.

## 🚀 Deployment Checklist

- [x] Add cache headers to audio endpoint
- [x] Add cache headers to definition endpoint
- [x] Create enhanced test script
- [ ] Restart backend: `docker-compose restart app`
- [ ] Test locally with test script
- [ ] Deploy to production
- [ ] Create 3 Cloudflare Cache Rules (or Page Rules)
- [ ] Test production with enhanced script
- [ ] Verify `cf-cache-status: HIT` on second requests
- [ ] Monitor Cloudflare Analytics cache ratio (target >90%)
- [ ] Test in iOS app for performance improvement

## 📈 Monitoring

### Cloudflare Dashboard
- **Go to**: **Analytics** → **Caching**
- **Monitor**:
  - Cache Ratio (should be >90% after warm-up)
  - Bandwidth Saved
  - Requests by Status (HIT vs MISS distribution)

### Backend Logs
```bash
# Check origin hit frequency (lower is better)
docker logs dogetionary-app-1 | grep "Serving video\|Serving audio"
```

## 💰 Cost Savings

With 90% cache hit rate for 1000 daily requests:

**Before Caching**:
- 1000 videos × 2MB = 2GB origin bandwidth
- 1000 audio × 50KB = 50MB origin bandwidth
- 1000 definitions × 5KB = 5MB origin bandwidth
- **Total**: ~2.1GB/day origin load
- 3000 database queries/day

**After Caching** (90% hit rate):
- 100 videos × 2MB = 200MB origin bandwidth
- 100 audio × 50KB = 5MB origin bandwidth
- 100 definitions × 5KB = 0.5MB origin bandwidth
- **Total**: ~205MB/day origin load
- 300 database queries/day

**Savings**: 90% reduction in bandwidth and database load!

## 🔗 References

- [Cloudflare Cache Rules Documentation](https://developers.cloudflare.com/cache/how-to/cache-rules/)
- [Cloudflare CDN-Cache-Control Header](https://developers.cloudflare.com/cache/about/cdn-cache-control/)
- [Video Caching Guide](./CLOUDFLARE_VIDEO_CACHE.md)
