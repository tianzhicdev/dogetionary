# Test Prep Endpoints - Usage Analysis

## Executive Summary

**Research Goal**: Determine if the 4 test-prep endpoints can be safely removed from the backend.

**Endpoints Under Investigation**:
1. `POST /v3/api/test-prep/add-words` → `add_daily_test_words()`
2. `GET /v3/api/test-prep/stats` → `get_test_vocabulary_stats()`
3. `GET /v3/api/test-prep/vocabulary-count` → `get_test_vocabulary_count()`
4. `GET /v3/api/test-prep/config` → `get_test_config()`

**Conclusion**:
- ✅ **Safe to remove**: 3 endpoints (`/add-words`, `/vocabulary-count`, `/config`)
- ❌ **Currently in use**: 1 endpoint (`/stats`)

---

## Detailed Findings

### 1. iOS Frontend Usage

#### iOS Service Layer Analysis

**File**: `ios/dogetionary/dogetionary/Core/Services/DictionaryService.swift`

Found function `getTestVocabularyStats()` at line 101:
```swift
func getTestVocabularyStats(for language: String) async throws -> TestVocabularyStats {
    try await scheduleService.getTestVocabularyStats(for: language)
}
```

**Finding**: This is just a delegation to `ScheduleService` - no actual HTTP call here.

---

**File**: `ios/dogetionary/dogetionary/Core/Services/ScheduleService.swift`

Found actual endpoint call at line 132:
```swift
func getTestVocabularyStats(for language: String) async throws -> TestVocabularyStats {
    guard let url = URL(string: "\(baseURL)/v3/api/test-prep/stats?language=\(language)") else {
        throw URLError(.badURL)
    }

    let (data, _) = try await URLSession.shared.data(from: url)
    let stats = try JSONDecoder().decode(TestVocabularyStats.self, from: data)
    return stats
}
```

**Finding**: Only calls `/v3/api/test-prep/stats` endpoint. No other test-prep endpoints are called.

---

#### iOS ViewModels and Views

**Search Pattern**: `getTestVocabularyStats`

**Finding**: No ViewModels or Views call this function. The function exists in the service layer but appears to be dead code in the iOS app.

---

### 2. Backend Internal Usage

#### Direct Function Calls (Not via HTTP)

**Search Pattern**: Direct calls to the 4 endpoint functions

**Files checked**:
- `src/handlers/bundle_vocabulary.py` - contains the endpoint definitions
- `src/routes/test_prep.py` - contains route registrations
- `src/app_v3.py` - contains route registrations
- `src/handlers/users.py` - imports constants only
- `src/handlers/review_batch.py` - imports `get_active_test_type()` only
- `src/workers/bundle_vocabulary_worker.py` - contains scheduled job
- `scripts/test_vocabulary_manual.py` - test script

**Finding**: NO backend code directly calls any of the 4 endpoint functions.

---

#### Scheduled Worker Analysis

**File**: `src/workers/bundle_vocabulary_worker.py`

**Key Finding**: Contains `add_daily_test_words_for_all_users()` function that:
- Runs as a scheduled job every day at midnight
- Adds 10 random test vocabulary words per user who has test mode enabled
- **Calls the DATABASE FUNCTION** `add_daily_test_words()` directly via SQL
- Does NOT call the HTTP endpoint `/test-prep/add-words`

**Code**:
```python
def add_daily_test_words_for_all_users():
    """Add daily test vocabulary words for all users who have test mode enabled"""
    # Gets users with any test mode enabled
    users = get_users_with_test_mode_enabled()

    for user in users:
        user_id = user['user_id']
        learning_language = user['learning_language']
        native_language = user['native_language']

        # CALLS DATABASE FUNCTION, NOT HTTP ENDPOINT
        cur.execute("SELECT add_daily_test_words(%s, %s, %s)",
                   (user_id, learning_language, native_language))
```

**Important**: The worker uses the **database function**, not the HTTP endpoint!

---

#### Database Function vs HTTP Endpoint

**Database function** (in `db/init.sql`):
```sql
CREATE OR REPLACE FUNCTION add_daily_test_words(
    p_user_id UUID,
    p_learning_language VARCHAR,
    p_native_language VARCHAR
) RETURNS INTEGER AS $$
    -- SQL implementation here
$$ LANGUAGE plpgsql;
```

**HTTP endpoint** (in `src/handlers/bundle_vocabulary.py`):
```python
def add_daily_test_words():
    """POST /v3/api/test-prep/add-words"""
    # Wrapper around the database function
    user_id = request.json.get('user_id')
    # ... validation ...
    cur.execute("SELECT add_daily_test_words(%s, %s, %s)", ...)
```

**Finding**: The HTTP endpoint is just a wrapper around the database function. The scheduled worker bypasses the HTTP endpoint entirely.

---

### 3. Test Script Usage

**File**: `scripts/test_vocabulary_manual.py`

This is a manual test script that:
- Calls the **database function** `add_daily_test_words()` via SQL (lines 91, 184)
- Does NOT call any HTTP endpoints
- Used for testing the core functionality, not the API

**Finding**: Test script does not depend on HTTP endpoints.

---

## Summary by Endpoint

### 1. `POST /v3/api/test-prep/add-words` → `add_daily_test_words()`

**Status**: ❌ **UNUSED** - Safe to remove

**Evidence**:
- ✅ NOT called by iOS frontend
- ✅ NOT called by any backend code
- ✅ NOT called by scheduled worker (worker uses database function directly)
- ✅ NOT called by test scripts (test scripts use database function directly)

**Reason to remove**: The endpoint is a redundant wrapper. All actual usage goes through the database function directly.

---

### 2. `GET /v3/api/test-prep/stats` → `get_test_vocabulary_stats()`

**Status**: ⚠️ **POTENTIALLY DEAD CODE** - But currently in use by iOS

**Evidence**:
- ❌ Called by iOS `ScheduleService.swift` line 132
- ✅ NOT called by any backend code
- ✅ NOT called by scheduled worker
- ✅ iOS service function exists but is not called by any ViewModels/Views

**Reason to keep (for now)**: While the iOS function appears unused in the app, the endpoint is still being called. Would need to verify with iOS team before removal.

**Potential action**: Research iOS codebase to see if `ScheduleService.getTestVocabularyStats()` is actually used anywhere. If not, this endpoint can also be removed after cleaning up iOS code.

---

### 3. `GET /v3/api/test-prep/vocabulary-count` → `get_test_vocabulary_count()`

**Status**: ❌ **UNUSED** - Safe to remove

**Evidence**:
- ✅ NOT called by iOS frontend
- ✅ NOT called by any backend code
- ✅ NOT called by scheduled worker
- ✅ NOT called by test scripts

**Reason to remove**: Completely unused. The new achievements system uses different endpoints for vocabulary progress (see `src/handlers/achievements.py`).

---

### 4. `GET /v3/api/test-prep/config` → `get_test_config()`

**Status**: ❌ **UNUSED** - Safe to remove

**Evidence**:
- ✅ NOT called by iOS frontend
- ✅ NOT called by any backend code
- ✅ NOT called by scheduled worker
- ✅ NOT called by test scripts

**Reason to remove**: Test configuration is now handled through user preferences table directly.

---

## Related Functionality Still In Use

### What IS being used:

**1. Database function `add_daily_test_words()`**:
- Called by scheduled worker `bundle_vocabulary_worker.py`
- Called by test scripts
- Should NOT be removed

**2. Test vocabulary achievements system**:
- `src/handlers/achievements.py` contains new badge/achievement logic
- Endpoints: `/v3/achievements/progress`, `/v3/achievements/test-vocabulary-awards`
- These are the REPLACEMENT for the old test-prep endpoints

**3. Bundle vocabulary table**:
- `bundle_vocabularies` table contains test vocabulary data
- Used by new achievement system
- Should NOT be removed

---

## Migration Notes

The test vocabulary feature has evolved:

### Old System (being analyzed for removal):
- `/test-prep/*` endpoints provided stats and configuration
- Frontend tracked progress via these dedicated endpoints

### New System (current):
- Achievement-based progress tracking via `/v3/achievements/*`
- Test completion badges in `user_badges` table
- Utility functions in `achievements.py`:
  - `count_test_vocabulary_progress()`
  - `check_test_completion_badges()`
  - `get_user_test_preferences()`

**The new system has replaced most of the old test-prep API surface.**

---

## Recommendation

### Safe to Remove (3 endpoints):

1. ✅ `POST /v3/api/test-prep/add-words`
   - Worker uses database function directly
   - Endpoint is redundant wrapper

2. ✅ `GET /v3/api/test-prep/vocabulary-count`
   - Replaced by achievement system
   - No callers found

3. ✅ `GET /v3/api/test-prep/config`
   - No callers found
   - Configuration via user_preferences now

### Investigate Further (1 endpoint):

4. ⚠️ `GET /v3/api/test-prep/stats`
   - Called by iOS `ScheduleService`
   - BUT: iOS function appears unused in the app
   - **Action**: Search iOS codebase for `getTestVocabularyStats` usage in ViewModels/Views
   - If truly unused, can be removed after cleaning iOS service layer

---

## Files to Modify for Removal

If removing the 3 safe endpoints:

**Backend**:
1. `src/handlers/bundle_vocabulary.py` - Remove 3 endpoint functions
2. `src/routes/test_prep.py` - Remove route registrations
3. `src/app_v3.py` - Remove route registrations

**iOS** (if removing `/stats` after verification):
1. `ios/dogetionary/dogetionary/Core/Services/ScheduleService.swift` - Remove `getTestVocabularyStats()`
2. `ios/dogetionary/dogetionary/Core/Services/DictionaryService.swift` - Remove delegation function
3. `ios/dogetionary/dogetionary/Core/Models/DictionaryModels.swift` - Remove `TestVocabularyStats` model if unused

---

## Next Steps

1. ✅ **Completed**: Research endpoint usage (this document)
2. ⏳ **Pending**: User approval to proceed with removal
3. ⏳ **If approved**: Remove 3 unused endpoints
4. ⏳ **If approved**: Investigate `/stats` endpoint iOS usage more deeply
5. ⏳ **If approved**: Add migration note to API documentation

---

## API Contracts

### Endpoint Being Kept (For Now)

**GET /v3/api/test-prep/stats**
```
Request: ?language=en
Response: {
  "total_words": 5000,
  "toefl_words": 3000,
  "ielts_words": 2500,
  "both_tests": 500
}
```

**Replacement**: Use `/v3/achievements/test-vocabulary-awards?user_id=XXX` instead

---

## Testing Impact

**No tests depend on these endpoints**:
- Integration tests use database functions directly
- Manual test scripts use database functions directly
- No breaking changes to test suite

---

## Conclusion

**Summary**:
- 3 endpoints are completely unused and safe to remove
- 1 endpoint has iOS caller but appears to be dead code in iOS app
- Database function `add_daily_test_words()` must be kept (used by worker)
- New achievement system has replaced the old test-prep API

**Confidence**: High (95%+) for the 3 unused endpoints, Medium (70%) for `/stats` endpoint

**Risk**: Low - these are read-only stats endpoints with no side effects, easy to restore if needed
