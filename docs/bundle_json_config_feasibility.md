# JSON Config for Vocabulary Bundles - Feasibility Report

## Executive Summary

**Recommendation:** JSON config approach is FEASIBLE but offers MINIMAL improvement over current centralized config files.

**Current state:** Already using centralized config (bundle_config.py) - only 1 place to add bundles
**JSON state:** Would require 2 JSON files (iOS + backend) - 2 places to change
**Verdict:** Current approach is actually simpler than JSON for this use case.

---

## 1. Current JSON Usage Patterns

### iOS (Swift)
- **Lottie animations**: Uses `LottieView(animation: .named("animated_star"))` 
  - Loads JSON animations from Bundle.main automatically
  - 24 JSON files in resources/ directory (mostly video metadata)
- **No config JSON loading**: App doesn't currently load any config JSON files
- **Pattern exists**: JSONDecoder used extensively for API responses, not for embedded resources

### Backend (Python)
- **Video metadata**: Loads JSON files with `json.load(f)` from resources/videos/
- **No config JSON loading**: No pattern of loading config JSON at startup
- **Pattern exists**: json.loads() used for API data, not embedded config

---

## 2. Swift JSON Loading Capabilities

### Technical Implementation
```swift
// Loading embedded JSON from Bundle.main
guard let url = Bundle.main.url(forResource: "bundle_config", withExtension: "json") else {
    fatalError("Config not found")
}
let data = try Data(contentsOf: url)
let config = try JSONDecoder().decode(BundleConfig.self, from: data)
```

### Pros
- ✅ Straightforward with Codable protocol
- ✅ Type-safe with struct definitions
- ✅ JSON file embedded in app bundle at compile time
- ✅ Can validate at runtime

### Cons
- ❌ Cannot generate enums from JSON at compile time (would need build script)
- ❌ Requires manual Codable struct definition that mirrors JSON
- ❌ Runtime loading adds minimal overhead
- ❌ No compile-time validation of enum cases

---

## 3. Python JSON Loading Capabilities

### Technical Implementation
```python
# Load once at module import
import json
import os

config_path = os.path.join(os.path.dirname(__file__), 'config/bundle_config.json')
with open(config_path, 'r') as f:
    BUNDLE_CONFIG = json.load(f)

# Create lookup dictionaries
BUNDLES = {b['id']: b for b in BUNDLE_CONFIG['bundles']}
```

### Pros
- ✅ Very easy to load JSON in Python
- ✅ Can load once at import time (negligible performance impact)
- ✅ Can build runtime dictionaries for fast lookup
- ✅ Dynamic - no code generation needed

### Cons
- ❌ No compile-time type checking
- ❌ Errors only discovered at runtime
- ❌ IDE won't autocomplete bundle IDs
- ❌ Need to manually keep JSON and code in sync

---

## 4. What Would Need to Be in the JSON?

### Bundle Metadata
```json
{
  "bundles": [
    {
      "id": "TOEFL_BEGINNER",
      "display_name": "TOEFL Beginner",
      "description": "Essential vocabulary for TOEFL beginners",
      "base_test": "TOEFL",
      "level": "Beginner",
      "badge_image_name": "toefl_beginner_badge",
      "db_column": "is_toefl_beginner",
      "enabled_column": "toefl_enabled",
      "target_days_column": "toefl_target_days",
      "is_testing_only": false,
      "default_target_days": 30,
      "language_availability": ["en"],
      "order": 1
    },
    // ... 8 more bundles
  ]
}
```

### Current Python Config (47 lines)
```python
# bundle_config.py - centralized config
BUNDLE_TYPE_MAP = {
    'TOEFL_BEGINNER': ('toefl_enabled', 'toefl_target_days', 'is_toefl_beginner'),
    'TOEFL_INTERMEDIATE': ('toefl_enabled', 'toefl_target_days', 'is_toefl_intermediate'),
    # ... 7 more
}

SOURCE_TO_COLUMN_MAP = {
    'demo_bundle': 'is_demo',
    # ... mappings
}
```

### Current Swift Enum (75 lines)
```swift
enum TestType: String, Codable, CaseIterable {
    case toeflBeginner = "TOEFL_BEGINNER"
    // ... 8 cases
    
    var displayName: String {
        switch self {
        case .toeflBeginner: return "TOEFL Beginner"
        // ... 8 cases
        }
    }
    
    var baseTest: String { /* ... */ }
    var level: String? { /* ... */ }
}
```

---

## 5. What Would STILL Need Database Changes?

### Database Schema Changes (REQUIRED for new bundles)
- ✅ Add boolean column to `bundle_vocabularies` table
  - Example: `ALTER TABLE bundle_vocabularies ADD COLUMN sat_vocab BOOLEAN DEFAULT FALSE;`
- ✅ Add enabled column to `user_preferences` table
  - Example: `ALTER TABLE user_preferences ADD COLUMN sat_enabled BOOLEAN DEFAULT FALSE;`
- ✅ Add target_days column to `user_preferences` table
  - Example: `ALTER TABLE user_preferences ADD COLUMN sat_target_days INTEGER;`
- ✅ Create indexes
  - Example: `CREATE INDEX idx_bundle_vocab_sat ON bundle_vocabularies(sat_vocab) WHERE sat_vocab = TRUE;`
- ✅ Update CHECK constraints
- ✅ Run migration

### Vocabulary Data Import (REQUIRED)
- ✅ Create word list CSV/JSON
- ✅ Run import script to populate bundle_vocabularies table
- ✅ Mark words with new bundle column

**Verdict:** Database changes are UNAVOIDABLE regardless of JSON approach.

---

## 6. Comparison Analysis

### Current State: Adding a New Bundle (e.g., "SAT Vocabulary")

**Steps Required:**
1. **Backend** - Edit `bundle_config.py` (1 file, ~5 lines)
   - Add to BUNDLE_TYPE_MAP
   - Add to SOURCE_TO_COLUMN_MAP
2. **iOS** - Edit `DictionaryModels.swift` (1 file, ~10 lines)
   - Add enum case to TestType
   - Add to displayName switch
   - Add to baseTest switch
   - Add to level switch
3. **Database** - Create migration SQL (1 file)
   - Add columns, indexes, constraints
4. **Assets** - Add badge image (1 file)
5. **Data** - Import vocabulary words (1 script run)

**Total: 5 places to change**

---

### JSON Approach: Adding a New Bundle

**Steps Required:**
1. **Backend JSON** - Edit `config/bundle_config.json` (1 file, ~15 lines)
   - Add bundle object with all metadata
2. **iOS JSON** - Edit `bundle_config.json` in iOS resources (1 file, ~15 lines)
   - Add same bundle object (must match backend)
3. **iOS Code** - Generate or manually update BundleConfig struct (if schema changes)
4. **Database** - Create migration SQL (1 file) - SAME AS BEFORE
   - Add columns, indexes, constraints
5. **Assets** - Add badge image (1 file) - SAME AS BEFORE
6. **Data** - Import vocabulary words (1 script run) - SAME AS BEFORE

**Total: 6 places to change**

---

## 7. Edge Cases & Tradeoffs

### JSON Approach Advantages
- ✅ Metadata is co-located (display name, description, order, etc.)
- ✅ Non-developers could theoretically edit JSON
- ✅ Could use JSON schema for validation
- ✅ Easier to generate documentation from JSON

### JSON Approach Disadvantages
- ❌ **TWO JSON files to keep in sync** (iOS and backend)
- ❌ No compile-time enum validation in Swift
- ❌ Runtime errors if JSON malformed
- ❌ Backend loses Python type hints/autocomplete
- ❌ iOS loses Swift type safety benefits
- ❌ Still requires database migration (no benefit there)
- ❌ Still requires code changes (struct definition, loading code)
- ❌ More verbose (~15 lines vs ~5 lines per bundle)

### Current Approach Advantages
- ✅ **Centralized config in each codebase** (1 Python file, 1 Swift file)
- ✅ Compile-time validation in Swift (enum cases)
- ✅ IDE autocomplete works perfectly
- ✅ Type-safe in Swift (enum)
- ✅ Minimal code duplication
- ✅ Fast (no JSON parsing at runtime)

### Current Approach Disadvantages
- ❌ Requires developer to edit code files
- ❌ Display names scattered in switch statements
- ❌ Harder to generate docs from code

---

## 8. Alternative: Hybrid Approach

### Keep enums, Add JSON for metadata ONLY
- Python: Keep BUNDLE_TYPE_MAP as-is, add optional JSON for descriptions/docs
- Swift: Keep TestType enum, add optional JSON for display metadata
- Best of both worlds: type safety + rich metadata

### Example
```python
# bundle_config.py (keep this)
BUNDLE_TYPE_MAP = { ... }  # Type-safe mapping

# bundle_metadata.json (optional, for docs/display only)
{
  "TOEFL_BEGINNER": {
    "description": "...",
    "doc_url": "...",
    "marketing_copy": "..."
  }
}
```

---

## 9. Final Recommendation

### **DO NOT use JSON config approach**

### Reasons:
1. **Current approach is actually simpler:** 1 file per platform vs 2 JSON files to sync
2. **No reduction in database work:** Still need full migration for new bundles
3. **Loss of type safety:** Swift enum → runtime JSON loading
4. **More places to change:** 6 vs 5 (JSON files must be duplicated)
5. **Already centralized:** bundle_config.py is the single source of truth in backend
6. **Swift enum is excellent:** CaseIterable, type-safe, autocomplete, compile-time validation

### Better Alternative: Keep Current Approach, Improve Documentation
1. Keep `bundle_config.py` as single source of truth (backend)
2. Keep `TestType` enum as single source of truth (iOS)
3. Add code comments with full bundle metadata
4. Create a developer guide: "How to Add a New Bundle"
5. Consider generating docs from code (SwiftDoc, Python docstrings)

### If You Really Want JSON:
- **Use for metadata ONLY** (descriptions, marketing, docs)
- **Keep enums/config for technical mappings** (type-safe)
- **Don't duplicate** - have backend generate iOS JSON from bundle_config.py

---

## 10. Conclusion

The JSON config approach is **technically feasible** but offers **no practical benefit** for this use case. The current centralized config files (`bundle_config.py` and `TestType` enum) are:

- ✅ Simpler (1 file vs 2 JSON files)
- ✅ Type-safe (Swift enum + Python constants)
- ✅ IDE-friendly (autocomplete, refactoring)
- ✅ Already centralized
- ✅ Faster (no runtime parsing)

The only advantage of JSON (non-developer editing) is not relevant here, as:
- Database migrations still require developer
- Vocabulary imports still require developer
- Badge assets still require designer
- Testing still requires QA

**Bottom line:** Adding a new bundle is a developer task regardless of JSON. Current approach is optimal.
