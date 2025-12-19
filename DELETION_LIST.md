# Deletion List - Legacy Endpoints & Unused Functions

## Summary
- **Legacy route registrations to delete: 33**
- **Unused handler functions to verify: 10+**
- **Potentially unused handler files: 3**

---

## Part 1: Legacy Route Registrations to DELETE from app.py

These are ALL in the `register_legacy_routes()` function (lines 97-229).

### Core Endpoints - DELETE 10 routes (Lines 144-153)
```python
# File: src/app.py
# Function: register_legacy_routes()

DELETE Line 144: app.route('/save', methods=['POST'])(save_word)
DELETE Line 145: app.route('/unsave', methods=['POST'])(delete_saved_word)
DELETE Line 146: app.route('/v2/unsave', methods=['POST'])(delete_saved_word_v2)
DELETE Line 147: app.route('/review_next', methods=['GET'])(get_next_review_word)
DELETE Line 148: app.route('/v2/review_next', methods=['GET'])(get_next_review_word_v2)
DELETE Line 149: app.route('/due_counts', methods=['GET'])(get_due_counts)
DELETE Line 150: app.route('/reviews/submit', methods=['POST'])(submit_review)
DELETE Line 151: app.route('/word', methods=['GET'])(get_word_definition_v4)
DELETE Line 152: app.route('/saved_words', methods=['GET'])(get_saved_words)
DELETE Line 153: app.route('/feedback', methods=['POST'])(submit_feedback)
```

**Reason:** iOS uses V3 equivalents:
- `/v3/save`, `/v3/unsave`, `/v3/word`, `/v3/saved_words`, `/v3/feedback`
- iOS uses `/v3/next-review-words-batch` instead of `/review_next`

---

### User Management - DELETE 2 routes (Lines 159-160)
```python
DELETE Line 159: app.route('/users/<user_id>/preferences', methods=['GET', 'POST'])(handle_user_preferences)
DELETE Line 160: app.route('/languages', methods=['GET'])(get_supported_languages)
```

**Reason:**
- iOS uses `/v3/users/<user_id>/preferences`
- iOS doesn't use `/languages` endpoint

---

### Analytics & Statistics - DELETE 7 routes (Lines 166-172)
```python
DELETE Line 166: app.route('/words/<int:word_id>/forgetting-curve', methods=['GET'])(get_forgetting_curve)
DELETE Line 167: app.route('/words/<int:word_id>/details', methods=['GET'])(get_word_details)
DELETE Line 168: app.route('/leaderboard', methods=['GET'])(get_leaderboard)
DELETE Line 169: app.route('/reviews/stats', methods=['GET'])(get_review_stats)
DELETE Line 170: app.route('/reviews/progress_stats', methods=['GET'])(get_review_progress_stats)
DELETE Line 171: app.route('/analytics/track', methods=['POST'])(track_user_action)
DELETE Line 172: app.route('/analytics/data', methods=['GET'])(get_analytics_data)
```

**Reason:**
- iOS uses V3 equivalents: `/v3/words/<id>/forgetting-curve`, `/v3/words/<id>/details`
- iOS uses `/v3/leaderboard-score` instead of `/leaderboard`
- iOS uses `/v3/analytics/track` instead of `/analytics/track`
- iOS doesn't use `/reviews/stats` or `/analytics/data`

---

### Media Endpoints - DELETE 3 routes (Lines 178-180)
```python
DELETE Line 178: app.route('/audio/<path:text>/<language>')(get_audio)
DELETE Line 179: app.route('/get-illustration', methods=['GET', 'POST'])(get_illustration)
DELETE Line 180: app.route('/generate-illustration', methods=['POST'])(get_illustration)
```

**Reason:** iOS uses V3 equivalents:
- `/v3/audio/<text>/<language>`
- `/v3/illustration`

---

### Pronunciation - DELETE 3 routes (Lines 186-188)
```python
DELETE Line 186: app.route('/pronunciation/practice', methods=['POST'])(practice_pronunciation)
DELETE Line 187: app.route('/pronunciation/stats', methods=['GET'])(get_pronunciation_stats)
DELETE Line 188: app.route('/pronunciation/history', methods=['GET'])(get_pronunciation_history)
```

**Reason:**
- iOS uses `/v3/pronunciation/practice` and `/v3/review/pronounce`
- iOS doesn't use pronunciation stats or history

---

### Static Site Generation - DELETE 3 routes (Lines 194-196)
```python
DELETE Line 194: app.route('/words', methods=['GET'])(get_all_words)
DELETE Line 195: app.route('/words/summary', methods=['GET'])(get_words_summary)
DELETE Line 196: app.route('/words/featured', methods=['GET'])(get_featured_words)
```

**Reason:** These are for static site generation, not used by iOS app

---

### Bulk Data Management - DELETE 1 route (Line 202)
```python
DELETE Line 202: app.route('/api/words/generate', methods=['POST'])(generate_word_definition)
```

**Reason:** iOS doesn't use this endpoint

---

### Test Prep Endpoints - DELETE 8 routes (Lines 208-215)
```python
DELETE Line 208: app.route('/api/test-prep/settings', methods=['PUT'])(update_test_settings)
DELETE Line 209: app.route('/api/test-prep/settings', methods=['GET'])(get_test_settings)
DELETE Line 210: app.route('/api/test-prep/add-words', methods=['POST'])(add_daily_test_words)
DELETE Line 211: app.route('/api/test-prep/stats', methods=['GET'])(get_test_vocabulary_stats)
DELETE Line 212: app.route('/api/v3/test-vocabulary-count', methods=['GET'])(get_test_vocabulary_count)
DELETE Line 213: app.route('/api/test-prep/config', methods=['GET'])(get_test_config)
DELETE Line 214: app.route('/api/test-prep/batch-populate', methods=['POST'])(batch_populate_test_vocabulary)
DELETE Line 215: app.route('/api/test-prep/run-daily-job', methods=['POST'])(manual_daily_job)
```

**Reason:**
- iOS uses `/v3/schedule/test-progress` instead
- iOS uses `/v3/api/test-prep/stats` (note: different from backend's `/v3/test-prep/stats`)
- Other endpoints are admin/internal only

---

### Admin Endpoints - DELETE 7 routes, KEEP 5 (Lines 221-227)

**DELETE:**
```python
DELETE Line 221: app.route('/test-review-intervals', methods=['GET'])(test_review_intervals)
DELETE Line 222: app.route('/fix_next_review_dates', methods=['POST'])(fix_next_review_dates)
DELETE Line 226: app.route('/usage', methods=['GET'])(get_usage_dashboard)
DELETE Line 227: app.route('/api/usage', methods=['GET'])(get_api_usage_analytics)
```

**KEEP (might be used in admin tools/scripts):**
```python
KEEP Line 223: app.route('/privacy', methods=['GET'])(privacy_agreement)    # Might be rendered in webview
KEEP Line 224: app.route('/support', methods=['GET'])(support_page)          # Might be rendered in webview
KEEP Line 225: app.route('/health', methods=['GET'])(health_check)           # Health monitoring
```

**Reason:** iOS has V3 equivalents for routes we're deleting, keep only essentials

---

## Part 2: Unused Handler FUNCTIONS to Verify

These functions are imported in app.py but might only be used by legacy routes we're deleting.

### From handlers/actions.py
```python
VERIFY: delete_saved_word         # Only used by legacy /unsave
VERIFY: get_next_review_word      # Only used by legacy /review_next
```

### From handlers/users.py
```python
VERIFY: get_supported_languages   # Only used by legacy /languages
```

### From handlers/reads.py
```python
VERIFY: get_review_stats          # Only used by legacy /reviews/stats
VERIFY: get_leaderboard           # Only used by legacy /leaderboard (iOS uses get_leaderboard_v2)
```

### From handlers/analytics.py
```python
VERIFY: get_analytics_data        # Only used by legacy /analytics/data
```

### From handlers/api_usage_analytics.py
```python
VERIFY: get_api_usage_analytics   # Only used by legacy /api/usage
```

### From handlers/pronunciation.py
```python
VERIFY: get_pronunciation_history # Only used by legacy /pronunciation/history
VERIFY: get_pronunciation_stats   # Only used by legacy /pronunciation/stats
```

### From handlers/words.py
```python
VERIFY: get_next_review_word_v2   # Only used by legacy /v2/review_next
VERIFY: generate_word_definition  # Only used by legacy /api/words/generate
```

### From handlers/static_site.py
```python
VERIFY: get_all_words             # Only used by legacy /words
VERIFY: get_words_summary         # Only used by legacy /words/summary
VERIFY: get_featured_words        # Only used by legacy /words/featured
```

---

## Part 3: Handler FILES to Potentially DELETE

After verifying functions above, these entire files might be deletable:

### Highly Likely Deletable
```bash
src/handlers/static_site.py          # Only used by /words, /words/summary, /words/featured
src/handlers/api_usage_analytics.py  # Only used by /api/usage
```

### Verify Before Deleting
```bash
src/handlers/compatibility.py        # Check if anything imports this
```

**Action Required:**
1. Search codebase for imports of these files
2. Check if any background workers use them
3. Verify no other scripts reference them

---

## Part 4: Import Cleanup in app.py

After deleting routes, clean up these imports from `register_legacy_routes()`:

### DELETE These Imports (Lines 110-138)
```python
# DELETE from handlers.actions import:
DELETE: delete_saved_word             # If verified unused
DELETE: get_next_review_word          # If verified unused

# DELETE from handlers.users import:
DELETE: get_supported_languages       # If verified unused

# DELETE from handlers.reads import:
DELETE: get_review_stats              # If verified unused
DELETE: get_leaderboard               # If verified unused

# DELETE from handlers.admin import:
DELETE: test_review_intervals         # After deleting route
DELETE: fix_next_review_dates         # After deleting route

# DELETE from handlers.usage_dashboard import:
DELETE: get_usage_dashboard           # After deleting route

# DELETE from handlers.analytics import:
DELETE: get_analytics_data            # If verified unused

# DELETE from handlers.api_usage_analytics import:
DELETE: get_api_usage_analytics       # If verified unused

# DELETE from handlers.pronunciation import:
DELETE: get_pronunciation_history     # If verified unused
DELETE: get_pronunciation_stats       # If verified unused

# DELETE from handlers.words import:
DELETE: get_next_review_word_v2       # If verified unused
DELETE: generate_word_definition      # If verified unused

# DELETE entire import:
DELETE: from handlers.static_site import get_all_words, get_words_summary, get_featured_words

# DELETE entire import:
DELETE: from handlers.bundle_vocabulary import (
    update_test_settings, get_test_settings, add_daily_test_words,
    get_test_vocabulary_stats, get_test_vocabulary_count,
    manual_daily_job, get_test_config, batch_populate_test_vocabulary
)
```

---

## Part 5: Final Simplified register_legacy_routes()

After all deletions, this function should be EMPTY or just contain admin routes:

```python
def register_legacy_routes(app):
    """
    Register legacy routes for backward compatibility.

    DEPRECATED: iOS app now uses V3 API exclusively.
    This function kept for potential admin tool compatibility.
    """
    app.logger.info("No legacy routes - iOS uses V3 API exclusively")

    # Keep only essential admin endpoints if needed
    # from handlers.admin import privacy_agreement, support_page, health_check
    # app.route('/privacy', methods=['GET'])(privacy_agreement)
    # app.route('/support', methods=['GET'])(support_page)
    # app.route('/health', methods=['GET'])(health_check)
```

Or even better - **DELETE the entire function** and move health/privacy to V3 namespace.

---

## Execution Checklist

### Phase 1: Verification
- [ ] Search codebase for each function in Part 2 to verify it's only used by legacy routes
- [ ] Search for imports of handler files in Part 3
- [ ] Check background workers for usage of these functions
- [ ] Check if any admin scripts use these endpoints

### Phase 2: Deletion
- [ ] Delete 33 legacy route registrations from app.py (Lines 144-227, selective)
- [ ] Delete unused function imports (Lines 110-138, selective)
- [ ] Optionally delete entire `register_legacy_routes()` function
- [ ] Delete verified unused handler functions
- [ ] Delete verified unused handler files

### Phase 3: Testing
- [ ] Run backend with changes
- [ ] Check for import errors
- [ ] Run integration tests
- [ ] Verify iOS app still works
- [ ] Check logs for any 404 errors

---

## Expected Code Reduction

**Before:**
- app.py: ~250 lines
- register_legacy_routes(): ~130 lines
- Handler functions: ~100+ unused functions

**After:**
- app.py: ~120 lines (52% reduction)
- register_legacy_routes(): DELETED or ~10 lines
- Handler functions: Cleaned up

**Total Reduction:**
- ~130 lines of route registration code
- ~10-15 unused handler functions
- 2-3 unused handler files
- Simpler codebase with single API version (V3)
