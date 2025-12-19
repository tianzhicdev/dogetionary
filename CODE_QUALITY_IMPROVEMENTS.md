# Backend Code Quality Improvement Plan

## Executive Summary

**Overall Assessment**: The codebase has **solid architectural foundations** but suffers from implementation anti-patterns that create maintenance burden and potential bugs.

**Key Strengths**:
- ✅ Blueprint-based architecture with clean V3 API separation
- ✅ Service layer for business logic (definition_service, spaced_repetition_service)
- ✅ Connection pooling (min=10, max=50)
- ✅ Parameterized SQL queries (no SQL injection via concatenation)

**Critical Issues**:
- ❌ **70 instances** of manual database connection management
- ❌ God functions up to **481 lines** long
- ❌ Extensive code duplication (UUID validation, audio logic, test type determination)
- ❌ Inconsistent error handling (3 different patterns)
- ❌ N+1 query patterns in batch operations

**Total Backend Code**: ~8,400 lines across handlers
**Estimated Refactoring Effort**: 3-4 sprints for critical + high priority items

---

## 1. CRITICAL: Database Connection Management Anti-Pattern

### Problem
**70 instances** of manual `conn = get_db_connection()` with inconsistent cleanup:

```python
# BAD - Current pattern (found in 23 files)
conn = get_db_connection()
cur = conn.cursor()
try:
    cur.execute(...)
    conn.commit()
except Exception as e:
    conn.rollback()
    raise e
finally:
    cur.close()
    conn.close()
```

**Issues**:
1. **81 manual cleanup calls** - error-prone boilerplate
2. **Connection leaks** - exceptions before finally blocks
3. **Multiple connections per function** - `submit_review()` opens 2 separate connections
4. **Long-held connections** - `get_review_words_batch()` holds for **381 lines**

### Solution
Use existing `db_cursor()` context manager consistently:

```python
# GOOD - Already available in database.py
with db_cursor(commit=True) as cur:
    cur.execute(...)
    # Automatic commit, cleanup, error handling
```

### Files to Refactor (Priority Order)

**Critical - Immediate Action**:
1. `handlers/actions.py` - submit_review() opens 2 connections (lines 176-304)
2. `handlers/review_batch.py` - get_review_words_batch() 481 lines (lines 100-481)
3. `handlers/schedule.py` - get_today_schedule() 214 lines (lines 62-276)

**High Priority**:
4. `handlers/words.py` - get_saved_words() 152 lines (lines 285-436)
5. `handlers/achievements.py` - Multiple functions with manual management
6. `handlers/bundle_vocabulary.py` - Schedule generation functions

**All Files with Manual Connections** (60+ total):
- actions.py (6 occurrences)
- review_batch.py (8 occurrences)
- schedule.py (5 occurrences)
- words.py (10 occurrences)
- achievements.py (7 occurrences)
- users.py (4 occurrences)
- reads.py (5 occurrences)
- pronunciation.py (3 occurrences)
- streaks.py (4 occurrences)
- bundle_vocabulary.py (6 occurrences)
- enhanced_review.py (2 occurrences)
- admin.py (3 occurrences)
- + 10 more service/util files

### Implementation Steps
1. Create refactoring script to identify all patterns
2. Refactor in batches by file
3. Add integration tests to verify no regressions
4. Deploy and monitor for connection pool metrics

---

## 2. CRITICAL: Break Up God Functions

### Problem
Functions exceeding 150 lines with high cyclomatic complexity:

**Top 3 Offenders**:
1. `get_review_words_batch()` - **481 lines** (review_batch.py:100-481)
2. `get_today_schedule()` - **214 lines** (schedule.py:62-276)
3. `get_saved_words()` - **152 lines** (words.py:285-436)

**Issues**:
- Hard to test individual logic paths
- Difficult to understand at a glance
- High risk of bugs when modifying
- Poor code reusability

### Solution
Extract sub-functions following Single Responsibility Principle:

#### Example: review_batch.py refactoring

**Before** (481 lines):
```python
def get_review_words_batch():
    # 1. Parse parameters (20 lines)
    # 2. Fetch scheduled new words (80 lines)
    # 3. Fetch overdue words (120 lines)
    # 4. Generate questions (150 lines)
    # 5. Format response (111 lines)
    # All mixed together!
```

**After** (orchestration + helper functions):
```python
def get_review_words_batch():
    """Main orchestrator - should be <50 lines"""
    user_id, count = _parse_batch_params()

    scheduled_words = _fetch_scheduled_new_words(user_id, count)
    if len(scheduled_words) < count:
        overdue_words = _fetch_overdue_words(user_id, count - len(scheduled_words))
        all_words = scheduled_words + overdue_words
    else:
        all_words = scheduled_words

    questions = _generate_questions_batch(all_words)
    return _format_batch_response(questions, user_id)

def _parse_batch_params() -> tuple[str, int]:
    """Extract and validate request parameters"""
    # 15 lines max

def _fetch_scheduled_new_words(user_id: str, count: int) -> List[dict]:
    """Fetch today's scheduled new words"""
    # 40 lines max

def _fetch_overdue_words(user_id: str, count: int) -> List[dict]:
    """Fetch overdue review words"""
    # 50 lines max

def _generate_questions_batch(words: List[dict]) -> List[dict]:
    """Generate questions for word batch"""
    # 60 lines max

def _format_batch_response(questions: List[dict], user_id: str) -> tuple:
    """Format final JSON response"""
    # 30 lines max
```

### Refactoring Priority
1. **review_batch.py**: get_review_words_batch() (481 lines → 5 functions <60 lines each)
2. **schedule.py**: get_today_schedule() (214 lines → 4 functions)
3. **words.py**: get_saved_words() (152 lines → 3 functions)

---

## 3. HIGH PRIORITY: Eliminate Code Duplication

### Issue 1: UUID Validation (15+ occurrences)

**Current**:
```python
# Repeated in actions.py, words.py, achievements.py, users.py, etc.
try:
    uuid.UUID(user_id)
except ValueError:
    return jsonify({"error": "Invalid user_id format. Must be a valid UUID"}), 400
```

**Solution**:
```python
# utils/validation.py
from functools import wraps
from flask import jsonify, request

def require_valid_uuid(param_name: str = 'user_id', source: str = 'json'):
    """Decorator to validate UUID parameter"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            if source == 'json':
                value = request.get_json().get(param_name)
            else:  # 'args'
                value = request.args.get(param_name)

            if not value:
                return jsonify({"error": f"{param_name} is required"}), 400

            try:
                uuid.UUID(value)
            except ValueError:
                return jsonify({"error": f"Invalid {param_name} format"}), 400

            return func(*args, **kwargs)
        return wrapper
    return decorator

# Usage
@require_valid_uuid('user_id', source='args')
def get_saved_words():
    user_id = request.args.get('user_id')  # Already validated
    # ... rest of logic
```

### Issue 2: Audio Generation Duplication

**Locations**:
- `handlers/words.py`: get_audio() + generate_audio_for_text() + store_audio() (lines 440-493)
- `handlers/enhanced_review.py`: get_or_generate_audio_base64() (lines 20-72)

**Identical logic** in both places - changes must be synchronized!

**Solution**:
```python
# services/audio_service.py
class AudioService:
    @staticmethod
    def get_or_generate_audio(text: str, language: str) -> Optional[str]:
        """Single source of truth for audio generation"""
        # 1. Try database cache
        cached = AudioService._fetch_cached_audio(text, language)
        if cached:
            return cached

        # 2. Generate with TTS
        audio_bytes = AudioService._generate_with_tts(text, language)
        if not audio_bytes:
            return None

        # 3. Store in database
        AudioService._store_audio(text, language, audio_bytes)
        return base64.b64encode(audio_bytes).decode('utf-8')

    @staticmethod
    def _fetch_cached_audio(text: str, language: str) -> Optional[str]:
        # Implementation

    @staticmethod
    def _generate_with_tts(text: str, language: str) -> Optional[bytes]:
        # Implementation

    @staticmethod
    def _store_audio(text: str, language: str, audio_bytes: bytes):
        # Implementation
```

**Then replace both locations**:
```python
# handlers/words.py
from services.audio_service import AudioService

def get_audio():
    text = request.args.get('text')
    language = request.args.get('language')
    audio_data = AudioService.get_or_generate_audio(text, language)
    # ... return response
```

### Issue 3: Test Type Determination (5+ occurrences)

**Repeated in**:
- achievements.py (lines 209-214)
- schedule.py (multiple locations)
- bundle_vocabulary.py
- practice_status.py

**Solution**:
```python
# services/user_service.py
def get_active_test_type(user_id: str) -> Optional[str]:
    """Single source of truth for active test type"""
    prefs = _get_test_preferences(user_id)

    # Priority order
    test_priority = [
        ('toefl_beginner_enabled', 'TOEFL_BEGINNER'),
        ('toefl_intermediate_enabled', 'TOEFL_INTERMEDIATE'),
        ('toefl_advanced_enabled', 'TOEFL_ADVANCED'),
        ('ielts_beginner_enabled', 'IELTS_BEGINNER'),
        ('ielts_intermediate_enabled', 'IELTS_INTERMEDIATE'),
        ('ielts_advanced_enabled', 'IELTS_ADVANCED'),
        ('demo_enabled', 'DEMO'),
        ('business_english_enabled', 'BUSINESS_ENGLISH'),
        ('everyday_english_enabled', 'EVERYDAY_ENGLISH'),
    ]

    for pref_key, test_type in test_priority:
        if prefs.get(pref_key):
            return test_type

    return None
```

---

## 4. HIGH PRIORITY: Fix N+1 Query Patterns

### Problem: review_batch.py (lines 390-426)

**Current**:
```python
for position, row in enumerate(all_word_rows):
    word = row['word']

    # Query 1: Fetch definition (N queries!)
    cur.execute("""
        SELECT definition_data FROM definitions
        WHERE word = %s AND learning_language = %s
    """, (word, learning_lang))

    # Query 2: Generate question (may hit DB again)
    question = get_or_generate_question(...)
```

**Impact**: Batch of 20 words = 40+ database queries

**Solution**: Batch load all data upfront
```python
# Fetch ALL definitions in ONE query
words_to_fetch = [row['word'] for row in all_word_rows]
cur.execute("""
    SELECT word, definition_data FROM definitions
    WHERE word = ANY(%s) AND learning_language = %s
""", (words_to_fetch, learning_lang))

# Build lookup dictionary
definitions = {row['word']: row['definition_data'] for row in cur.fetchall()}

# No more queries in loop!
for position, row in enumerate(all_word_rows):
    word = row['word']
    definition_data = definitions.get(word)
    # ... process
```

---

## 5. HIGH PRIORITY: Standardize Error Handling

### Problem: 3 Inconsistent Patterns

**Pattern A** (good - 60% of handlers):
```python
except Exception as e:
    logger.error(f"Error submitting review: {str(e)}", exc_info=True)
    return jsonify({"error": f"Failed to submit review: {str(e)}"}), 500
```

**Pattern B** (bad - using print):
```python
# user_service.py:102
except Exception as e:
    print(f"Error getting user preferences: {str(e)}")  # ❌
    return 'en', 'zh', 'LearningExplorer', 'Every word is a new adventure!'
```

**Pattern C** (loses context):
```python
except Exception as e:
    logger.error(f"Error: {e}", exc_info=True)
    return jsonify({"error": "Internal server error"}), 500  # ❌ Lost details
```

### Solution: Create Error Handler Decorator

```python
# utils/error_handlers.py
from functools import wraps
from flask import jsonify
import logging

logger = logging.getLogger(__name__)

class ValidationError(Exception):
    """User input validation error"""
    pass

class DatabaseError(Exception):
    """Database operation error"""
    pass

def handle_api_errors(func):
    """Standard error handler for API endpoints"""
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)

        except ValidationError as e:
            # User errors - 400
            logger.warning(f"Validation error in {func.__name__}: {e}")
            return jsonify({"error": str(e)}), 400

        except DatabaseError as e:
            # Database errors - 500
            logger.error(f"Database error in {func.__name__}: {e}", exc_info=True)
            return jsonify({"error": "Database operation failed"}), 500

        except Exception as e:
            # Unexpected errors - 500
            logger.error(f"Unexpected error in {func.__name__}: {e}", exc_info=True)
            return jsonify({"error": "Internal server error"}), 500

    return wrapper

# Usage
@handle_api_errors
def submit_review():
    user_id = request.get_json().get('user_id')
    if not user_id:
        raise ValidationError("user_id is required")

    # ... business logic
    # Exceptions automatically handled
```

---

## 6. MEDIUM PRIORITY: Remove Wildcard Imports

### Problem
Found in 5 handler files:
- handlers/actions.py:25
- handlers/words.py:25
- handlers/reads.py:27
- handlers/admin.py:24
- handlers/users.py:24

```python
from config.config import *  # ❌ Imports everything
```

**Issues**:
- Pollutes namespace
- Can shadow built-ins
- Makes dependencies unclear
- IDE can't provide proper autocomplete

### Solution
```python
# Explicit imports
from config.config import (
    SUPPORTED_LANGUAGES,
    TTS_MODEL_NAME,
    FALLBACK_CHAINS,
    MAX_RETRIES
)
```

**Implementation**: Simple find-replace across 5 files

---

## 7. MEDIUM PRIORITY: Fix SQL Injection Risks

### Problem: Dynamic Column Names in SQL

**Location**: schedule.py:896, achievements.py:209

```python
# schedule.py:896 - F-string variable in SQL
cur.execute(f"""
    SELECT COUNT(DISTINCT word) as total
    FROM bundle_vocabularies
    WHERE {vocab_column} = TRUE  # ❌ Risk if source changes
""")
```

**Current**: `vocab_column` comes from trusted dict, but risky pattern

### Solution
```python
# Whitelist validation
ALLOWED_VOCAB_COLUMNS = {
    'is_toefl_beginner',
    'is_toefl_intermediate',
    'is_toefl_advanced',
    'is_ielts_beginner',
    'is_ielts_intermediate',
    'is_ielts_advanced',
    'is_demo',
    'is_business_english',
    'is_everyday_english'
}

def validate_vocab_column(column: str) -> str:
    """Validate column name against whitelist"""
    if column not in ALLOWED_VOCAB_COLUMNS:
        raise ValueError(f"Invalid vocabulary column: {column}")
    return column

# Usage
vocab_column = validate_vocab_column(vocab_column)
cur.execute(f"""
    SELECT COUNT(DISTINCT word) as total
    FROM bundle_vocabularies
    WHERE {vocab_column} = TRUE  -- Safe after validation
""")
```

---

## 8. MEDIUM PRIORITY: Add Rate Limiting

### Problem
Expensive operations with no throttling:
- `get_word_definition_v4()`: Calls LLM API
- `get_illustration()`: Generates DALL-E images
- `practice_pronunciation()`: Calls Whisper API

**Risk**: Could be abused for high API costs

### Solution
```python
# requirements.txt
flask-limiter==3.5.0

# app.py or middleware/rate_limiter.py
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

def get_user_id():
    """Extract user_id for rate limiting key"""
    if request.is_json:
        return request.get_json().get('user_id', get_remote_address())
    return request.args.get('user_id', get_remote_address())

limiter = Limiter(
    app=app,
    key_func=get_user_id,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="redis://localhost:6379"  # Or memory:// for simple setup
)

# Apply to expensive endpoints
@app.route('/v3/word', methods=['GET'])
@limiter.limit("10 per minute")  # Strict limit for LLM calls
def get_word_definition_v4():
    # ...

@app.route('/v3/illustration', methods=['POST'])
@limiter.limit("5 per hour")  # Very strict for DALL-E
def get_illustration():
    # ...
```

---

## 9. LOW PRIORITY: Improve Type Safety

### Current State
Most handler functions lack type hints:

```python
def get_saved_words():  # ❌ No hints
    user_id = request.args.get('user_id')
    # ... 152 lines
    return jsonify(...)
```

### Recommended
```python
from typing import Optional, List, Dict, Tuple
from flask import Response

def get_saved_words() -> Tuple[Response, int]:
    """Get user's saved words with progress tracking"""
    user_id: str = request.args.get('user_id')
    # ... logic
    return jsonify(response_data), 200
```

**Benefits**:
- Better IDE autocomplete
- Catch type errors at development time
- Self-documenting code

---

## 10. ARCHITECTURAL IMPROVEMENTS

### Recommendation: Repository Pattern

**Problem**: Complex SQL queries scattered in handlers

**Current** (words.py:313-380):
```python
# 68-line SQL query directly in handler
cur.execute("""
    WITH recent_reviews AS (
        SELECT word_id,
        COUNT(*) FILTER (WHERE response = TRUE ...) as correct_84d,
        # ... 40 more lines of SQL ...
    )
    SELECT sw.id, sw.word, ...
    # ... another 20 lines ...
""", (user_id,))
```

**Solution**: Extract to repository layer
```python
# repositories/word_repository.py
class WordRepository:
    @staticmethod
    def get_saved_words_with_progress(
        user_id: str,
        exclude_known: bool = True
    ) -> List[Dict]:
        """
        Fetch saved words with review progress.
        Encapsulates complex CTE query logic.
        """
        with db_cursor() as cur:
            cur.execute("""
                WITH recent_reviews AS (...)
                SELECT ...
            """, (user_id,))
            return cur.fetchall()

# handlers/words.py - Much cleaner!
from repositories.word_repository import WordRepository

def get_saved_words():
    user_id = request.args.get('user_id')
    words = WordRepository.get_saved_words_with_progress(user_id)
    return jsonify({"words": words}), 200
```

---

## IMPLEMENTATION ROADMAP

### Sprint 1: Critical Fixes (Week 1-2)
**Goal**: Fix connection leaks and immediate risks

- [ ] Refactor top 10 handlers to use `db_cursor()` context manager
  - actions.py (submit_review)
  - review_batch.py (get_review_words_batch)
  - schedule.py (get_today_schedule)
  - words.py (get_saved_words)
- [ ] Add whitelist validation for dynamic SQL column names
- [ ] Fix N+1 query in review_batch.py
- [ ] Add integration tests for refactored functions

**Success Metrics**:
- Connection leak monitoring shows 0 leaks
- Average response time for batch endpoint improves 30%

### Sprint 2: Code Quality (Week 3-4)
**Goal**: Reduce duplication and improve maintainability

- [ ] Create validation utilities (UUID, parameters)
- [ ] Consolidate audio generation logic into AudioService
- [ ] Extract test type determination to user_service
- [ ] Standardize error handling with decorators
- [ ] Remove wildcard imports from 5 handler files

**Success Metrics**:
- Code duplication reduced by 40% (measured by SonarQube)
- Average function length <80 lines

### Sprint 3: Refactoring (Week 5-6)
**Goal**: Break up god functions and improve structure

- [ ] Refactor get_review_words_batch() into 5 sub-functions
- [ ] Refactor get_today_schedule() into 4 sub-functions
- [ ] Refactor get_saved_words() into 3 sub-functions
- [ ] Add comprehensive unit tests for extracted functions

**Success Metrics**:
- Cyclomatic complexity <10 for all functions
- Test coverage >80%

### Sprint 4: Infrastructure (Week 7-8)
**Goal**: Add rate limiting and improve observability

- [ ] Add flask-limiter with Redis backend
- [ ] Apply rate limits to expensive endpoints (LLM, DALL-E, Whisper)
- [ ] Add type hints to top 20 most-used functions
- [ ] Create repository layer for complex queries
- [ ] Add performance monitoring metrics

**Success Metrics**:
- API abuse attempts blocked
- 0 type errors in CI pipeline
- Query performance improved 20%

---

## MEASURING SUCCESS

### Key Metrics to Track

#### Code Quality Metrics
- **Lines of Code**: Reduce by 10% through deduplication
- **Cyclomatic Complexity**: All functions <10
- **Code Duplication**: <5% (SonarQube)
- **Test Coverage**: >80%

#### Performance Metrics
- **Connection Pool Utilization**: <80% at peak
- **Average Response Time**: Improve by 25%
- **P95 Response Time**: <500ms for all endpoints
- **Database Query Count**: Reduce N+1 patterns by 100%

#### Reliability Metrics
- **Connection Leaks**: 0 per day
- **Error Rate**: <0.5%
- **API Abuse Blocked**: Track rate limit hits
- **Production Incidents**: Reduce by 40%

---

## TOOLS & SETUP

### Recommended Tools
```bash
# Code quality analysis
pip install pylint black isort mypy

# Run static analysis
pylint src/handlers/*.py --max-line-length=120
black src/ --check
isort src/ --check-only
mypy src/ --strict

# Complexity analysis
pip install radon
radon cc src/handlers -a -nb  # Cyclomatic complexity
radon mi src/handlers -nb      # Maintainability index
```

### Pre-commit Hooks
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/psf/black
    rev: 23.12.0
    hooks:
      - id: black
        args: [--line-length=120]

  - repo: https://github.com/PyCQA/isort
    rev: 5.13.2
    hooks:
      - id: isort

  - repo: https://github.com/PyCQA/pylint
    rev: v3.0.3
    hooks:
      - id: pylint
        args: [--max-line-length=120]
```

---

## CONCLUSION

This improvement plan addresses **critical technical debt** while maintaining backward compatibility. The phased approach allows continuous deployment without disrupting production.

**Priority**: Focus on Sprint 1 (connection management) immediately, as connection leaks can cause production outages.

**Estimated Impact**:
- 40% reduction in bugs related to resource leaks
- 25% improvement in response times
- 50% reduction in code review time (clearer, more consistent code)
- Better developer onboarding experience
