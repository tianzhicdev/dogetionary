# VideoFinder Refactoring: Quick Reference Guide

## TL;DR - The Recommendation

**Move VideoFinder from `scripts/find_videos.py` to `src/services/video_finder.py`**

- **Location:** Single file service (Option A)
- **Risk Level:** LOW
- **Backward Compatible:** YES
- **Dependencies Added:** NONE
- **Implementation Time:** 2-3 hours
- **Lines Changed:** 3 files, ~150 lines total change

---

## Decision Matrix

### Option A: Single File Service (RECOMMENDED)
```
pros:
  ✓ Simplest (CLAUDE.md principle)
  ✓ Matches existing service pattern
  ✓ No package hierarchy
  ✓ Easy to import from handlers
  
cons:
  - Single large file (1,035 lines)
  - Might split later if it grows significantly
```

### Option B: Package-Based Service
```
pros:
  ✓ Better organization if it grows
  ✓ Separates concerns (llm, audio, upload)
  
cons:
  - More complex now
  - Added package overhead
  - Violates CLAUDE.md "simple" principle
```

**CHOSEN: Option A** (recommended for now)

---

## Quick Action Items

### Before Starting
- [ ] Read full plan: `VIDEO_FINDER_REFACTORING_PLAN.md`
- [ ] Review current imports in video_search.py
- [ ] Backup repo (git already does this)

### Phase 1: Create Service (30 min)
```bash
# Create new file with VideoFinder class
cp scripts/find_videos.py src/services/video_finder.py
# Edit: Remove CLI code, logging.basicConfig()
# Keep: VideoFinder class, LLM_FALLBACK_CHAIN
```

**Test:**
```bash
python3 -c "from src.services.video_finder import VideoFinder; print('OK')"
```

### Phase 2: Update Handler (15 min)
```python
# In /src/handlers/video_search.py
# REMOVE: lines 16-17 (sys.path.insert hack)
# CHANGE: from find_videos import VideoFinder
# TO:     from services.video_finder import VideoFinder
# REMOVE: local import in run_video_finder_for_word()
```

**Test:**
```bash
python3 src/app.py  # Check Flask starts without errors
```

### Phase 3: Simplify CLI (30 min)
```python
# In /scripts/find_videos.py
# ADD:    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))
# ADD:    from services.video_finder import VideoFinder
# DELETE: VideoFinder class (1000+ lines)
# KEEP:   main(), argparse, environment setup
```

**Test:**
```bash
python3 scripts/find_videos.py --help
```

---

## Import Patterns (After Refactoring)

### From Backend Code
```python
from services.video_finder import VideoFinder
```

### From CLI Scripts
```python
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))
from services.video_finder import VideoFinder
```

---

## File Changes Summary

| File | Type | Change | Lines |
|------|------|--------|-------|
| `/src/services/video_finder.py` | NEW | Create service | +1,035 |
| `/src/handlers/video_search.py` | MODIFY | Update import | -3, +1 |
| `/scripts/find_videos.py` | REFACTOR | CLI wrapper | -1,083 |
| **TOTAL** | | | -51 lines (net) |

---

## Dependency Check

**All required packages already available:**
- ✓ requests
- ✓ openai  
- ✓ python-dotenv
- ✓ Standard library (os, json, csv, logging, etc.)

**New packages needed:** NONE

---

## Risk Checklist

| Risk | Probability | Severity | Mitigation |
|------|-------------|----------|-----------|
| Import path breaks | Low | Medium | Use `os.path.dirname(__file__)` |
| Circular imports | Very Low | High | Service only imports utils/config |
| Handler fails to load | Low | Medium | Test step 2 before step 3 |
| CLI path issue | Low | Medium | Test from different directories |
| Logging config lost | Low | Low | Follow existing service pattern |

**Overall Risk:** LOW ✓

---

## Testing Checklist

### Phase 1 (Service Creation)
- [ ] Import works: `from src.services.video_finder import VideoFinder`
- [ ] Constant works: `from src.services.video_finder import LLM_FALLBACK_CHAIN`
- [ ] Class has 20+ methods
- [ ] No syntax errors

### Phase 2 (Handler Update)
- [ ] Flask backend starts: `python3 src/app.py`
- [ ] No import errors in logs
- [ ] Handler can load: `from src.handlers.video_search import trigger_video_search`

### Phase 3 (CLI Refactor)
- [ ] Help works: `python3 scripts/find_videos.py --help`
- [ ] CSV mode works: `python3 scripts/find_videos.py --csv test.csv`
- [ ] Bundle mode works: `python3 scripts/find_videos.py --bundle test`

### Integration
- [ ] Backend video search endpoint works
- [ ] Background thread video search works
- [ ] Database records created correctly

---

## Success Criteria (13 Items)

1. ✓ Service file exists: `/src/services/video_finder.py`
2. ✓ VideoFinder class importable
3. ✓ LLM_FALLBACK_CHAIN constant importable
4. ✓ Handler imports from service (no sys.path hack)
5. ✓ Flask backend starts without errors
6. ✓ `--help` works
7. ✓ `--csv` mode works
8. ✓ `--bundle` mode works
9. ✓ Background thread video search works
10. ✓ No circular imports
11. ✓ All tests pass
12. ✓ Code review approval
13. ✓ No revert needed

---

## Configuration (No Changes Required)

**Constructor Parameters:**
```python
VideoFinder(
    storage_dir='/path',           # Configurable
    backend_url='http://...',      # Configurable
    word_list_path='words.csv',    # Optional
    clipcafe_api_key='...',        # From env
    openai_api_key='...',          # From env
    max_videos_per_word=100,       # Default: 100
    education_min_score=0.6,       # Default: 0.6
    context_min_score=0.6,         # Default: 0.6
    download_only=False            # Default: False
)
```

**Environment Variables:** No changes needed
- `CLIPCAFE` (already used)
- `OPENAI_API_KEY` (already used)
- `OPEN_ROUTER_KEY` (optional, already used)
- `BASE_URL` (already used)

---

## Backward Compatibility

| Component | Before | After | Compatible |
|-----------|--------|-------|------------|
| CLI | Direct from scripts | Service import | ✓ YES |
| Handler | sys.path hack | Clean import | ✓ YES |
| Background jobs | From scripts | From service | ✓ YES |
| Tests | May need update | Clean paths | ✓ UPDATE |

**No breaking changes** if migration steps followed.

---

## Quick Troubleshooting

### Import Error: "No module named find_videos"
**Cause:** Trying to import from scripts instead of service
**Fix:** Change import to `from services.video_finder import VideoFinder`

### Flask startup fails with import error
**Cause:** Service file not created or has syntax error
**Fix:** Verify `/src/services/video_finder.py` exists and is valid Python

### CLI script can't find service module
**Cause:** sys.path.insert not working correctly
**Fix:** Check path is relative to `__file__` location, not current directory

### Circular import error
**Cause:** Service importing from handlers
**Fix:** Remove any handler imports from service, keep only utils/config

---

## Timeline

- **Phase 1 (Create Service):** 30 minutes
- **Phase 2 (Update Handler):** 15 minutes  
- **Phase 3 (Simplify CLI):** 30 minutes
- **Testing:** 30-60 minutes
- **Code Review:** 15-30 minutes
- **Total:** 2-3 hours

---

## Post-Migration (Optional)

1. **Unit Tests:** Create `/src/tests/test_video_finder.py`
2. **Documentation:** Update README files
3. **Code Organization:** Extract sub-modules if grows to 2000+ lines
4. **Monitoring:** Add metrics/logging hooks
5. **Async:** Convert to async/await if needed for performance

---

## Decision Questions

Before proceeding, confirm:

1. Is Option A (single file) acceptable?
2. Should tests be updated as part of this?
3. Should unit tests be created?
4. Any performance concerns?
5. Timeline constraints?

---

## Document References

- **Full Plan:** `VIDEO_FINDER_REFACTORING_PLAN.md` (840 lines, detailed)
- **Summary:** `VIDEO_FINDER_REFACTORING_SUMMARY.txt` (423 lines, overview)
- **This Guide:** Quick reference for key information

---

## Quick Commands

```bash
# Test import after phase 1
python3 -c "from src.services.video_finder import VideoFinder; print('OK')"

# Test backend after phase 2
python3 src/app.py

# Test CLI after phase 3
python3 scripts/find_videos.py --help

# Full test suite
python3 -m pytest src/tests/test_video_finder.py -v

# Integration test
POST /v3/search/video {"word": "example"}
```

---

## Recommendation: GO AHEAD

This refactoring is:
- ✓ Low risk (well-understood scope)
- ✓ Backward compatible (no breaking changes)
- ✓ Architecture improvement (clear separation)
- ✓ Future-ready (testable, monitorable)
- ✓ Simple (aligned with CLAUDE.md)

**Proceed with confidence.**

