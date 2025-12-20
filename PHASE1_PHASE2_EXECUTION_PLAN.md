# Phase 1 & 2 Execution Plan: Audio Service + Naming Consistency

## Overview
- **Phase 1**: Create audio service and consolidate duplicate code
- **Phase 2**: Rename functions for consistency
- **Total files**: 13 files (1 new, 12 modified)
- **Estimated lines changed**: ~200 lines

---

## Phase 1: Audio Service Consolidation

### Step 1.1: Create New Service File

**File**: `src/services/audio_service.py` (NEW FILE)

**Content**: Move 3 functions from `handlers/words.py` + add 2 new wrapper functions

```python
"""
Audio Service

Provides consistent cache-first audio generation for TTS.
All audio operations should go through this service.
"""

import base64
import logging
import openai
from typing import Optional
from utils.database import db_fetch_one, get_db_connection

logger = logging.getLogger(__name__)

# TTS Configuration
TTS_MODEL_NAME = "tts-1"
TTS_VOICE = "nova"


def generate_audio_for_text(text: str) -> bytes:
    """Generate TTS audio for text using OpenAI"""
    # MOVE from handlers/words.py:440-455 (16 lines)
    ...


def store_audio(text: str, language: str, audio_data: bytes) -> str:
    """Store audio, return the created_at timestamp"""
    # MOVE from handlers/words.py:457-493 (37 lines)
    ...


def audio_exists(text: str, language: str) -> bool:
    """Check if audio exists for text+language"""
    # MOVE from handlers/words.py:127-148 (22 lines)
    ...


def get_or_generate_audio(text: str, language: str) -> bytes:
    """
    Get or generate audio data (cache-first pattern).
    
    Returns:
        Raw audio bytes (mp3)
    """
    # NEW FUNCTION - Core cache-first logic
    try:
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
        audio_data = generate_audio_for_text(text)
        
        # Store
        store_audio(text, language, audio_data)
        
        return audio_data
        
    except Exception as e:
        logger.error(f"Error getting/generating audio: {e}", exc_info=True)
        raise


def get_or_generate_audio_base64(text: str, language: str) -> str:
    """
    Get or generate audio as base64 data URI.
    
    Returns:
        Data URI string: "data:audio/mpeg;base64,..."
    """
    # NEW FUNCTION - Replaces duplicates in review_batch.py and enhanced_review.py
    try:
        audio_data = get_or_generate_audio(text, language)
        audio_base64 = base64.b64encode(audio_data).decode('utf-8')
        return f"data:audio/mpeg;base64,{audio_base64}"
    except Exception as e:
        logger.error(f"Error getting/generating audio base64: {e}", exc_info=True)
        return ""  # Return empty string on error (safe fallback)
```

**Lines**: ~110 lines total

---

### Step 1.2: Update `handlers/words.py`

**File**: `src/handlers/words.py`

**Changes**:

1. **DELETE 3 functions** (lines 127-148, 440-455, 457-493 = 75 lines):
   - `audio_exists()` → Moved to service
   - `generate_audio_for_text()` → Moved to service
   - `store_audio()` → Moved to service

2. **ADD import at top**:
```python
from services.audio_service import (
    audio_exists, 
    generate_audio_for_text, 
    store_audio,
    get_or_generate_audio
)
```

3. **UPDATE `get_audio()` endpoint** (line 495-551):
   - Replace internal logic with service call
   - Before (lines 500-528): Manual cache check + generate + store
   - After: Use `get_or_generate_audio()` service

**Before** (lines 500-528):
```python
conn = get_db_connection()
cur = conn.cursor()

# Try to get existing audio
cur.execute("""
    SELECT audio_data, content_type, created_at
    FROM audio
    WHERE text_content = %s AND language = %s
""", (text, language))

result = cur.fetchone()

if result:
    # Return existing audio
    audio_base64 = base64.b64encode(result['audio_data']).decode('utf-8')
    return jsonify({...})

# Audio doesn't exist, generate it
audio_data = generate_audio_for_text(text)
created_at = store_audio(text, language, audio_data)
```

**After**:
```python
from services.audio_service import get_or_generate_audio

try:
    # Use service (handles cache check + generation + storage)
    audio_data = get_or_generate_audio(text, language)
    
    # Get metadata for response
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT content_type, created_at
        FROM audio
        WHERE text_content = %s AND language = %s
    """, (text, language))
    
    result = cur.fetchone()
    
    audio_base64 = base64.b64encode(audio_data).decode('utf-8')
    return jsonify({
        "audio_data": audio_base64,
        "content_type": result['content_type'] if result else "audio/mpeg",
        "created_at": result['created_at'].isoformat() if result else None,
        "generated": True
    })
except Exception as e:
    logger.error(f"Error getting audio: {str(e)}", exc_info=True)
    return jsonify({"error": f"Failed to get audio: {str(e)}"}), 500
```

4. **UPDATE other usages in same file**:
   - Line 55: `generate_audio_for_text()` → Already imported, no change
   - Line 56: `store_audio()` → Already imported, no change
   - Line 158: `audio_exists()` → Already imported, no change
   - Line 172: `audio_exists()` → Already imported, no change
   - Line 258: `audio_exists()` → Already imported, no change

**Net change**: -75 lines (deleted) + 5 lines (import) + ~15 lines (simplified endpoint) = **-55 lines**

---

### Step 1.3: Update `handlers/review_batch.py`

**File**: `src/handlers/review_batch.py`

**Changes**:

1. **DELETE function** `get_or_generate_audio_base64()` (lines 21-72 = 52 lines)

2. **ADD import at top**:
```python
from services.audio_service import get_or_generate_audio_base64
```

3. **UPDATE usage** (line 362 - inside `get_review_words_batch()`):
   - No change needed - function call stays the same
   - Import now comes from service instead of local

**Net change**: -52 lines (deleted) + 1 line (import) = **-51 lines**

---

### Step 1.4: Update `handlers/enhanced_review.py`

**File**: `src/handlers/enhanced_review.py`

**Changes**:

1. **DELETE function** `get_or_generate_audio_base64()` (lines 19-71 = 53 lines)
   - This is a DUPLICATE that's already unused
   
2. **ADD import at top** (just in case it's used somewhere I missed):
```python
from services.audio_service import get_or_generate_audio_base64
```

**Net change**: -53 lines (deleted) + 1 line (import) = **-52 lines**

---

### Step 1.5: Update `services/question_generation_service.py`

**File**: `src/services/question_generation_service.py`

**Changes**:

1. **UPDATE import** (line 638):
   
**Before**:
```python
from handlers.words import collect_audio_references, audio_exists
```

**After**:
```python
from handlers.words import collect_audio_references
from services.audio_service import audio_exists
```

2. **UPDATE import** (line 634):

**Before**:
```python
from handlers.review_batch import get_or_generate_audio_base64
```

**After**:
```python
from services.audio_service import get_or_generate_audio_base64
```

**Net change**: 2 import updates (2 lines changed)

---

### Step 1.6: Update Unit Tests

**File**: `src/tests/test_unit_dictionary_service.py`

**Changes**:

1. **UPDATE imports**:

**Before**:
```python
from handlers.words import audio_exists, store_audio, generate_audio_for_text
```

**After**:
```python
from services.audio_service import audio_exists, store_audio, generate_audio_for_text
```

**Net change**: 1 import update (1 line changed)

---

## Phase 1 Summary

**Files Modified**: 6
- ✅ `src/services/audio_service.py` - NEW FILE (110 lines)
- ✅ `src/handlers/words.py` - DELETE 75 lines, simplify endpoint (-55 lines)
- ✅ `src/handlers/review_batch.py` - DELETE duplicate (-51 lines)
- ✅ `src/handlers/enhanced_review.py` - DELETE duplicate (-52 lines)
- ✅ `src/services/question_generation_service.py` - UPDATE imports (2 lines)
- ✅ `src/tests/test_unit_dictionary_service.py` - UPDATE imports (1 line)

**Net Result**: 
- Created: 1 service file with consolidated logic
- Removed: ~158 lines of duplicate code
- Added: ~110 lines of clean service code
- **Total reduction**: ~48 lines

---

## Phase 2: Naming Consistency

### Step 2.1: Rename `generate_definition_with_llm`

**File**: `src/services/definition_service.py`

**Change**: Rename function (line 208)

**Before**:
```python
def generate_definition_with_llm(word: str, learning_lang: str, native_lang: str, build_prompt_fn=None) -> Optional[Dict]:
```

**After**:
```python
def get_or_generate_definition(word: str, learning_lang: str, native_lang: str, build_prompt_fn=None) -> Optional[Dict]:
```

**Lines changed**: 1 (function signature)

---

### Step 2.2: Update Imports for `get_or_generate_definition`

**Files with imports** (5 files):

1. **`src/handlers/enhanced_review.py`** (line 81):
```python
# Before
from services.definition_service import generate_definition_with_llm

# After
from services.definition_service import get_or_generate_definition
```
   - **Line 84**: Update call `generate_definition_with_llm(` → `get_or_generate_definition(`

2. **`src/handlers/review_batch.py`** (line 110):
```python
# Before
from services.definition_service import generate_definition_with_llm

# After
from services.definition_service import get_or_generate_definition
```
   - **Line 112**: Update call `generate_definition_with_llm(` → `get_or_generate_definition(`

3. **`src/handlers/admin_questions_smart.py`** (line 14):
```python
# Before
from services.definition_service import generate_definition_with_llm

# After
from services.definition_service import get_or_generate_definition
```
   - **Line 137**: Update call `generate_definition_with_llm(` → `get_or_generate_definition(`

4. **`src/handlers/bundle_vocabulary.py`** (line 838):
```python
# Before
from services.definition_service import generate_definition_with_llm

# After
from services.definition_service import get_or_generate_definition
```
   - **Line 894**: Update call `generate_definition_with_llm(` → `get_or_generate_definition(`

5. **`src/handlers/words.py`** (line 206):
```python
# Before
from services.definition_service import generate_definition_with_llm

# After
from services.definition_service import get_or_generate_definition
```
   - **Line 226**: Update call `generate_definition_with_llm(` → `get_or_generate_definition(`

**Total changes**: 6 files × 2 lines each = **12 lines changed**

---

### Step 2.3: Rename `get_illustration`

**File**: `src/handlers/words.py`

**Change**: Rename function (line 554)

**Before**:
```python
def get_illustration():
    """Get AI illustration for a word - returns cached if exists, generates if not"""
```

**After**:
```python
def get_or_generate_illustration():
    """Get or generate AI illustration for a word (cache-first pattern)"""
```

**Lines changed**: 2 (function signature + docstring)

---

### Step 2.4: Update Route Registration for `get_or_generate_illustration`

**File**: `src/app_v3.py`

**Changes**:

1. **Update import** (line 14):
```python
# Before
from handlers.words import get_saved_words, get_word_definition_v4, get_word_details, get_audio, get_illustration, toggle_exclude_from_practice, is_word_saved

# After
from handlers.words import get_saved_words, get_word_definition_v4, get_word_details, get_audio, get_or_generate_illustration, toggle_exclude_from_practice, is_word_saved
```

2. **Update route** (line 54):
```python
# Before
v3_api.route('/illustration', methods=['GET', 'POST'])(get_illustration)

# After
v3_api.route('/illustration', methods=['GET', 'POST'])(get_or_generate_illustration)
```

**Lines changed**: 2

---

### Step 2.5: Update Compatibility Handlers

**File**: `src/handlers/compatibility.py`

**Changes**:

1. **Update import** (line 8):
```python
# Before
from handlers.words import get_word_definition_v4, get_illustration

# After
from handlers.words import get_word_definition_v4, get_or_generate_illustration
```

2. **Update `generate_illustration()` function** (line 47):
```python
# Before
return get_illustration()

# After
return get_or_generate_illustration()
```

3. **Update `get_illustration_legacy()` function** (line 56):
```python
# Before
return get_illustration()

# After
return get_or_generate_illustration()
```

**Lines changed**: 3

---

## Phase 2 Summary

**Files Modified**: 8
- ✅ `src/services/definition_service.py` - Rename function (1 line)
- ✅ `src/handlers/enhanced_review.py` - Update import + call (2 lines)
- ✅ `src/handlers/review_batch.py` - Update import + call (2 lines)
- ✅ `src/handlers/admin_questions_smart.py` - Update import + call (2 lines)
- ✅ `src/handlers/bundle_vocabulary.py` - Update import + call (2 lines)
- ✅ `src/handlers/words.py` - Rename function + update import call (3 lines)
- ✅ `src/app_v3.py` - Update import + route (2 lines)
- ✅ `src/handlers/compatibility.py` - Update import + 2 calls (3 lines)

**Total changes**: **17 lines** (all pure renames/import updates)

---

## Complete Execution Order

### Phase 1 (Audio Service)
1. ✅ Create `services/audio_service.py` with all functions
2. ✅ Update `handlers/words.py` - delete functions, add imports, simplify endpoint
3. ✅ Update `handlers/review_batch.py` - delete duplicate, add import
4. ✅ Update `handlers/enhanced_review.py` - delete duplicate, add import
5. ✅ Update `services/question_generation_service.py` - update imports
6. ✅ Update `tests/test_unit_dictionary_service.py` - update imports

### Phase 2 (Naming)
7. ✅ Rename `generate_definition_with_llm` in `services/definition_service.py`
8. ✅ Update all imports for definition function (5 files)
9. ✅ Rename `get_illustration` in `handlers/words.py`
10. ✅ Update route registration in `app_v3.py`
11. ✅ Update compatibility handlers in `handlers/compatibility.py`

### Verification
12. ✅ Run unit tests: `python -m pytest src/tests/test_unit_dictionary_service.py`
13. ✅ Rebuild backend: `docker-compose build app --no-cache`
14. ✅ Start backend: `docker-compose up -d app`
15. ✅ Test health: `curl http://localhost:5001/health`
16. ✅ Test audio endpoint: `curl http://localhost:5001/v3/audio/hello/en`
17. ✅ Test illustration endpoint: `curl http://localhost:5001/v3/illustration?word=cat&lang=en`

---

## Risk Mitigation

**Before starting**:
- ✅ Create git branch: `git checkout -b refactor/audio-service-naming`
- ✅ Commit current state: `git add . && git commit -m "Checkpoint before refactor"`

**After each phase**:
- ✅ Commit Phase 1: `git commit -m "Phase 1: Consolidate audio service"`
- ✅ Commit Phase 2: `git commit -m "Phase 2: Rename functions for consistency"`

**If issues occur**:
- ✅ Can rollback per phase: `git reset --hard HEAD~1`
- ✅ Or rollback entire refactor: `git checkout main`

---

## Final File Count

**Total files affected**: 13
- **New**: 1 file (audio_service.py)
- **Modified**: 12 files
- **Deleted**: 0 files

**Total lines changed**: ~206 lines
- **Phase 1**: -158 lines (deletions) + 110 lines (new service) = -48 net
- **Phase 2**: 17 lines (renames/imports)

**Result**: Cleaner codebase with ~48 fewer lines and consistent naming ✅
