# Schedule Feature Removal - Radical Simplification Plan

## Overview

Remove the entire schedule feature and replace it with simple, on-the-fly calculations in two endpoints:
1. **Practice Status**: Show due count, new words (24h), total words
2. **Review Batch**: Pick 1 random due word, else pick 1 new word from active bundle

## Current Architecture (Complex)

```
Schedule Feature (REMOVE THIS):
├── Backend calculation of daily schedules
├── Database tables storing pre-calculated schedules
├── Complex date-based planning logic
├── iOS UI showing 7-day schedule view
└── Timezone-aware date calculations

Problems:
- Over-engineered for simple use case
- Pre-calculates data that's rarely used
- Adds database complexity
- Confuses users with planning UI
```

## New Architecture (Simple)

```
On-the-Fly Calculations (REPLACE WITH THIS):
├── Practice Status: Count queries only
│   ├── due_word_count (next_review <= NOW)
│   ├── new_word_count_past_24h (created in last 24h)
│   └── total_word_count (all saved words)
└── Review Batch: Random selection
    ├── Pick 1 random due word (next_review <= NOW)
    └── If none, pick 1 new word from active bundle
```

---

## Files to DELETE (9 files)

### Backend (3 files)
1. ✅ `/src/handlers/schedule.py` (877 lines) - ALL schedule API handlers
2. ✅ `/src/services/schedule_service.py` (1048 lines) - ALL schedule calculation logic
3. ✅ `/src/services/scheduler_service.py` (54 lines) - Background scheduler (no longer needed)

### iOS (2 files)
4. ✅ `/ios/dogetionary/dogetionary/Features/Schedule/ScheduleView.swift` - Schedule UI
5. ✅ `/ios/dogetionary/dogetionary/Core/Services/ScheduleService.swift` - Schedule network service

### Tests (3 files)
6. ✅ `/tests/test_calc_schedule.py` - Schedule calculation tests
7. ✅ `/src/tests/test_unit_schedule_service.py` - Schedule unit tests
8. ✅ `/src/tests/test_practice_status_schedule_consistency.py` - Schedule consistency tests

### Documentation (1 file - optional cleanup)
9. ⚠️ Any docs mentioning schedule feature

---

## Files to MODIFY

### Backend Modifications

#### 1. **`/src/app_v3.py`** (3 lines to remove)
**Current (lines 25, 78-80)**:
```python
from handlers.schedule import get_today_schedule, get_schedule_range, get_test_progress

v3_api.route('/schedule/today', methods=['GET'])(get_today_schedule)
v3_api.route('/schedule/range', methods=['GET'])(get_schedule_range)
v3_api.route('/schedule/test-progress', methods=['GET'])(get_test_progress)
```

**New**:
```python
# Remove all 4 lines above
```

---

#### 2. **`/src/handlers/practice_status.py`** (Simplify)

**Current Dependencies**:
```python
from services.schedule_service import get_user_today, get_today_schedule_entry
```

**Remove**:
- Remove `get_today_schedule_entry()` calls (lines 58-59, 68, 91-92)
- Remove timezone/date logic (use server time)

**New Logic**:
```python
def get_practice_status():
    """Return simple practice status with on-the-fly counts"""
    user_id = request.args.get('user_id')

    # Simple queries - no schedule calculation
    due_count = count_due_words(user_id)  # next_review <= NOW()
    new_count_24h = count_words_saved_in_last_24h(user_id)
    total_count = count_total_saved_words(user_id)

    return jsonify({
        "due_word_count": due_count,
        "new_word_count_past_24h": new_count_24h,
        "total_word_count": total_count
    })
```

**SQL Queries Needed** (add to practice_status.py):
```python
def count_due_words(user_id: str) -> int:
    """Count words due for review (next_review <= NOW)"""
    cur.execute("""
        SELECT COUNT(*) FROM saved_words
        WHERE user_id = %s AND next_review <= NOW()
    """, (user_id,))
    return cur.fetchone()[0]

def count_words_saved_in_last_24h(user_id: str) -> int:
    """Count words saved in last 24 hours"""
    cur.execute("""
        SELECT COUNT(*) FROM saved_words
        WHERE user_id = %s
        AND saved_at >= NOW() - INTERVAL '24 hours'
    """, (user_id,))
    return cur.fetchone()[0]

def count_total_saved_words(user_id: str) -> int:
    """Count total saved words"""
    cur.execute("""
        SELECT COUNT(*) FROM saved_words
        WHERE user_id = %s
    """, (user_id,))
    return cur.fetchone()[0]
```

---

#### 3. **`/src/handlers/review_batch.py`** (Simplify)

**Current Dependencies** (lines 16, 138, 148, 156-157):
```python
from services.schedule_service import get_today_schedule_entry
```

**Remove**:
- Remove schedule_entry calculation logic
- Remove scheduled new words logic

**New Logic**:
```python
def get_review_words_batch():
    """
    Return 1 random word for review.
    Priority: 1 due word > 1 new word from active bundle
    """
    user_id = request.args.get('user_id')
    count = int(request.args.get('count', 1))  # Keep param but always return 1

    # Step 1: Try to get 1 random due word
    due_word = get_random_due_word(user_id)

    if due_word:
        # Generate question for due word
        word_data = prepare_word_for_review(due_word)
        return jsonify({"words": [word_data]})

    # Step 2: No due words - get 1 new word from active bundle
    new_word = get_random_new_word_from_bundle(user_id)

    if new_word:
        word_data = prepare_word_for_review(new_word)
        return jsonify({"words": [word_data]})

    # No words available
    return jsonify({"words": []})
```

**SQL Queries Needed** (add to review_batch.py):
```python
def get_random_due_word(user_id: str) -> Optional[Dict]:
    """Get 1 random word that's due for review"""
    cur.execute("""
        SELECT word, learning_language, native_language
        FROM saved_words
        WHERE user_id = %s
        AND next_review <= NOW()
        AND exclude_from_practice = FALSE
        ORDER BY RANDOM()
        LIMIT 1
    """, (user_id,))
    row = cur.fetchone()
    return dict(row) if row else None

def get_random_new_word_from_bundle(user_id: str) -> Optional[Dict]:
    """Get 1 random new word from active test bundle"""
    # Get user's active test type
    test_type = get_active_test_type(user_id)
    if not test_type:
        return None

    cur.execute("""
        SELECT bv.word, up.learning_language, up.native_language
        FROM bundle_vocabularies bv
        CROSS JOIN user_preferences up
        WHERE up.user_id = %s
        AND bv.bundle_name = %s
        AND bv.language = up.learning_language
        AND NOT EXISTS (
            SELECT 1 FROM saved_words sw
            WHERE sw.user_id = up.user_id
            AND sw.word = bv.word
            AND sw.learning_language = bv.language
        )
        ORDER BY RANDOM()
        LIMIT 1
    """, (user_id, test_type))
    row = cur.fetchone()
    return dict(row) if row else None
```

---

### iOS Modifications

#### 4. **`/ios/dogetionary/dogetionary/App/ContentView.swift`**

**Remove**:
- Line 45: ScheduleView() tab
- Line 70: `.navTabSaved` case mapping
- Entire schedule tab from navigation

**New**:
```swift
// Remove schedule tab entirely
// Keep only: Search, Saved Words, Practice, Settings
```

---

#### 5. **`/ios/dogetionary/dogetionary/Core/Services/DictionaryService.swift`**

**Remove** (lines 89-101):
```swift
func getTodaySchedule(completion: @escaping (Result<...>) -> Void)
func getScheduleRange(days: Int, onlyNewWords: Bool, completion: ...)
func getTestProgress(completion: @escaping (Result<...>) -> Void)
func getTestVocabularyStats(language: String, completion: ...)
```

**New**:
```swift
// All removed - no replacement needed
// Practice status already has due_word_count
```

---

#### 6. **`/ios/dogetionary/dogetionary/Core/Models/DictionaryModels.swift`**

**Remove**:
```swift
struct DailyScheduleEntry { ... }
struct GetScheduleRangeResponse { ... }
// Any other schedule-related models
```

---

#### 7. **`/ios/dogetionary/dogetionary/Features/Settings/OnboardingView.swift`**

**Remove** (lines 428-429):
```swift
// Remove embedded ScheduleView from onboarding
```

**New**:
```swift
// Just show test type selection, no schedule preview
```

---

### Database Modifications

#### 8. **Create Migration**: `/db/migration_011_remove_schedule.sql`

```sql
-- Migration 011: Remove schedule feature tables
-- Part of radical simplification - schedule is now on-the-fly

-- Drop tables
DROP TABLE IF EXISTS daily_schedule_entries CASCADE;
DROP TABLE IF EXISTS study_schedules CASCADE;

-- Remove schedule-related indexes (if any remain)
DROP INDEX IF EXISTS idx_study_schedules_user;
DROP INDEX IF EXISTS idx_study_schedules_end_date;
DROP INDEX IF EXISTS idx_daily_entries_schedule;
DROP INDEX IF EXISTS idx_daily_entries_date;

-- Note: Keep target_end_date in user_preferences for now
-- It may still be useful for test prep duration tracking
```

---

## Implementation Steps

### Phase 1: Backend Simplification
1. ✅ Create migration SQL to drop schedule tables
2. ✅ Simplify `practice_status.py` with count queries
3. ✅ Simplify `review_batch.py` with random selection
4. ✅ Remove schedule routes from `app_v3.py`
5. ✅ Delete schedule handler and service files
6. ✅ Run migration on local DB
7. ✅ Test practice_status endpoint
8. ✅ Test review_batch endpoint

### Phase 2: iOS Simplification
1. ✅ Remove ScheduleView tab from ContentView
2. ✅ Delete ScheduleView.swift
3. ✅ Delete ScheduleService.swift
4. ✅ Remove schedule methods from DictionaryService
5. ✅ Remove schedule models from DictionaryModels
6. ✅ Remove schedule from OnboardingView
7. ✅ Test app compilation
8. ✅ Test practice flow without schedule

### Phase 3: Cleanup
1. ✅ Delete test files
2. ✅ Remove schedule from integration tests
3. ✅ Update documentation
4. ✅ Deploy to production

---

## Expected Benefits

### Code Reduction
- **Backend**: Remove ~2000 lines of code (schedule.py + schedule_service.py + scheduler_service.py)
- **iOS**: Remove ~500 lines of code (ScheduleView + ScheduleService)
- **Database**: Remove 2 tables (study_schedules, daily_schedule_entries)
- **Tests**: Remove 3 test files

### Complexity Reduction
- ❌ **Remove**: Pre-calculation of schedules
- ❌ **Remove**: Complex date math and timezone handling
- ❌ **Remove**: Background workers for schedule refresh
- ❌ **Remove**: Schedule-specific database queries
- ✅ **Keep**: Simple COUNT queries
- ✅ **Keep**: Simple RANDOM selection

### Performance Improvement
- Faster API responses (no schedule calculation)
- Less database storage
- Fewer queries overall
- No background processing overhead

### User Experience
- Simpler mental model: "review due words, add new words"
- No confusing schedule planning UI
- Immediate feedback (counts update in real-time)
- Less cognitive load

---

## Risk Assessment

### Low Risk
- ✅ Schedule is informational only (not critical to core practice flow)
- ✅ Due word selection already uses `next_review` field (unchanged)
- ✅ Practice flow works without schedule
- ✅ Easy rollback (keep migration script)

### Migration Safety
- Keep `target_end_date` in `user_preferences` (may be useful later)
- Keep `next_review` in `saved_words` (critical for SRS)
- Drop only `study_schedules` and `daily_schedule_entries` tables

---

## Testing Checklist

### Backend Tests
- [ ] Practice status returns correct counts
- [ ] Review batch picks due words when available
- [ ] Review batch picks new words when no due words
- [ ] Review batch returns empty when no words available
- [ ] Counts update correctly after saving/reviewing words

### iOS Tests
- [ ] App compiles without schedule tab
- [ ] Navigation works with 4 tabs (no schedule)
- [ ] Onboarding works without schedule view
- [ ] Practice flow works normally
- [ ] Settings page doesn't reference schedule

### Integration Tests
- [ ] End-to-end practice flow works
- [ ] Word saving updates counts correctly
- [ ] Word reviewing updates due count correctly

---

## Rollback Plan

If issues arise:
1. Revert backend code changes
2. Run reverse migration (re-create tables)
3. Re-add schedule routes
4. Revert iOS changes
5. Deploy previous version

---

## Summary

**Remove**: 2500+ lines of complex scheduling code
**Replace with**: ~100 lines of simple count/random queries
**Result**: Same user experience, 95% less code, much simpler architecture

This is a **radical simplification** that aligns with the actual user need: "show me what to practice next."
