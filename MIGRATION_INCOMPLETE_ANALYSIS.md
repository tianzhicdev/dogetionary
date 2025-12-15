# Migration Incomplete - Comprehensive Analysis

## Executive Summary

The TIANZ→DEMO migration is **incomplete** and has **12 CRITICAL issues** causing the backend to crash and **13 HIGH priority issues** causing user-visible bugs in the iOS app.

**Backend Status:** 🔴 **BROKEN** - ModuleNotFoundError on startup
**iOS App Status:** 🟡 **WORKS BUT BUGGY** - Still shows "Tianz Test" throughout UI

---

## Why Backend is Broken

The backend cannot start because 8 files are importing from renamed modules:
- `handlers.test_vocabulary` → renamed to `handlers.bundle_vocabulary` ✅
- `workers.test_vocabulary_worker` → renamed to `workers.bundle_vocabulary_worker` ✅

But these 8 files were NOT updated:
1. `src/handlers/schedule.py` (3 imports)
2. `src/handlers/users.py` (1 import)
3. `src/handlers/practice_status.py` (1 import)
4. `src/handlers/review_batch.py` (1 import)
5. `src/routes/test_prep.py` (2 imports)
6. `src/app_v3.py` (2 imports)
7. `src/handlers/bundle_vocabulary.py` (1 import)

**Error Message:**
```
ModuleNotFoundError: No module named 'handlers.test_vocabulary'
```

---

## Why iOS Shows "Tianz Test"

The iOS app displays incorrect text in **7 locations**:

### User-Visible Text Issues:
1. **DictionaryModels.swift:637** - TestType display name returns `"Tianz Test"`
2. **ScheduleView.swift:468** - TestType display name returns `"Tianz Test"`
3. **ScheduleView.swift:298** - Button text shows `"TIANZ TEST"`
4. **TestProgressBar.swift:30** - Dictionary literal has `"Tianz"` instead of `"Demo"`

### UserDefaults Keys (Legacy compatibility issue):
5. **UserManager.swift:27** - `demoEnabledKey = "DogetionaryTianzEnabled"` (should be `"DogetionaryDemoEnabled"`)
6. **UserManager.swift:30** - `demoTargetDaysKey = "DogetionaryTianzTargetDays"` (should be `"DogetionaryDemoTargetDays"`)

### Variable Names:
7. **DebugConfig.swift:66** - Variable named `showTianzTest` (should be `showDemoTest`)
8. **UserManager.swift:281** - Variable named `savedTianzTargetDays` (should be `savedDemoTargetDays`)

---

## Complete Issue Breakdown

### CRITICAL - Backend Crashes (12 issues)
**Impact:** App won't start

| File | Line | Issue | Fix |
|------|------|-------|-----|
| `src/handlers/schedule.py` | 24 | `from handlers.test_vocabulary import TEST_TYPE_MAPPING` | Change to `bundle_vocabulary` |
| `src/handlers/schedule.py` | 144 | `from handlers.test_vocabulary import get_active_test_type` | Change to `bundle_vocabulary` |
| `src/handlers/schedule.py` | 437 | `from handlers.test_vocabulary import get_active_test_type` | Change to `bundle_vocabulary` |
| `src/handlers/users.py` | 29 | `from handlers.test_vocabulary import TEST_TYPE_MAPPING, ALL_TEST_ENABLE_COLUMNS` | Change to `bundle_vocabulary` |
| `src/handlers/practice_status.py` | 109 | `from handlers.test_vocabulary import get_active_test_type` | Change to `bundle_vocabulary` |
| `src/handlers/review_batch.py` | 177 | `from handlers.test_vocabulary import get_active_test_type` | Change to `bundle_vocabulary` |
| `src/routes/test_prep.py` | 2-6 | Multiple imports from `handlers.test_vocabulary` | Change to `bundle_vocabulary` |
| `src/routes/test_prep.py` | 7 | `from workers.test_vocabulary_worker import ...` | Change to `bundle_vocabulary_worker` |
| `src/app_v3.py` | 19-23 | Multiple imports from `handlers.test_vocabulary` | Change to `bundle_vocabulary` |
| `src/app_v3.py` | 24 | `from workers.test_vocabulary_worker import ...` | Change to `bundle_vocabulary_worker` |
| `src/handlers/bundle_vocabulary.py` | 642 | `from workers.test_vocabulary_worker import ...` | Change to `bundle_vocabulary_worker` |

### HIGH - User-Visible Bugs (13 issues)
**Impact:** Users see "Tianz Test" instead of "Demo Bundle"

**Backend Display Strings:**
| File | Line | Current | Should Be |
|------|------|---------|-----------|
| `src/routes/test_prep.py` | 44 | `"name": "Tianz Test"` | `"name": "Demo Bundle"` |
| `src/handlers/bundle_vocabulary.py` | 664 | `"name": "Tianz Test"` | `"name": "Demo Bundle"` |
| `src/handlers/bundle_vocabulary.py` | 695 | `"name": "Tianz Test"` | `"name": "Demo Bundle"` |
| `src/app_v3.py` | 150 | `"name": "Tianz Test"` | `"name": "Demo Bundle"` |

**iOS Display Strings:**
| File | Line | Current | Should Be |
|------|------|---------|-----------|
| `ios/.../DictionaryModels.swift` | 637 | `return "Tianz Test"` | `return "Demo Bundle"` |
| `ios/.../ScheduleView.swift` | 468 | `return "Tianz Test"` | `return "Demo Bundle"` |
| `ios/.../ScheduleView.swift` | 298 | `Text("TIANZ TEST")` | `Text("DEMO BUNDLE")` |
| `ios/.../TestProgressBar.swift` | 30 | `"DEMO": ("Tianz", ...)` | `"DEMO": ("Demo", ...)` |

**iOS Variable Names:**
| File | Line | Current | Should Be |
|------|------|---------|-----------|
| `ios/.../DebugConfig.swift` | 66-68 | `showTianzTest` | `showDemoTest` |
| `ios/.../UserManager.swift` | 27 | `"DogetionaryTianzEnabled"` | `"DogetionaryDemoEnabled"` |
| `ios/.../UserManager.swift` | 30 | `"DogetionaryTianzTargetDays"` | `"DogetionaryDemoTargetDays"` |
| `ios/.../UserManager.swift` | 281 | `savedTianzTargetDays` | `savedDemoTargetDays` |

### MEDIUM - Internal Consistency (5 issues)
**Impact:** API responses inconsistent

| File | Line | Issue | Fix |
|------|------|-------|-----|
| `src/handlers/bundle_vocabulary.py` | 382-386 | JSON key `"tianz":` | Change to `"demo":` |
| `src/handlers/bundle_vocabulary.py` | 527-531 | JSON key `"tianz":` | Change to `"demo":` |
| `src/handlers/admin_questions.py` | 207 | Mapping key `'tianz':` | Change to `'demo':` |
| `src/handlers/admin_questions_smart.py` | 264 | Mapping key `'tianz':` | Change to `'demo':` |
| `src/handlers/admin_questions_smart.py` | 406 | Mapping key `'tianz':` | Change to `'demo':` |

### LOW - Documentation (19 issues)
**Impact:** Developer confusion, no functional impact

Comments, docstrings, and preview names still reference "TIANZ" or "tianz" in:
- Bundle vocabulary handler docstrings
- App v3 comments
- iOS model documentation comments
- Script variable names (`tianz_file`, `tianz_count`)
- Preview names in Xcode
- CLI argument choices

---

## Recommended Fix Strategy

### Option 1: Quick Fix (15 minutes)
**Goal:** Get backend working and hide worst user-facing bugs

1. Fix all 12 CRITICAL import statements (search & replace)
2. Fix 4 HIGH priority backend display strings
3. Fix 4 HIGH priority iOS display strings

**Result:** Backend runs ✅, iOS app mostly correct ✅

### Option 2: Complete Fix (30 minutes)
**Goal:** Finish the migration properly

1. Fix all CRITICAL issues (imports)
2. Fix all HIGH issues (display strings + variables)
3. Fix all MEDIUM issues (JSON keys + mappings)
4. Fix all LOW issues (comments + docs)

**Result:** Migration 100% complete ✅

---

## Why Search & Replace Wasn't Enough

The initial migration used global search & replace like:
```bash
find . -name "*.py" -exec sed -i '' 's/test_vocabulary/bundle_vocabulary/g' {} +
```

**Problem:** This only replaced literal strings, NOT import statements.

**Example:**
- ✅ Replaced: `from handlers.test_vocabulary import ...`
- ✅ Renamed: `test_vocabulary.py` → `bundle_vocabulary.py`
- ❌ Forgot to update: Files that import the module!

**What happened:**
1. Module was renamed: `handlers/test_vocabulary.py` → `handlers/bundle_vocabulary.py`
2. Import paths were partially updated in some files (app.py) but NOT in others
3. Search & replace worked for strings inside files, but dynamic imports inside functions weren't caught

---

## Files Needing Updates

### Backend Files (8 files):
```
src/handlers/schedule.py
src/handlers/users.py
src/handlers/practice_status.py
src/handlers/review_batch.py
src/routes/test_prep.py
src/app_v3.py
src/handlers/bundle_vocabulary.py
src/handlers/admin_questions.py
src/handlers/admin_questions_smart.py
```

### iOS Files (5 files):
```
ios/dogetionary/dogetionary/Core/Models/DictionaryModels.swift
ios/dogetionary/dogetionary/Core/Managers/UserManager.swift
ios/dogetionary/dogetionary/Core/Services/DebugConfig.swift
ios/dogetionary/dogetionary/Features/Schedule/ScheduleView.swift
ios/dogetionary/dogetionary/Shared/Components/TestProgressBar.swift
```

---

## Next Steps

1. **Decide on fix strategy** (Quick vs Complete)
2. **Apply fixes in order** (CRITICAL → HIGH → MEDIUM → LOW)
3. **Test after each phase**
4. **Update git commit** with comprehensive fixes

**Total Estimated Time:**
- Quick Fix: 15 minutes
- Complete Fix: 30 minutes
- Testing: 10 minutes each

**Current Status:**
- Migration: 60% complete
- Backend: 🔴 Broken
- iOS: 🟡 Works but shows wrong text
- Database: ✅ Fully migrated
