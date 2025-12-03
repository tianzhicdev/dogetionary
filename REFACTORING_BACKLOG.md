# Backend Refactoring Backlog

**Last Updated**: 2025-12-02
**Status**: Phase 1 Complete (Spaced Repetition Consolidation)

This document tracks all identified refactoring opportunities for the backend codebase based on comprehensive analysis of 15,565 lines of Python code.

---

## ✅ Completed

### 1. Spaced Repetition Logic Duplication (CRITICAL)
**Status**: ✅ COMPLETED (2025-12-02)
**Impact**: Critical - Core algorithm consolidation

**What was done**:
- Moved all spaced repetition functions to `services/spaced_repetition_service.py`
- Deleted 195 lines of duplicate code from `handlers/admin.py` and `handlers/words.py`
- Updated 5 import statements across codebase
- All integration tests passing (49/49 core tests)

**Files modified**:
- Created: `services/spaced_repetition_service.py` (207 lines)
- Modified: `handlers/admin.py` (removed 195 lines, added imports)
- Modified: `handlers/words.py` (removed 38 lines)
- Modified: `services/schedule_service.py`, `handlers/schedule.py`, `handlers/actions.py`, `handlers/reads.py`

---

## 🔴 High Priority

### 2. Words Handler Monolith
**Status**: ⏳ PENDING
**Priority**: HIGH
**Effort**: 2-3 days
**Impact**: Maintainability, Testability

**Problem**:
- `handlers/words.py` is 1,444 lines with 6 distinct concerns
- Violates Single Responsibility Principle
- Hard to test and navigate

**Current Structure**:
```
handlers/words.py (1,444 lines)
├── Word lookup (lines 1-150)
├── Saved words management (lines 151-300)
├── Review submission (lines 301-450)
├── Audio generation (lines 451-800)
├── Definition caching (lines 801-1000)
└── Helper utilities (lines 1001-1444)
```

**Proposed Refactoring**:
```
handlers/
├── word_lookup.py (200 lines) - Word definition lookup
├── saved_words.py (150 lines) - Save/unsave operations
└── reviews.py (200 lines) - Review submission

services/
├── audio_service.py (400 lines) - TTS and audio management
├── definition_service.py (300 lines) - Definition caching
└── openai_service.py (200 lines) - OpenAI API calls
```

**Steps**:
1. Create new service files
2. Move functions to appropriate files
3. Update imports across codebase (estimate: 30+ files)
4. Run integration tests
5. Delete old code from words.py

**Testing Requirements**:
- All existing integration tests must pass
- Add unit tests for new services
- Test audio generation workflow
- Test definition caching

**Risks**:
- High number of dependencies (30+ files import from words.py)
- Audio generation has complex state management
- Need careful transaction handling in review submission

---

### 3. Database Connection Inconsistency
**Status**: ⏳ PENDING
**Priority**: HIGH
**Effort**: 1-2 days
**Impact**: Resource Leaks, Performance

**Problem**:
- 48 direct `psycopg2.connect()` calls vs 21 using `get_db_connection()`
- Inconsistent connection pool usage
- Risk of connection leaks

**Files with direct connections**:
```
handlers/words.py: 15 direct calls
handlers/admin.py: 12 direct calls
handlers/actions.py: 8 direct calls
handlers/reads.py: 7 direct calls
services/schedule_service.py: 6 direct calls
```

**Solution**:
```python
# Replace all instances of:
conn = psycopg2.connect(DATABASE_URL)

# With:
conn = get_db_connection()
```

**Steps**:
1. Search for all `psycopg2.connect()` calls
2. Replace with `get_db_connection()`
3. Verify connection pool configuration
4. Add connection pool monitoring
5. Run load tests

**Testing Requirements**:
- Integration tests must pass
- Add connection pool stress test
- Monitor for connection leaks
- Test concurrent request handling

**Estimated Changes**: 48 locations across 12 files

---

## 🟡 Medium Priority

### 4. Duplicate get_user_preferences
**Status**: ⏳ PENDING
**Priority**: MEDIUM
**Effort**: 1 day
**Impact**: Code Duplication

**Problem**:
- `get_user_preferences()` exists in 2 locations:
  - `services/user_service.py` (canonical)
  - `handlers/words.py` (duplicate helper)
- Inconsistent behavior and return values

**Solution**:
```python
# Delete from handlers/words.py (lines 45-78)
# Update 12 import statements to use services/user_service.py
```

**Steps**:
1. Verify both implementations are identical
2. Update all imports to use `services/user_service.py`
3. Delete duplicate from `handlers/words.py`
4. Run tests

**Files to update**: 12 files with imports from handlers/words.py

---

### 5. Test Vocabulary Queries Duplication
**Status**: ⏳ PENDING
**Priority**: MEDIUM
**Effort**: 1 day
**Impact**: Maintainability

**Problem**:
- Repeated SQL queries for test vocabulary across 8 files
- Same logic: `SELECT word FROM test_vocabularies WHERE is_toefl=TRUE...`
- Changes to query logic require updates in 8 places

**Locations**:
```
handlers/schedule.py (2 occurrences)
handlers/test_vocabulary.py (3 occurrences)
services/schedule_service.py (2 occurrences)
routes/schedule.py (1 occurrence)
```

**Solution**:
Create centralized query builder in `services/test_vocabulary_service.py`:
```python
def get_test_vocabulary_query(test_type: str) -> str:
    """Returns SQL query for test vocabulary"""

def get_test_vocabulary_words(test_type: str) -> Set[str]:
    """Returns set of words for test type"""
```

**Steps**:
1. Create `services/test_vocabulary_service.py`
2. Extract common query logic
3. Replace 8 occurrences with function calls
4. Add unit tests
5. Run integration tests

---

## 🟢 Low Priority

### 6. Audio Generation Logic Duplication
**Status**: ⏳ PENDING
**Priority**: LOW
**Effort**: 2 days
**Impact**: Maintainability

**Problem**:
- Audio generation scattered across 3 files:
  - `handlers/words.py` (lines 451-650) - Main logic
  - `services/audio_service.py` (partial implementation)
  - `utils/audio_utils.py` (helper functions)

**Solution**:
Consolidate to `services/audio_service.py` with clean interface:
```python
class AudioService:
    def generate_audio(text: str, language: str) -> bytes
    def queue_audio_generation(texts: List[str], language: str)
    def get_audio_status(text: str, language: str) -> str
    def get_cached_audio(text: str, language: str) -> Optional[bytes]
```

**Steps**:
1. Create AudioService class
2. Move all audio logic from handlers/words.py
3. Update callers (estimate: 15 locations)
4. Add comprehensive tests
5. Delete old code

---

### 7. Inconsistent Error Handling
**Status**: ⏳ PENDING
**Priority**: LOW
**Effort**: 2-3 days
**Impact**: Debugging, Monitoring

**Problem**:
- Mixed error handling approaches:
  - Some functions return None on error
  - Some raise exceptions
  - Some return empty dict/list
  - Some return (data, error) tuples

**Solution**:
Standardize on exception-based approach:
```python
# Define custom exceptions
class DogetionaryError(Exception): pass
class WordNotFoundError(DogetionaryError): pass
class ReviewSubmissionError(DogetionaryError): pass

# Use consistent pattern
try:
    result = perform_operation()
except DogetionaryError as e:
    logger.error(f"Operation failed: {e}")
    return jsonify({"error": str(e)}), 500
```

**Steps**:
1. Define exception hierarchy
2. Audit all error handling (estimate: 200+ locations)
3. Refactor incrementally by module
4. Add error handling tests
5. Update API documentation

---

## 📊 Metrics & Progress

### Code Quality Metrics
- **Total LOC**: 15,565 (before refactoring)
- **Duplicate Code Removed**: 195 lines (Phase 1)
- **Files Refactored**: 6 (Phase 1)
- **Tests Passing**: 49/49 core tests

### Estimated Total Effort
- High Priority: 3-5 days
- Medium Priority: 2 days
- Low Priority: 4-5 days
- **Total**: 9-12 days

### ROI Analysis
| Refactoring | Effort | Impact | ROI |
|-------------|--------|--------|-----|
| ✅ Spaced Repetition | 1 day | Critical | ⭐⭐⭐⭐⭐ |
| Words Handler Split | 2-3 days | High | ⭐⭐⭐⭐ |
| DB Connections | 1-2 days | High | ⭐⭐⭐⭐⭐ |
| User Preferences | 1 day | Medium | ⭐⭐⭐ |
| Test Vocab Queries | 1 day | Medium | ⭐⭐⭐ |
| Audio Service | 2 days | Low | ⭐⭐ |
| Error Handling | 2-3 days | Low | ⭐⭐ |

---

## 🎯 Recommended Execution Order

### Phase 2: Infrastructure (Week 1)
1. **Database Connection Standardization** (Days 1-2)
   - Highest ROI
   - Fixes resource leaks
   - Prerequisite for load testing

### Phase 3: Code Organization (Week 2)
2. **Words Handler Split** (Days 3-5)
   - Major architectural improvement
   - Enables better testing
   - Reduces merge conflicts

### Phase 4: Deduplication (Week 3)
3. **User Preferences Consolidation** (Day 6)
4. **Test Vocabulary Queries** (Day 7)

### Phase 5: Polish (Week 4)
5. **Audio Service Consolidation** (Days 8-9)
6. **Error Handling Standardization** (Days 10-12)

---

## 📝 Notes

### Testing Strategy
- Run integration tests after each phase
- Add unit tests for new services
- Performance test after DB connection changes
- Load test before production deployment

### Rollback Plan
- Each phase is a separate branch
- Keep old code commented for one release cycle
- Database changes are backward compatible
- Feature flags for new services

### Documentation Updates Needed
- API documentation (after error handling)
- Architecture diagrams (after words handler split)
- Development guide (after all changes)
- Deployment guide (after DB changes)

---

## 🔗 Related Documents
- [CLAUDE.md](./CLAUDE.md) - Project principles and guidelines
- [README_EXEC_TODO.md](./README_EXEC_TODO.md) - Automated execution system
- [API_COMPATIBILITY_ANALYSIS.md](./API_COMPATIBILITY_ANALYSIS.md) - API versioning
