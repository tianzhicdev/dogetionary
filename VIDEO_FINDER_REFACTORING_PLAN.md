# VideoFinder Refactoring Plan: Moving find_videos.py to src/services/

## Executive Summary

This document provides a detailed refactoring strategy to move the `VideoFinder` class from `scripts/find_videos.py` into `src/services/` while maintaining:
- Backward compatibility with the existing CLI script
- Clean separation between library and CLI code
- Easy importability by `src/handlers/video_search.py`
- Consistent patterns with other backend services

---

## 1. CURRENT STATE ANALYSIS

### 1.1 find_videos.py Structure

**File Size:** 1,183 lines
**Main Components:**
- Global constant: `LLM_FALLBACK_CHAIN` (lines 41-46)
- `VideoFinder` class (lines 49-1030)
  - Core methods: 20+ methods handling 3-stage pipeline
  - Initialization, word loading, ClipCafe search, LLM analysis, audio processing
  - Download, upload, and directory save functionality
- CLI code: `main()` function (lines 1085-1178)
- Argument parser and entry point (lines 1085-1182)

**Dependencies (Imports):**
```python
Standard library:
- os, sys, json, csv, base64, time, re, argparse, logging, subprocess
- pathlib.Path
- typing (List, Dict, Optional, Set)
- datetime.datetime

Third-party:
- dotenv (load_dotenv)
- requests
```

**Key Characteristics:**
- No external dependencies beyond Flask backend stack
- All required packages already in `src/requirements.txt`
- CLI-specific: argparse, sys.exit(), .env.secrets loading
- Library-specific: class initialization, method composition
- **Note:** Logging is set up for CLI at module level (lines 33-38)

### 1.2 How video_search.py Uses VideoFinder

**Import pattern (line 153):**
```python
from find_videos import VideoFinder
```

**Usage context (lines 147-188):**
- Called in background thread (`threading.Thread`)
- Single word processing: `finder.process_word(word, vocab_list)`
- Temporary directory for storage (no disk persistence)
- Environment variables: `CLIPCAFE`, `OPENAI_API_KEY`, `BASE_URL`
- Config: max_videos=20, education_min_score=0.6, context_min_score=0.6
- Mode: Upload to backend (`download_only=False`)

### 1.3 Existing Service Patterns

**Services directory has 8 existing services:**
1. `analytics_service.py` - Functions, not class-based
2. `audio_service.py` - Functions with cache-first pattern
3. `definition_service.py` - Class-based service
4. `due_words_service.py` - Functions
5. `pronunciation_service.py` - Class-based service
6. `question_generation_service.py` - Functions
7. `spaced_repetition_service.py` - Functions
8. `user_service.py` - Functions

**Patterns observed:**
- Mix of function-based and class-based services
- Class-based services: `PronunciationService`, `DefinitionService`
- Both patterns are acceptable in this codebase
- Services import from `utils.database`, `utils.llm`, `config.config`
- Logging uses standard Python logging module
- No module-level logging setup in services

---

## 2. DEPENDENCY ANALYSIS

### 2.2 Required Packages Status

All dependencies already in `/src/requirements.txt`:
- ✓ requests (used by ClipCafe search, LLM queries, uploads)
- ✓ openai (used for Whisper API, LLM queries)
- ✓ python-dotenv (for environment variable handling)
- ✓ All standard library modules

**No additional dependencies needed.**

### 2.3 Configuration Requirements

**Environment variables needed:**
- `CLIPCAFE` - ClipCafe API key
- `OPENAI_API_KEY` - OpenAI API key
- `OPEN_ROUTER_KEY` - OpenRouter key (optional fallback)
- `BASE_URL` - Backend URL (defaults to http://localhost:5001)

**These are already managed in video_search.py (lines 156-166)**

---

## 3. RECOMMENDED DIRECTORY STRUCTURE

### Option A: Single File Service (RECOMMENDED)
```
src/services/
├── video_finder.py          # VideoFinder class + LLM_FALLBACK_CHAIN
├── audio_service.py         # (existing)
├── pronunciation_service.py # (existing)
└── ... (other services)

scripts/
├── find_videos.py          # CLI wrapper (simplified, imports from services)
└── ... (other scripts)
```

**Rationale:**
- Matches existing codebase pattern (single service = single file)
- VideoFinder is self-contained, doesn't need sub-modules
- Easier to import in handlers: `from services.video_finder import VideoFinder`
- Clear separation: service logic vs CLI orchestration

### Option B: Package-Based Service (Alternative)
```
src/services/video_finder/
├── __init__.py              # Exports VideoFinder, LLM_FALLBACK_CHAIN
├── finder.py                # VideoFinder class
├── llm_analysis.py          # LLM prompt building, querying
├── audio_processing.py      # Whisper, audio extraction
└── upload.py                # Backend upload, directory save

scripts/
└── find_videos.py          # CLI wrapper
```

**Rationale:** Better separation for future growth, but adds complexity now.

**Recommendation:** Go with **Option A** - keep it simple per CLAUDE.md principle 1.

---

## 4. REFACTORING IMPLEMENTATION

### 4.1 Phase 1: Create the Service Module

**Step 1: Create `/src/services/video_finder.py`**

**What to move:**
- Lines 1-46: Module docstring + LLM_FALLBACK_CHAIN constant
- Lines 49-1030: VideoFinder class (all methods intact)

**What to remove:**
- Lines 32-38: CLI logging setup (replace with backend logging pattern)
- Lines 16-30: CLI-specific imports (keep only needed ones)

**Module docstring (update from original):**
```python
"""
Video Finder Service - 3-Stage video discovery and upload pipeline

Provides VideoFinder class for discovering videos via ClipCafe API,
analyzing with LLM, and uploading to backend.

Stage 1: Search ClipCafe for video metadata
Stage 2: Candidate selection using metadata transcript + LLM
Stage 3: Audio verification using Whisper API + final LLM analysis

Features:
- Idempotent: Caches all intermediate results
- Parameterized: Storage dir, API domain, config adjustable
- Quality filtering: Whisper audio transcript + dual LLM analysis
- Batch processing: Efficient parallel operations
"""
```

**Imports to keep:**
```python
import os
import json
import csv
import base64
import time
import re
import logging
import subprocess
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime
import requests
```

**Logging setup (new pattern for service):**
```python
logger = logging.getLogger(__name__)
# No logging.basicConfig() - let Flask app configure it
```

**LLM_FALLBACK_CHAIN constant:** Keep as-is (lines 41-46)

**VideoFinder class:** Keep all methods intact (49-1030)

**Key changes within VideoFinder:**
1. Line 29: `self._build_llm_prompt` already uses logger
2. Line 335: `_query_llm` uses logger
3. No changes needed to class methods - already use logger!

---

### 4.2 Phase 2: Update video_search.py Handler

**File:** `/src/handlers/video_search.py`

**Change (lines 15-17, 153):**

From:
```python
# Add scripts directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'scripts'))

# Later...
from find_videos import VideoFinder
```

To:
```python
from services.video_finder import VideoFinder
```

**Remove:** Lines 15-17 (no longer needed)

**That's it!** No other changes needed in video_search.py

---

### 4.3 Phase 3: Update scripts/find_videos.py

**Keep:** CLI functionality, argument parsing, environment variable loading

**New imports:**
```python
import os
import sys
import argparse
import logging
from pathlib import Path
from dotenv import load_dotenv

# Add src directory to path (allows importing service)
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from services.video_finder import VideoFinder

# Setup logging for CLI
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)
```

**Keep:** Lines 1085-1182 (`main()` function and entry point)

**Updated main() function usage:**
```python
# Everything else stays the same!
# finder = VideoFinder(...)
# finder.run(words=words, source_name=...)
```

**Result:** ~100 lines instead of 1,183

---

## 5. CODE ORGANIZATION SUMMARY

### Before Refactoring
```
scripts/find_videos.py        (1,183 lines - service + CLI mixed)
src/handlers/video_search.py  (188 lines - imports from scripts)
src/services/                 (8 existing services, no video finder)
```

### After Refactoring
```
src/services/video_finder.py  (1,035 lines - pure service)
scripts/find_videos.py        (~100 lines - CLI wrapper only)
src/handlers/video_search.py  (185 lines - imports from services)
```

---

## 6. IMPORT STRATEGY

### For Backend Code (handlers, workers, etc.)
```python
from services.video_finder import VideoFinder, LLM_FALLBACK_CHAIN
```

### For CLI Scripts
```python
# Add src to path first
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from services.video_finder import VideoFinder
```

### Why This Works
1. When running from `src/app.py` context, services are automatically importable
2. When running `scripts/find_videos.py`, we explicitly add src to path
3. No circular dependencies (services don't import from handlers)
4. No need to install as a package - relative imports work

---

## 7. CONFIGURATION MANAGEMENT

### Current Approach (No Changes Needed!)
VideoFinder already accepts all config via constructor:
```python
VideoFinder(
    storage_dir=temp_dir,
    backend_url=backend_url,
    word_list_path=None,
    clipcafe_api_key=clipcafe_api_key,
    openai_api_key=openai_api_key,
    max_videos_per_word=20,
    education_min_score=0.6,
    context_min_score=0.6,
    download_only=False
)
```

**API keys sourced from environment:**
- video_search.py: `os.getenv('CLIPCAFE')`, `os.getenv('OPENAI_API_KEY')`
- scripts/find_videos.py: Same pattern via `.env.secrets`

**No config file needed** - follows existing backend pattern

---

## 8. TESTING & INTEGRATION

### Unit Tests
**Location:** Create `/src/tests/test_video_finder.py`

**What to test:**
- VideoFinder initialization
- Word loading from CSV
- ClipCafe search (mock API)
- LLM analysis (mock LLM)
- Audio transcript extraction (mock)
- Backend upload (mock)

**Note:** Don't move existing tests yet - video_search integration tests can stay as-is

### Integration Tests
**Existing:** `scripts/integration_test.py` (if exists)

**No changes needed** - continue to import from scripts after refactoring

### Manual Testing
```bash
# Test service import
python3 -c "import sys; sys.path.insert(0, 'src'); from services.video_finder import VideoFinder; print('OK')"

# Test handler import
cd src && python3 -c "from services.video_finder import VideoFinder; print('OK')"

# Test CLI script
python3 scripts/find_videos.py --csv test_words.csv --storage-dir /tmp/test
```

---

## 9. MIGRATION STEPS (EXECUTION ORDER)

### Step 1: Create Service File (No Breaking Changes)
```bash
# Create new file
cp /Users/biubiu/projects/dogetionary/scripts/find_videos.py \
   /Users/biubiu/projects/dogetionary/src/services/video_finder.py

# Edit /src/services/video_finder.py:
# - Remove CLI-specific code (main(), argparse setup)
# - Remove sys.path.insert, sys.exit() calls
# - Keep VideoFinder class and LLM_FALLBACK_CHAIN
# - Update logging setup to remove basicConfig()
```

**Test:** `python3 -c "from src.services.video_finder import VideoFinder"`

### Step 2: Update video_search.py Handler
```bash
# Edit /src/handlers/video_search.py:
# - Change line 17: Remove sys.path.insert
# - Change line 153: Update import from `find_videos` to `services.video_finder`
```

**Test:** Run backend, check that video search handler loads without errors

### Step 3: Simplify scripts/find_videos.py
```bash
# Edit /scripts/find_videos.py:
# - Keep docstring and imports
# - Add sys.path.insert for src directory
# - Add import from services.video_finder
# - Keep main() function and entry point
# - Delete VideoFinder class (now 1000+ lines)
```

**Test:** `python3 scripts/find_videos.py --help` still works

### Step 4: Verify Backward Compatibility
```bash
# Test 1: CLI still works with CSV
python3 scripts/find_videos.py --csv test_words.csv

# Test 2: CLI with bundle
python3 scripts/find_videos.py --bundle toefl_beginner

# Test 3: Handler import works
cd src && python3 -c "from handlers.video_search import trigger_video_search"

# Test 4: Service import from anywhere
python3 -c "import sys; sys.path.insert(0, 'src'); from services.video_finder import VideoFinder, LLM_FALLBACK_CHAIN"
```

### Step 5: Create Tests
```bash
# Create /src/tests/test_video_finder.py
# Add unit tests for VideoFinder class
# Include mocked API calls
```

### Step 6: Update Documentation
```bash
# Update FIND_VIDEOS_README.md with new structure
# Update imports in any related docs
```

---

## 10. BACKWARD COMPATIBILITY MATRIX

| Component | Before | After | Compatible |
|-----------|--------|-------|------------|
| CLI: `scripts/find_videos.py` | Direct VideoFinder | Imports from service | ✓ Yes |
| Handler: `video_search.py` | `sys.path + find_videos` | Direct service import | ✓ Yes |
| API: Background jobs | Instance creation unchanged | Instance creation unchanged | ✓ Yes |
| Config: Environment vars | Same | Same | ✓ Yes |
| Test: Integration tests | Import from scripts | Import from service (update) | ~ Update path |

**No breaking changes** if migration steps are followed correctly.

---

## 11. POTENTIAL ISSUES & MITIGATION

### Issue 1: Circular Imports
**Risk:** If service imports from handlers/utils that import back
**Mitigation:** services/video_finder.py only imports from utils/config, not handlers
**Verification:** 
```bash
python3 -c "import src.services.video_finder" # Should work standalone
```

### Issue 2: Logging Configuration
**Risk:** Flask app's logging setup might not apply to service
**Current Status:** Already OK - no logging.basicConfig() in services/audio_service.py
**Verification:** Check existing services don't configure logging

### Issue 3: Path Issues in sys.path.insert
**Risk:** Relative path in scripts/find_videos.py might break if called from different cwd
**Mitigation:** Use `os.path.dirname(__file__)` - already done correctly
```python
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))
# This resolves relative to find_videos.py location
```

### Issue 4: Temporary Files in Background Thread
**Risk:** Thread safety with tempfile.TemporaryDirectory()
**Current Status:** Already handled correctly - context manager in video_search.py
**No change needed**

---

## 12. IMPLEMENTATION CHECKLIST

- [ ] Create `/src/services/video_finder.py` with VideoFinder class
- [ ] Test: `from src.services.video_finder import VideoFinder` works
- [ ] Update `/src/handlers/video_search.py` import (1 line change)
- [ ] Test: Handler still loads without errors
- [ ] Simplify `/scripts/find_videos.py` (keep CLI, add import)
- [ ] Test: `python3 scripts/find_videos.py --help` works
- [ ] Test: CLI CSV mode works
- [ ] Test: CLI bundle mode works
- [ ] Test: Background thread video search works (integration test)
- [ ] Create `/src/tests/test_video_finder.py` with unit tests
- [ ] Verify no other scripts import find_videos.py (check entire codebase)
- [ ] Update `FIND_VIDEOS_README.md` with new structure
- [ ] Commit changes

---

## 13. DETAILED CODE DIFFS

### File: `/src/services/video_finder.py` (NEW)

**Lines to copy from scripts/find_videos.py:**
- 1-10: Docstring (update module name)
- 40-46: LLM_FALLBACK_CHAIN constant
- 49-1030: Entire VideoFinder class

**Changes within copied code:**
1. Remove lines 16-38 (imports and logging setup) - DONE in next section
2. Update imports (see below)
3. Keep all method implementations identical

**Final imports for video_finder.py:**
```python
"""
Video Finder Service - 3-Stage video discovery and upload pipeline
...
"""

import os
import json
import csv
import base64
import time
import re
import logging
import subprocess
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime
import requests

logger = logging.getLogger(__name__)

# LLM fallback chain for video analysis
LLM_FALLBACK_CHAIN = [
    "google/gemini-2.0-flash-lite-001",
    "deepseek/deepseek-chat-v3.1",
    "qwen/qwen-2.5-7b-instruct",
    "openai/gpt-4o-mini"
]

class VideoFinder:
    # ... entire class unchanged ...
```

### File: `/src/handlers/video_search.py` (MODIFIED)

**Diff:**
```diff
- # Add scripts directory to path
- sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'scripts'))

  from utils.database import get_db_connection, db_fetch_one, db_fetch_all
  from services.question_generation_service import generate_video_mc_question
+ from services.video_finder import VideoFinder

  # ... rest of file unchanged until run_video_finder_for_word ...

  def run_video_finder_for_word(word: str, lang: str):
      try:
-         from find_videos import VideoFinder
          
          # Get API keys from environment
          clipcafe_api_key = os.getenv('CLIPCAFE')
```

### File: `/scripts/find_videos.py` (SIMPLIFIED)

**New content (simplified from 1,183 lines to ~100 lines):**
```python
#!/usr/bin/env python3
"""
find_videos.py - CLI wrapper for video discovery and upload pipeline

Usage:
  python3 find_videos.py --csv words.csv --backend-url http://localhost:5001
  python3 find_videos.py --bundle toefl_beginner --max-videos 50
"""

import os
import sys
import argparse
import logging
from pathlib import Path
from dotenv import load_dotenv

# Add src directory to path to import services
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from services.video_finder import VideoFinder

# Setup logging for CLI
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


def main():
    parser = argparse.ArgumentParser(
        description='Find videos for vocabulary words and upload to backend',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    # [Keep entire argparse section from original lines 1092-1140]
    word_source = parser.add_mutually_exclusive_group(required=True)
    word_source.add_argument(
        '--csv',
        help='Path to CSV file with word list'
    )
    word_source.add_argument(
        '--bundle',
        help='Bundle name to fetch words from (e.g., toefl_beginner, ielts_advanced)'
    )

    parser.add_argument(
        '--storage-dir',
        default='/Volumes/databank/shortfilms',
        help='Base directory for caching (default: /Volumes/databank/shortfilms)'
    )

    parser.add_argument(
        '--backend-url',
        default='http://localhost:5001',
        help='Backend API URL (default: http://localhost:5001)'
    )

    parser.add_argument(
        '--max-videos',
        type=int,
        default=100,
        help='Max videos to fetch per word (default: 100)'
    )

    parser.add_argument(
        '--education-min-score',
        type=float,
        default=0.6,
        help='Minimum education score - how well video illustrates word meaning (default: 0.6)'
    )

    parser.add_argument(
        '--context-min-score',
        type=float,
        default=0.6,
        help='Minimum context score - how well scene stands alone (default: 0.6)'
    )

    parser.add_argument(
        '--download-only',
        action='store_true',
        help='Download and process videos without uploading (saves to storage directory)'
    )

    args = parser.parse_args()

    # Load secrets from .env.secrets
    env_path = Path(__file__).parent.parent / 'src' / '.env.secrets'
    if env_path.exists():
        load_dotenv(env_path)
        logger.info(f"Loaded secrets from {env_path}")
    else:
        logger.warning(f"Secrets file not found: {env_path}")

    clipcafe_api_key = os.getenv('CLIPCAFE')
    openai_api_key = os.getenv('OPENAI_API_KEY')

    if not clipcafe_api_key or not openai_api_key:
        logger.error("Missing API keys in .env.secrets (CLIPCAFE, OPENAI_API_KEY)")
        sys.exit(1)

    # Create pipeline
    finder = VideoFinder(
        storage_dir=args.storage_dir,
        backend_url=args.backend_url,
        word_list_path=args.csv if args.csv else None,
        clipcafe_api_key=clipcafe_api_key,
        openai_api_key=openai_api_key,
        max_videos_per_word=args.max_videos,
        education_min_score=args.education_min_score,
        context_min_score=args.context_min_score,
        download_only=args.download_only
    )

    # Get words from either bundle or CSV
    if args.bundle:
        words = finder.fetch_bundle_words(args.bundle)
    else:
        words = finder.load_words()

    # Run pipeline with words
    finder.run(words=words, source_name=args.bundle or args.csv)


if __name__ == '__main__':
    main()
```

---

## 14. RISKS & MITIGATION STRATEGIES

### Risk 1: Breaking Video Search Handler
**Impact:** Medium - Handler won't start if import fails
**Mitigation:** 
- Test import before committing: `python3 -c "from src.services.video_finder import VideoFinder"`
- Run Flask app startup check: `python3 src/app.py` (check logs)
**Timeline:** Immediately after creating service file

### Risk 2: CLI Script Broken by Import Path
**Impact:** Medium - CLI won't run if sys.path incorrect
**Mitigation:**
- Test: `python3 scripts/find_videos.py --help`
- Verify from different directory: `cd /tmp && python3 /path/to/find_videos.py --help`
**Timeline:** After updating scripts/find_videos.py

### Risk 3: Existing Integration Tests Fail
**Impact:** Low - Tests import from scripts, service file supports it
**Mitigation:**
- No changes needed if tests import from scripts
- Alternative: Update test imports to use service directly
**Timeline:** During test execution

### Risk 4: Multiple Imports of Same Code
**Impact:** Low - No actual duplication, just logical imports
**Mitigation:** 
- After refactoring, only one source of truth (service file)
- CLI wrapper has zero duplicate code
**Timeline:** Complete after Phase 3

---

## 15. SUCCESS CRITERIA

Migration is successful when:

1. ✓ `src/services/video_finder.py` exists with VideoFinder class
2. ✓ `from services.video_finder import VideoFinder` works from src/
3. ✓ `python3 scripts/find_videos.py --help` works
4. ✓ `python3 scripts/find_videos.py --csv test.csv` executes (with test data)
5. ✓ Flask backend starts without import errors
6. ✓ `src/handlers/video_search.py` handler imports VideoFinder correctly
7. ✓ Background thread video search works (manual test with trigger_video_search endpoint)
8. ✓ Integration tests pass (if they exist)
9. ✓ All existing CLI options still work with new structure

---

## 16. POST-MIGRATION OPPORTUNITIES

After successful refactoring:

1. **Add unit tests:** Create `/src/tests/test_video_finder.py`
2. **Add async support:** Convert VideoFinder to async if needed for high concurrency
3. **Extract helper modules:** If VideoFinder grows, split into sub-modules:
   - `services/video_finder/llm.py` - LLM analysis
   - `services/video_finder/audio.py` - Audio processing
   - `services/video_finder/upload.py` - Backend upload logic
4. **Add configuration:** Move hardcoded params to config file if used elsewhere
5. **Error handling:** Add custom exceptions for VideoFinder failures
6. **Monitoring:** Add metrics/logging hooks for observability

---

## 17. SUMMARY DECISION MATRIX

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Location** | `src/services/video_finder.py` | Matches backend structure, easy imports |
| **Format** | Single file service | Keeps it simple (CLAUDE.md principle 1) |
| **CLI** | Lightweight wrapper in scripts/ | Maintains backward compatibility |
| **Imports** | Direct from services (handlers), sys.path (scripts) | Works with existing architecture |
| **Config** | Constructor params + env vars | No changes needed, already working |
| **Tests** | New unit tests in src/tests/ | Service layer should be testable |
| **Dependencies** | No new packages | Everything already in requirements.txt |

---

## 18. FILES TO MODIFY & CREATE

### Create (1 new file)
- [ ] `/src/services/video_finder.py` - VideoFinder service (copy + edit from scripts/find_videos.py)

### Modify (2 files)
- [ ] `/src/handlers/video_search.py` - Update import (1-2 lines)
- [ ] `/scripts/find_videos.py` - Simplify to CLI wrapper (delete 1000+ lines, add import)

### Optional Create (1 test file)
- [ ] `/src/tests/test_video_finder.py` - Unit tests for VideoFinder

### Update (Documentation)
- [ ] `/scripts/FIND_VIDEOS_README.md` - Document new structure if exists

---

## QUICK REFERENCE: Before/After Import Examples

### Before Refactoring
```python
# In src/handlers/video_search.py:
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'scripts'))
from find_videos import VideoFinder

# In scripts/find_videos.py:
# All 1,183 lines - service + CLI mixed
```

### After Refactoring
```python
# In src/handlers/video_search.py:
from services.video_finder import VideoFinder

# In scripts/find_videos.py:
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))
from services.video_finder import VideoFinder
```

---
