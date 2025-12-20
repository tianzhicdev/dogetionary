# Refactor Analysis: Standardize to `get_or_generate_*` Pattern

## Current State Analysis

### Database Schema - Caching Tables

The database already has a **consistent caching pattern**:

1. **`definitions`** (lines 68-81):
   - Primary key: `(word, learning_language, native_language)`
   - Cache for: LLM-generated word definitions
   - Pattern: ✅ Already follows cache-first

2. **`audio`** (lines 55-66):
   - Primary key: `(text_content, language)`
   - Cache for: OpenAI TTS audio (mp3)
   - Pattern: ✅ Already follows cache-first

3. **`review_questions`** (lines 111-124):
   - Primary key: `(word, learning_language, native_language, question_type)`
   - Cache for: LLM-generated review questions
   - Pattern: ✅ Already follows cache-first

4. **`illustrations`** (lines 176-185):
   - Primary key: `(word, language)`
   - Cache for: AI-generated illustrations (scene + DALL-E image)
   - Pattern: ✅ Already follows cache-first

**Conclusion**: Database schema is **already optimized** for the `get_or_generate_*` pattern. No schema changes needed!

---

## Current Implementation Patterns

### ✅ GOOD: Already Following Pattern

**1. `generate_definition_with_llm()` - services/definition_service.py:208-279**
- ✅ Checks cache first (lines 227-237)
- ✅ Generates with LLM if cache miss (lines 239-275)
- ✅ Stores in DB (lines 281-293)
- **Naming**: Should be `get_or_generate_definition()`

**2. `get_or_generate_question()` - services/question_generation_service.py:561-661**
- ✅ Checks cache via `get_cached_question()` (line 628)
- ✅ Generates with LLM if cache miss (line 634)
- ✅ Stores via `cache_question()` (line 637)
- **Naming**: ✅ Perfect!

**3. `get_illustration()` - handlers/words.py:554-703**
- ✅ Checks cache first (lines 576-595)
- ✅ Generates if cache miss (lines 597-686)
- ✅ Stores in DB (lines 673-682)
- **Naming**: Should be `get_or_generate_illustration()`

---

### ⚠️ INCONSISTENT: Needs Refactoring

**4. Audio Functions - Multiple Implementations**

**Current mess**:
- `get_or_generate_audio_base64()` in review_batch.py:21-72 ✅
- `get_or_generate_audio_base64()` in enhanced_review.py:19-71 (DUPLICATE, UNUSED)
- `get_audio()` in words.py:495-551 (HTTP endpoint, different purpose)
- `generate_audio_for_text()` in words.py:440-455 (utility)
- `store_audio()` in words.py:457-493 (utility)
- `audio_exists()` in words.py:127-148 (check only)

**Problem**: 
- Duplicate code in 2 files
- Inconsistent naming (`get_audio` is HTTP endpoint, not utility)
- Shared logic scattered across 3 functions

---

## Proposed Refactor

### Phase 1: Create Service Layer (High Priority)

**Create `services/audio_service.py`**:
```python
def get_or_generate_audio(text: str, language: str) -> bytes:
    """
    Get or generate audio data (cache-first pattern).
    
    Returns:
        Raw audio bytes (mp3)
    """
    # Check cache
    result = db_fetch_one(
        "SELECT audio_data FROM audio WHERE text_content = %s AND language = %s",
        (text, language)
    )
    
    if result:
        logger.info(f"Audio cache hit for '{text[:50]}...'")
        return result['audio_data']
    
    # Generate
    logger.info(f"Generating audio for '{text[:50]}...' in {language}")
    audio_data = generate_audio_for_text(text)  # OpenAI TTS call
    
    # Store
    store_audio(text, language, audio_data)
    
    return audio_data


def get_or_generate_audio_base64(text: str, language: str) -> str:
    """
    Get or generate audio as base64 data URI.
    
    Returns:
        Data URI string: "data:audio/mpeg;base64,..."
    """
    audio_data = get_or_generate_audio(text, language)
    audio_base64 = base64.b64encode(audio_data).decode('utf-8')
    return f"data:audio/mpeg;base64,{audio_base64}"


# Move these from handlers/words.py
def generate_audio_for_text(text: str) -> bytes: ...
def store_audio(text: str, language: str, audio_data: bytes) -> str: ...
def audio_exists(text: str, language: str) -> bool: ...
```

**Files to update**:
- `services/audio_service.py` (NEW)
- `handlers/words.py` - move 3 functions, update `get_audio()` endpoint
- `handlers/review_batch.py` - delete duplicate, import from service
- `handlers/enhanced_review.py` - delete duplicate (already unused)
- `services/question_generation_service.py` - import from service

**Impact**: 
- ✅ Consolidates 6 functions into 1 service
- ✅ Removes 50+ lines of duplicate code
- ✅ Consistent naming
- ⚠️ Medium risk (audio is used everywhere)

---

### Phase 2: Rename for Consistency (Low Priority)

**Rename these functions**:

1. `generate_definition_with_llm()` → `get_or_generate_definition()`
   - File: `services/definition_service.py`
   - Update imports in: handlers/review_batch.py, handlers/enhanced_review.py, handlers/words.py
   - **Impact**: Low risk, only 3 import sites

2. `get_illustration()` → `get_or_generate_illustration()`
   - File: `handlers/words.py`
   - Update route registration in: `app_v3.py`
   - **Impact**: Very low risk, only 1 route registration

3. Keep `get_or_generate_question()` as-is ✅

**Result**: Consistent naming across all LLM-generated resources:
- `get_or_generate_definition()`
- `get_or_generate_audio()`
- `get_or_generate_audio_base64()`
- `get_or_generate_question()`
- `get_or_generate_illustration()`

---

### Phase 3: Optimize N+1 Queries (Medium Priority)

**Problem**: `collect_audio_references()` in words.py:151-161

Current code makes **1 query per example**:
```python
for example in def_group.get('examples', []):
    if audio_exists(example, learning_lang):  # ← DB query!
        audio_refs["example_audio"][example] = True
```

**Optimization**:
```python
def collect_audio_references(definition_data: dict, learning_lang: str) -> dict:
    """Collect all audio references with SINGLE query"""
    audio_refs = {"example_audio": {}, "word_audio": None}
    
    # Collect all texts to check
    texts_to_check = []
    for def_group in definition_data.get('definitions', []):
        texts_to_check.extend(def_group.get('examples', []))
    
    if not texts_to_check:
        return audio_refs
    
    # SINGLE query with IN clause
    conn = get_db_connection()
    cur = conn.cursor()
    placeholders = ','.join(['%s'] * len(texts_to_check))
    cur.execute(f"""
        SELECT text_content 
        FROM audio 
        WHERE text_content IN ({placeholders}) 
        AND language = %s
    """, (*texts_to_check, learning_lang))
    
    # Build availability map
    existing_texts = {row['text_content'] for row in cur.fetchall()}
    for text in texts_to_check:
        if text in existing_texts:
            audio_refs["example_audio"][text] = True
    
    cur.close()
    conn.close()
    return audio_refs
```

**Impact**:
- ✅ Reduces N+1 queries to 1 query
- ✅ For word with 5 examples: 6 queries → 2 queries (word + all examples)
- ⚠️ Medium risk, used in review batch path

---

## Impact Summary

### Files to Create
1. `services/audio_service.py` (NEW)

### Files to Modify

**High Priority (Phase 1 - Audio Consolidation)**:
1. `services/audio_service.py` - Create service
2. `handlers/words.py` - Move functions, update `get_audio()` endpoint
3. `handlers/review_batch.py` - Delete duplicate, import from service
4. `handlers/enhanced_review.py` - Delete duplicate
5. `services/question_generation_service.py` - Import from service

**Low Priority (Phase 2 - Naming)**:
6. `services/definition_service.py` - Rename function
7. `app_v3.py` - Update route registration
8. `handlers/review_batch.py` - Update import
9. `handlers/enhanced_review.py` - Update import (if file still exists)

**Medium Priority (Phase 3 - Optimization)**:
10. `handlers/words.py` - Optimize `collect_audio_references()`

---

## Migration Risk Assessment

### Phase 1: Audio Consolidation
- **Risk**: ⚠️ Medium
- **Why**: Audio is used in multiple critical paths (review, pronunciation, questions)
- **Mitigation**: 
  - Keep `get_audio()` HTTP endpoint unchanged (just use service internally)
  - Add integration tests for audio generation
  - Deploy with monitoring on audio endpoints

### Phase 2: Naming
- **Risk**: ✅ Low
- **Why**: Pure refactoring, no logic changes
- **Mitigation**: 
  - Update all import sites in same commit
  - Run full test suite

### Phase 3: N+1 Optimization
- **Risk**: ⚠️ Medium
- **Why**: Changes query pattern in hot path
- **Mitigation**:
  - Add performance tests
  - Monitor query counts in production
  - Can rollback easily (no schema changes)

---

## Recommended Approach

**Option A: All at once (High Risk, High Reward)**
- Do all 3 phases in single PR
- Pros: Consistent codebase immediately
- Cons: Large change, harder to debug if issues

**Option B: Incremental (Recommended)**
1. **Week 1**: Phase 1 (Audio service) + monitoring
2. **Week 2**: Phase 3 (N+1 optimization) + performance testing  
3. **Week 3**: Phase 2 (Naming) for final polish

**Option C: Just Phase 1**
- Only consolidate audio service
- Skip naming changes and optimization
- Pros: Removes code duplication, safer
- Cons: Leaves inconsistent naming

---

## Answer to Your Questions

**Q: Is this easy to refactor?**
- **A**: YES - The database schema already supports the pattern perfectly ✅
- No schema migrations needed
- Main work is consolidating duplicate code

**Q: What does this impact?**
- **A**: See "Files to Modify" section above
- **10 files total** (1 new, 9 modified)
- Most impactful: Audio service consolidation (removes duplication)
- Safest: Naming changes (pure refactoring)

**Q: Should we do this?**
- **A**: YES for Phase 1 (audio consolidation) - removes 50+ lines of duplicate code
- **MAYBE** for Phase 2 (naming) - nice to have but not urgent
- **YES** for Phase 3 (N+1 fix) - clear performance win

---

## Next Steps

If you want to proceed:
1. I can start with Phase 1 (create audio service)
2. Or we can do all 3 phases together
3. Or just give you this analysis and you decide

Let me know!
