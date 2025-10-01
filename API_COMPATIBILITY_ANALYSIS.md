# API Compatibility Analysis

## Problem Statement
iOS app deployed with commit `33c566e` ("toefl fix") is incompatible with current backend version due to breaking changes in API endpoints.

## Compatibility Issues Identified

### ❌ CRITICAL: Removed Endpoints
These endpoints existed in `33c566e` but were removed in current version:

1. **`/v2/word`** - Merged into `/word`
   - **Impact**: iOS potentially uses this for word validation
   - **Current**: Only `/word` exists with merged functionality

2. **`/review_next`** - Removed in favor of `/v2/review_next`
   - **Impact**: Used by older iOS versions for getting next review word
   - **Current**: Only `/v2/review_next` exists

3. **`/reviews/stats`** - Completely removed
   - **Impact**: LOW - iOS app doesn't appear to use this endpoint
   - **Current**: No replacement

4. **`/generate-illustration`** + `/illustration`** - Merged into `/get-illustration`
   - **Impact**: HIGH - iOS calls `/get-illustration` but deployed version had separate endpoints
   - **Current**: Single `/get-illustration` endpoint with cache-first logic

### ⚠️ Missing Endpoints
iOS app expects these endpoints that don't exist in either version:

1. **`/saved_words/next_due`** (line 414 in DictionaryService.swift)
   - **Impact**: UNKNOWN - might be handled gracefully with 404
   - **Action**: Need to implement or confirm iOS handles 404

## iOS App Endpoint Usage
Based on `DictionaryService.swift`, the iOS app calls:

```
✅ /save                          - EXISTS (compatible)
✅ /saved_words                   - EXISTS (compatible)
✅ /word                          - EXISTS (compatible)
✅ /v2/unsave                     - EXISTS (compatible)
✅ /audio/{text}/{language}       - EXISTS (compatible)
❌ /saved_words/next_due          - MISSING (never existed)
✅ /reviews/submit                - EXISTS (compatible)
✅ /words/{id}/details            - EXISTS (compatible)
✅ /users/{id}/preferences        - EXISTS (compatible)
✅ /v2/review_next                - EXISTS (compatible)
✅ /due_counts                    - EXISTS (compatible)
✅ /review_statistics             - EXISTS (compatible)
✅ /weekly_review_counts          - EXISTS (compatible)
✅ /progress_funnel               - EXISTS (compatible)
✅ /review_activity               - EXISTS (compatible)
✅ /leaderboard                   - EXISTS (compatible)
✅ /words/{id}/forgetting-curve   - EXISTS (compatible)
❓ /get-illustration              - DIFFERENT (was /illustration + /generate-illustration)
✅ /feedback                      - EXISTS (compatible)
✅ /reviews/progress_stats        - EXISTS (compatible)
✅ /pronunciation/practice        - EXISTS (compatible)
✅ /api/test-prep/settings        - EXISTS (compatible)
✅ /api/test-prep/stats           - EXISTS (compatible)
```

## Proposed Solution: V3 API Strategy

### Phase 1: Restore Backward Compatibility
Keep the old endpoints from `33c566e` intact and add v3 versions for new functionality:

1. **Restore removed endpoints** in current app:
   - `/v2/word` - Restore with original functionality
   - `/review_next` - Restore pointing to original handler
   - `/reviews/stats` - Restore with original handler
   - `/generate-illustration` + `/illustration` - Restore separate endpoints

2. **Create v3 endpoints** in `app_v3.py`:
   - `/v3/word` - Current merged functionality
   - `/v3/review_next` - Points to current v2 handler
   - `/v3/illustration` - Current merged cache-first logic

3. **Add missing endpoint**:
   - `/saved_words/next_due` - Implement or return appropriate response

### Phase 2: Gradual Migration
Update iOS app to use v3 endpoints:
- New iOS versions use `/v3/*` endpoints
- Old iOS versions continue using original endpoints
- Monitor usage to determine when to deprecate old endpoints

### Phase 3: Cleanup (Future)
Once all iOS apps are upgraded:
- Remove old endpoints
- Move v3 endpoints to be the default
- Clean up duplicate code

## Implementation Plan

1. **Create `app_v3.py`** with current API versions
2. **Restore compatibility endpoints** in main app
3. **Test both old and new endpoint versions**
4. **Deploy with both versions supported**
5. **Monitor endpoint usage analytics**
6. **Plan deprecation timeline**

This strategy ensures zero downtime and no broken user experiences while enabling future API evolution.