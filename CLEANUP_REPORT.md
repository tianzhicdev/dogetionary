# Backend API Cleanup Report

## Executive Summary

**Current State:**
- Backend defines: **68 total endpoints** (27 V3 + 41 legacy)
- iOS app uses: **29 endpoints** (all V3)
- **Unused endpoints: 39** (57% of total endpoints)

**Recommendation:**
1. ✅ **Merge app.py and app_v3.py** - All iOS calls use V3 endpoints
2. ✅ **Delete 39 unused endpoints** - Safe to remove
3. ✅ **Delete legacy routes** - iOS doesn't use any non-V3 endpoints

---

## Section 1: Can We Merge app.py and app_v3.py?

### Answer: **YES ✅**

**Evidence:**
- iOS app exclusively uses `/v3/*` endpoints
- No iOS code references legacy endpoints (no prefix)
- All 29 iOS endpoint calls target V3 API

**Migration Plan:**
1. Keep only the V3 Blueprint from `app_v3.py`
2. Move health check, metrics, and privacy endpoints to V3 namespace
3. Delete all legacy route registrations from `app.py`
4. Consolidate into single `app.py` file

---

## Section 2: Endpoints to DELETE (39 total)

### Category A: Fully Unused Legacy Endpoints (33 endpoints)

These legacy endpoints have V3 equivalents that iOS uses, or are completely unused.

#### Word Management - DELETE (4 endpoints)
```python
# iOS uses /v3/word, /v3/save, /v3/unsave
DELETE /save                    # Replaced by /v3/save
DELETE /unsave                  # Replaced by /v3/unsave
DELETE /v2/unsave              # Replaced by /v3/unsave
DELETE /word                    # Replaced by /v3/word
```

#### Review System - DELETE (4 endpoints)
```python
# iOS uses /v3/reviews/submit, /v3/due_counts, /v3/next-review-words-batch
DELETE /review_next             # Old batch review system
DELETE /v2/review_next          # Old batch review system
DELETE /due_counts              # Replaced by /v3/due_counts
DELETE /reviews/submit          # Replaced by /v3/reviews/submit
```

#### Saved Words - DELETE (1 endpoint)
```python
# iOS uses /v3/saved_words
DELETE /saved_words             # Replaced by /v3/saved_words
```

#### User Preferences - DELETE (2 endpoints)
```python
# iOS uses /v3/users/<user_id>/preferences
DELETE /users/<user_id>/preferences   # Replaced by /v3/users/<user_id>/preferences
DELETE /languages                      # iOS doesn't use this
```

#### Analytics - DELETE (6 endpoints)
```python
# iOS uses /v3/words/<id>/forgetting-curve, /v3/words/<id>/details, /v3/reviews/progress_stats
DELETE /words/<int:word_id>/forgetting-curve   # Replaced by /v3/words/<id>/forgetting-curve
DELETE /words/<int:word_id>/details            # Replaced by /v3/words/<id>/details
DELETE /leaderboard                            # iOS uses /v3/leaderboard-score instead
DELETE /reviews/stats                          # iOS doesn't use this
DELETE /reviews/progress_stats                 # Replaced by /v3/reviews/progress_stats
DELETE /analytics/data                         # iOS doesn't use this
```

#### Analytics Tracking - DELETE (1 endpoint)
```python
# iOS uses /v3/analytics/track
DELETE /analytics/track         # Replaced by /v3/analytics/track
```

#### Media - DELETE (4 endpoints)
```python
# iOS uses /v3/audio/<text>/<language>, /v3/illustration
DELETE /audio/<path:text>/<language>  # Replaced by /v3/audio/<text>/<language>
DELETE /get-illustration               # Replaced by /v3/illustration
DELETE /generate-illustration          # Replaced by /v3/illustration (unified endpoint)
```

#### Pronunciation - DELETE (3 endpoints)
```python
# iOS uses /v3/pronunciation/practice, /v3/review/pronounce
DELETE /pronunciation/practice   # Replaced by /v3/pronunciation/practice
DELETE /pronunciation/stats      # iOS doesn't use this
DELETE /pronunciation/history    # iOS doesn't use this
```

#### Test Prep - DELETE (8 endpoints)
```python
# iOS uses /v3/schedule/test-progress, /v3/test-prep/stats (note: iOS calls it /v3/api/test-prep/stats)
DELETE /api/test-prep/settings (PUT)        # iOS doesn't modify test settings via API
DELETE /api/test-prep/settings (GET)        # iOS doesn't fetch test settings separately
DELETE /api/test-prep/add-words             # Automated server-side
DELETE /api/test-prep/stats                 # Replaced by /v3/test-prep/stats
DELETE /api/v3/test-vocabulary-count        # iOS doesn't use this
DELETE /api/test-prep/config                # iOS doesn't use this
DELETE /api/test-prep/batch-populate        # Admin endpoint, not used by iOS
DELETE /api/test-prep/run-daily-job         # Admin endpoint, not used by iOS
```

---

### Category B: V3 Endpoints to DELETE (6 endpoints)

These V3 endpoints are defined but iOS doesn't call them.

#### Test Prep V3 - DELETE (5 endpoints)
```python
DELETE /v3/test-prep/settings (PUT)        # Line 118 - iOS doesn't modify settings via API
DELETE /v3/test-prep/settings (GET)        # Line 119 - iOS doesn't fetch settings
DELETE /v3/test-prep/add-words             # Line 122 - Server-side automation
DELETE /v3/test-prep/vocabulary-count      # Line 124 - iOS uses /v3/api/test-vocabulary-count instead
DELETE /v3/test-prep/config                # Line 126 - iOS doesn't use this
DELETE /v3/test-prep/batch-populate        # Line 125 - Admin endpoint
DELETE /v3/test-prep/run-daily-job         # Lines 128-137 - Admin endpoint
```

#### Utility V3 - DELETE (1 endpoint)
```python
DELETE /v3/usage                # Line 88 - iOS doesn't use usage dashboard
```

---

### Category C: Static Site Generation - DELETE (3 endpoints)

These are for static site generation, not used by iOS app:

```python
DELETE /words                   # Line 194 - Static site only
DELETE /words/summary           # Line 195 - Static site only
DELETE /words/featured          # Line 196 - Static site only
```

---

### Category D: Admin/Internal Endpoints - KEEP (13 endpoints)

**DO NOT DELETE** - These are for admin operations:

```python
KEEP /v3/admin/videos/batch-upload
KEEP /v3/admin/bundles/<bundle_name>/words-needing-videos
KEEP /v3/admin/questions/batch-generate
KEEP /v3/admin/questions/smart-batch-generate
KEEP /v3/test-review-intervals
KEEP /v3/fix_next_review_dates
KEEP /v3/privacy           # Might be rendered in webview
KEEP /v3/support           # Might be rendered in webview
KEEP /v3/health            # Health check
KEEP /metrics              # Prometheus metrics
KEEP /test-review-intervals
KEEP /fix_next_review_dates
KEEP /api/usage            # Admin analytics
```

---

## Section 3: Endpoint Discrepancies to FIX

### Issue 1: iOS calls `/v3/api/test-prep/stats` but backend defines `/v3/test-prep/stats`

**iOS Code (ScheduleService.swift:132):**
```swift
guard let url = URL(string: "\(baseURL)/v3/api/test-prep/stats?language=\(language)") else {
```

**Backend Code (app_v3.py:123):**
```python
@v3_bp.route('/test-prep/stats', methods=['GET'])
```

**Fix Options:**
1. Add route alias: `@v3_bp.route('/api/test-prep/stats', methods=['GET'])`
2. Or update iOS to remove `/api/` prefix

**Recommendation:** Add backend alias to avoid iOS update.

---

## Section 4: Files That Can Be Deleted

### Backend Handler Files to DELETE

After removing unused endpoints, check if these handler files can be deleted:

```bash
# Check if these handlers are ONLY used by deleted endpoints:
src/handlers/static_site.py          # Used by /words, /words/summary, /words/featured
src/handlers/pronunciation_stats.py  # Used by /pronunciation/stats, /pronunciation/history
src/handlers/analytics_data.py       # Used by /analytics/data
src/handlers/api_usage.py            # Used by /api/usage
```

**Action:** Search each handler file to confirm no other code imports them.

---

## Section 5: Implementation Plan

### Phase 1: Merge Files ✅
```bash
1. Create new app.py with only V3 blueprint
2. Add health check, metrics, privacy/support to V3 namespace
3. Delete old app.py legacy routes
4. Delete app_v3.py (merged into app.py)
```

### Phase 2: Delete Unused Endpoints ✅
```bash
1. Remove 39 unused endpoint route registrations
2. Delete associated handler functions if not shared
3. Delete unused handler files (after verification)
```

### Phase 3: Fix Discrepancies ✅
```bash
1. Add /v3/api/test-prep/stats alias route
```

### Phase 4: Testing ✅
```bash
1. Run integration tests
2. Build iOS app - verify all endpoints compile
3. Test iOS app against new backend
4. Verify no 404 errors in logs
```

---

## Section 6: Detailed Deletion List

### app.py - DELETE These Route Registrations (Line Numbers)

```python
# Lines 144-196 - Legacy endpoints
Line 144: @app.route('/save', methods=['POST'])
Line 145: @app.route('/unsave', methods=['POST'])
Line 146: @app.route('/v2/unsave', methods=['POST'])
Line 147: @app.route('/review_next', methods=['GET'])
Line 148: @app.route('/v2/review_next', methods=['GET'])
Line 149: @app.route('/due_counts', methods=['GET'])
Line 150: @app.route('/reviews/submit', methods=['POST'])
Line 151: @app.route('/word', methods=['GET'])
Line 152: @app.route('/saved_words', methods=['GET'])
Line 153: @app.route('/feedback', methods=['POST'])
Line 159: @app.route('/users/<user_id>/preferences', methods=['GET', 'POST'])
Line 160: @app.route('/languages', methods=['GET'])
Line 166-172: Word details & analytics routes
Line 178-180: Media routes
Line 186-188: Pronunciation routes
Line 194-196: Static site routes
Line 202: @app.route('/api/words/generate', methods=['POST'])
Line 208-215: Test prep routes
Line 221-227: Admin/utility routes (except health, metrics, privacy, support)
```

### app_v3.py - DELETE These Route Registrations

```python
Line 118: @v3_bp.route('/test-prep/settings', methods=['PUT'])
Line 119: @v3_bp.route('/test-prep/settings', methods=['GET'])
Line 122: @v3_bp.route('/test-prep/add-words', methods=['POST'])
Line 124: @v3_bp.route('/test-prep/vocabulary-count', methods=['GET'])
Line 125: @v3_bp.route('/test-prep/batch-populate', methods=['POST'])
Line 126: @v3_bp.route('/test-prep/config', methods=['GET'])
Line 128-137: @v3_bp.route('/test-prep/run-daily-job', methods=['POST'])
Line 88: @v3_bp.route('/usage', methods=['GET'])
```

---

## Section 7: Code Size Reduction

**Before:**
- app.py: ~230 lines of route registrations
- app_v3.py: ~140 lines of route registrations
- Total: ~370 lines

**After:**
- Merged app.py: ~100 lines (73% reduction)
- Deleted: 39 unused routes
- Kept: 29 active routes + 13 admin routes = 42 routes total

**Maintenance Benefits:**
- Single source of truth for API routing
- Easier to find and update endpoints
- Reduced code duplication
- Clearer API surface area

---

## Section 8: Risk Assessment

### Low Risk Deletions (Safe) ✅
- All legacy endpoints - iOS uses V3 exclusively
- Unused V3 test-prep endpoints - iOS doesn't call them
- Static site generation endpoints - Separate deployment
- Pronunciation stats/history - iOS doesn't use

### Medium Risk (Verify First) ⚠️
- Admin endpoints marked for deletion - Confirm no admin scripts use them
- Handler file deletions - Ensure no imports in other code

### Zero Risk (Keep) ✅
- Admin `/v3/admin/*` endpoints
- Health check `/v3/health`
- Metrics `/metrics`
- Privacy/support pages (might be used in webviews)

---

## Conclusion

**Summary:**
1. ✅ **Merge app.py and app_v3.py** - iOS only uses V3
2. ✅ **Delete 39 unused endpoints** - 57% reduction
3. ✅ **Fix 1 endpoint alias** - `/v3/api/test-prep/stats`
4. ✅ **Simplify codebase** - 73% reduction in routing code

**Next Steps:**
1. Review this report
2. Approve deletion plan
3. Create backup branch
4. Execute cleanup
5. Test with iOS app
6. Deploy to production
