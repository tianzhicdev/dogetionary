# Complete Migration Plan: TIANZ → DEMO & Test → Bundle

## Overview
This migration combines three tasks:
1. Rename "TIANZ" → "DEMO" throughout codebase
2. Add two new vocabulary bundles (Business English, Everyday English)
3. Rename "test" → "bundle" terminology
4. Import 4,042 words from vocabulary_merged.csv

**Estimated Time**: 60-90 minutes
**Database Downtime**: ~3 minutes
**Rollback Available**: Yes (via PostgreSQL backup)

---

## Pre-Migration Checklist

### ✅ Backup Database
```bash
docker exec dogetionary-postgres-1 pg_dump -U postgres dogetionary > backup_pre_bundle_migration_$(date +%Y%m%d_%H%M%S).sql
```

### ✅ Verify No Active Users
```bash
docker exec dogetionary-postgres-1 psql -U postgres dogetionary -c "SELECT COUNT(*) FROM user_preferences;"
```

### ✅ Stop iOS App
- Close all Xcode instances
- Kill running simulators

### ✅ Placeholder Badge Images
Will copy existing badge PNGs to create placeholders for:
- `business_english_badge.imageset`
- `everyday_english_badge.imageset`

---

## PHASE 1: DATABASE MIGRATION (10 min)

### File to Create: `/db/migration_009_bundle_vocabulary.sql`

```sql
-- Migration 009: Rename TIANZ → DEMO, Test → Bundle, Add New Bundles
-- Date: 2025-12-14
-- Description: Complete refactoring of vocabulary bundle system

BEGIN;

-- ============================================================================
-- STEP 1: RENAME TABLE test_vocabularies → bundle_vocabularies
-- ============================================================================

ALTER TABLE test_vocabularies RENAME TO bundle_vocabularies;

-- Rename indexes
ALTER INDEX idx_test_vocab_word RENAME TO idx_bundle_vocab_word;
ALTER INDEX idx_test_vocab_language RENAME TO idx_bundle_vocab_language;
ALTER INDEX idx_test_vocab_toefl RENAME TO idx_bundle_vocab_toefl;
ALTER INDEX idx_test_vocab_ielts RENAME TO idx_bundle_vocab_ielts;
ALTER INDEX idx_test_vocab_tianz RENAME TO idx_bundle_vocab_demo;

-- ============================================================================
-- STEP 2: RENAME COLUMNS IN bundle_vocabularies
-- ============================================================================

-- Rename is_tianz → is_demo
ALTER TABLE bundle_vocabularies RENAME COLUMN is_tianz TO is_demo;

-- Add new bundle columns
ALTER TABLE bundle_vocabularies ADD COLUMN business_english BOOLEAN DEFAULT FALSE;
ALTER TABLE bundle_vocabularies ADD COLUMN everyday_english BOOLEAN DEFAULT FALSE;

-- Create indexes for new columns
CREATE INDEX idx_bundle_vocab_business_english ON bundle_vocabularies(business_english) WHERE business_english = TRUE;
CREATE INDEX idx_bundle_vocab_everyday_english ON bundle_vocabularies(everyday_english) WHERE everyday_english = TRUE;

-- ============================================================================
-- STEP 3: RENAME COLUMNS IN user_preferences
-- ============================================================================

ALTER TABLE user_preferences RENAME COLUMN tianz_enabled TO demo_enabled;
ALTER TABLE user_preferences RENAME COLUMN tianz_target_days TO demo_target_days;

-- Add new bundle preference columns
ALTER TABLE user_preferences ADD COLUMN business_english_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE user_preferences ADD COLUMN business_english_target_days INTEGER;
ALTER TABLE user_preferences ADD COLUMN everyday_english_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE user_preferences ADD COLUMN everyday_english_target_days INTEGER;

-- Update CHECK constraint for user_preferences
ALTER TABLE user_preferences DROP CONSTRAINT IF EXISTS user_preferences_check;
ALTER TABLE user_preferences ADD CONSTRAINT user_preferences_check CHECK (
    (toefl_enabled = FALSE OR toefl_target_days IS NOT NULL) AND
    (ielts_enabled = FALSE OR ielts_target_days IS NOT NULL) AND
    (demo_enabled = FALSE OR demo_target_days IS NOT NULL) AND
    (business_english_enabled = FALSE OR business_english_target_days IS NOT NULL) AND
    (everyday_english_enabled = FALSE OR everyday_english_target_days IS NOT NULL)
);

-- Create index for demo_enabled
DROP INDEX IF EXISTS idx_user_pref_tianz_enabled;
CREATE INDEX idx_user_pref_demo_enabled ON user_preferences(demo_enabled) WHERE demo_enabled = TRUE;

-- Create indexes for new bundle preferences
CREATE INDEX idx_user_pref_business_english_enabled ON user_preferences(business_english_enabled) WHERE business_english_enabled = TRUE;
CREATE INDEX idx_user_pref_everyday_english_enabled ON user_preferences(everyday_english_enabled) WHERE everyday_english_enabled = TRUE;

-- ============================================================================
-- STEP 4: UPDATE study_schedules TABLE
-- ============================================================================

-- Update CHECK constraint for bundle_type
ALTER TABLE study_schedules DROP CONSTRAINT IF EXISTS study_schedules_bundle_type_check;
ALTER TABLE study_schedules ADD CONSTRAINT study_schedules_bundle_type_check CHECK (
    bundle_type IN ('TOEFL', 'IELTS', 'DEMO', 'BUSINESS_ENGLISH', 'EVERYDAY_ENGLISH')
);

-- Rename existing TIANZ schedules to DEMO
UPDATE study_schedules SET bundle_type = 'DEMO' WHERE bundle_type = 'TIANZ';

-- Rename test_type column to bundle_type (if it exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='study_schedules' AND column_name='test_type') THEN
        ALTER TABLE study_schedules RENAME COLUMN test_type TO bundle_type;
    END IF;
END$$;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Verify table rename
SELECT 'bundle_vocabularies table exists:' as check, EXISTS (
    SELECT FROM pg_tables WHERE tablename = 'bundle_vocabularies'
) as result;

-- Verify column renames
SELECT 'demo_enabled column exists:' as check, EXISTS (
    SELECT FROM information_schema.columns WHERE table_name = 'user_preferences' AND column_name = 'demo_enabled'
) as result;

-- Count existing bundle words
SELECT
    COUNT(*) FILTER (WHERE is_toefl_beginner) as toefl_beginner,
    COUNT(*) FILTER (WHERE is_toefl_intermediate) as toefl_intermediate,
    COUNT(*) FILTER (WHERE is_toefl_advanced) as toefl_advanced,
    COUNT(*) FILTER (WHERE is_ielts_beginner) as ielts_beginner,
    COUNT(*) FILTER (WHERE is_ielts_intermediate) as ielts_intermediate,
    COUNT(*) FILTER (WHERE is_ielts_advanced) as ielts_advanced,
    COUNT(*) FILTER (WHERE is_demo) as demo,
    COUNT(*) FILTER (WHERE business_english) as business_english,
    COUNT(*) FILTER (WHERE everyday_english) as everyday_english
FROM bundle_vocabularies;

COMMIT;
```

### Execution Steps:

```bash
# 1. Copy migration file to db directory
cat > /Users/biubiu/projects/dogetionary/db/migration_009_bundle_vocabulary.sql

# 2. Stop backend (to prevent connections during migration)
docker-compose stop app

# 3. Run migration
docker exec -i dogetionary-postgres-1 psql -U postgres dogetionary < /Users/biubiu/projects/dogetionary/db/migration_009_bundle_vocabulary.sql

# 4. Verify migration
docker exec dogetionary-postgres-1 psql -U postgres dogetionary -c "\\dt bundle_vocabularies"
docker exec dogetionary-postgres-1 psql -U postgres dogetionary -c "\\d user_preferences" | grep demo

# 5. Restart backend
docker-compose start app
```

---

## PHASE 2: BACKEND PYTHON CODE (20 min)

### 2.1 Create Bundle Configuration File

**File**: `/src/config/bundle_config.py`

```python
"""
Centralized Bundle Configuration
Maps bundle types to database columns and user preferences.
"""

# Bundle type to database column mapping
BUNDLE_TYPE_MAP = {
    'TOEFL_BEGINNER': ('toefl_enabled', 'toefl_target_days', 'is_toefl_beginner'),
    'TOEFL_INTERMEDIATE': ('toefl_enabled', 'toefl_target_days', 'is_toefl_intermediate'),
    'TOEFL_ADVANCED': ('toefl_enabled', 'toefl_target_days', 'is_toefl_advanced'),
    'IELTS_BEGINNER': ('ielts_enabled', 'ielts_target_days', 'is_ielts_beginner'),
    'IELTS_INTERMEDIATE': ('ielts_enabled', 'ielts_target_days', 'is_ielts_intermediate'),
    'IELTS_ADVANCED': ('ielts_enabled', 'ielts_target_days', 'is_ielts_advanced'),
    'DEMO': ('demo_enabled', 'demo_target_days', 'is_demo'),
    'BUSINESS_ENGLISH': ('business_english_enabled', 'business_english_target_days', 'business_english'),
    'EVERYDAY_ENGLISH': ('everyday_english_enabled', 'everyday_english_target_days', 'everyday_english'),
}

# All bundle enable columns
ALL_BUNDLE_ENABLE_COLUMNS = [
    'toefl_enabled', 'ielts_enabled', 'demo_enabled',
    'business_english_enabled', 'everyday_english_enabled'
]

# All bundle vocabulary columns
ALL_BUNDLE_VOCAB_COLUMNS = [
    'is_toefl_beginner', 'is_toefl_intermediate', 'is_toefl_advanced',
    'is_ielts_beginner', 'is_ielts_intermediate', 'is_ielts_advanced',
    'is_demo', 'business_english', 'everyday_english'
]

# Source name mapping (for API compatibility)
SOURCE_TO_COLUMN_MAP = {
    'demo_bundle': 'is_demo',
    'demo': 'is_demo',
    'business_english': 'business_english',
    'everyday_english': 'everyday_english',
    'toefl': 'is_toefl_beginner',  # Default to beginner
    'ielts': 'is_ielts_beginner',
}
```

### 2.2 Files to Update (26 files)

#### Critical Handler Files:

**1. `/src/handlers/test_vocabulary.py` → `/src/handlers/bundle_vocabulary.py`**
- Line 2: Update docstring "TOEFL/IELTS/DEMO preparation features"
- Line 30: Update `BUNDLE_TYPE_MAP` (replace TIANZ → DEMO)
- Line 40: Update `ALL_BUNDLE_ENABLE_COLUMNS` (tianz_enabled → demo_enabled)
- Lines 44-200: Replace all `tianz_enabled` → `demo_enabled`
- Lines 44-200: Replace all `tianz_target_days` → `demo_target_days`
- Lines 230-290: Replace `is_tianz` → `is_demo`
- Lines 260-290: Add business_english and everyday_english cases
- Add imports: `from config.bundle_config import BUNDLE_TYPE_MAP, ALL_BUNDLE_ENABLE_COLUMNS`

**2. `/src/handlers/users.py`**
- Lines 44-45: `tianz_enabled` → `demo_enabled`, `tianz_target_days` → `demo_target_days`
- Line 80: `result['tianz_enabled']` → `result['demo_enabled']`
- Line 82: `result['tianz_target_days']` → `result['demo_target_days']`

**3. `/src/handlers/schedule.py`**
- Replace all `tianz_enabled` → `demo_enabled`
- Add business_english and everyday_english cases

**4. `/src/handlers/achievements.py`**
- Line 120: `'is_tianz'` → `'is_demo'`
- Line 122: `'tianz_enabled'` → `'demo_enabled'`
- Add business_english and everyday_english mappings

**5. `/src/handlers/admin_questions.py`**
- Line 30: Comment `"source": "demo_bundle"`
- Line 65: Update source options
- Line 130: `'demo_bundle': 'is_demo'`, `'demo': 'is_demo'`
- Add business_english and everyday_english

**6. `/src/handlers/admin_questions_smart.py`**
- Same as admin_questions.py

**7. `/src/handlers/practice_status.py`**
- Replace `tianz_enabled` → `demo_enabled`

**8. `/src/handlers/review_batch.py`**
- Replace `tianz_enabled` → `demo_enabled`

**9. `/src/handlers/words.py`**
- Replace `test_vocabularies` → `bundle_vocabularies`

**10. `/src/services/schedule_service.py`**
- Line 180: `'DEMO': 'is_demo'`
- Line 215: `(%s = 'DEMO' AND bv.is_demo = TRUE)`
- Replace all `test_vocabularies` → `bundle_vocabularies` (use alias `bv`)

**11. `/src/workers/test_vocabulary_worker.py` → `/src/workers/bundle_vocabulary_worker.py`**
- Replace all `tianz_enabled` → `demo_enabled`
- Replace all `is_tianz` → `is_demo`
- Replace `test_vocabularies` → `bundle_vocabularies`

#### Script Files:

**12. `/scripts/import_test_vocabularies.py` → `/scripts/import_bundle_vocabularies.py`**
- Line 97: `demo_file = project_root / 'resources' / 'demo.csv'`
- Lines 108-137: Replace TIANZ → DEMO throughout
- Line 150: `is_demo = word in demo_words`
- Lines 154-160: `is_demo` in SQL

**13. `/scripts/prepopulate_local.py`**
- Lines 50-60: Update examples with `demo_bundle`
- Line 75: Update help text and choices

**14. `/scripts/prepopulate_questions.py`**
- Lines 30-50: Replace `tianz_test` → `demo_bundle`
- Line 120: Update choices

**15. `/scripts/prepopulate_smart.py`**
- Lines 30-50: Replace `tianz_test` → `demo_bundle`
- Line 140: Update choices

#### Other Backend Files:

**16. `/src/app.py`** - Update imports (test_vocabulary → bundle_vocabulary)
**17. `/src/app_v3.py`** - Update route references if any
**18. `/db/init.sql`** - Already covered in Phase 1

### Global Search/Replace Commands:

```bash
# In src/ directory, replace all occurrences
cd /Users/biubiu/projects/dogetionary/src

# Replace tianz_enabled → demo_enabled
find . -name "*.py" -exec sed -i '' 's/tianz_enabled/demo_enabled/g' {} +

# Replace tianz_target_days → demo_target_days
find . -name "*.py" -exec sed -i '' 's/tianz_target_days/demo_target_days/g' {} +

# Replace is_tianz → is_demo
find . -name "*.py" -exec sed -i '' 's/is_tianz/is_demo/g' {} +

# Replace "TIANZ" → "DEMO" (string literals)
find . -name "*.py" -exec sed -i '' "s/'TIANZ'/'DEMO'/g" {} +
find . -name "*.py" -exec sed -i '' 's/"TIANZ"/"DEMO"/g' {} +

# Replace test_vocabularies → bundle_vocabularies
find . -name "*.py" -exec sed -i '' 's/test_vocabularies/bundle_vocabularies/g' {} +

# Rename files
mv handlers/test_vocabulary.py handlers/bundle_vocabulary.py
mv workers/test_vocabulary_worker.py workers/bundle_vocabulary_worker.py
mv scripts/import_test_vocabularies.py scripts/import_bundle_vocabularies.py
```

---

## PHASE 3: iOS SWIFT CODE (15 min)

### 3.1 Create Bundle Configuration File

**File**: `/ios/dogetionary/dogetionary/Core/Config/BundleConfig.swift`

```swift
//
//  BundleConfig.swift
//  dogetionary
//
//  Bundle type definitions and configurations
//

import Foundation
import SwiftUI

enum BundleType: String, Codable, CaseIterable {
    case toeflBeginner = "TOEFL_BEGINNER"
    case toeflIntermediate = "TOEFL_INTERMEDIATE"
    case toeflAdvanced = "TOEFL_ADVANCED"
    case ieltsBeginner = "IELTS_BEGINNER"
    case ieltsIntermediate = "IELTS_INTERMEDIATE"
    case ieltsAdvanced = "IELTS_ADVANCED"
    case demo = "DEMO"
    case businessEnglish = "BUSINESS_ENGLISH"
    case everydayEnglish = "EVERYDAY_ENGLISH"

    var displayName: String {
        switch self {
        case .toeflBeginner: return "TOEFL Beginner"
        case .toeflIntermediate: return "TOEFL Intermediate"
        case .toeflAdvanced: return "TOEFL Advanced"
        case .ieltsBeginner: return "IELTS Beginner"
        case .ieltsIntermediate: return "IELTS Intermediate"
        case .ieltsAdvanced: return "IELTS Advanced"
        case .demo: return "Demo Bundle"
        case .businessEnglish: return "Business English"
        case .everydayEnglish: return "Everyday English"
        }
    }

    var badgeImage: String {
        switch self {
        case .toeflBeginner: return "toefl_beginner_badge"
        case .toeflIntermediate: return "toefl_intermediate_badge"
        case .toeflAdvanced: return "toefl_advanced_badge"
        case .ieltsBeginner: return "ielts_beginner_badge"
        case .ieltsIntermediate: return "ielts_intermediate_badge"
        case .ieltsAdvanced: return "ielts_advanced_badge"
        case .demo: return "demo_badge"
        case .businessEnglish: return "business_english_badge"
        case .everydayEnglish: return "everyday_english_badge"
        }
    }

    var colorGradient: LinearGradient {
        switch self {
        case .toeflBeginner, .toeflIntermediate, .toeflAdvanced:
            return LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .ieltsBeginner, .ieltsIntermediate, .ieltsAdvanced:
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .demo:
            return LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .businessEnglish:
            return LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .everydayEnglish:
            return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
```

### 3.2 Files to Update (10 files)

#### Model Files:

**1. `/ios/dogetionary/dogetionary/Core/Models/DictionaryModels.swift`**

Lines to change:
- Line 250: `is_tianz: Bool?` → `is_demo: Bool?`
- Line 260: `.is_tianz` → `.is_demo`
- Line 300: `is_tianz: Bool? = nil` → `is_demo: Bool? = nil`
- Line 150: `case tianz = "TIANZ"` → `case demo = "DEMO"`
- Line 160: `case .tianz: return "Tianz Test"` → `case .demo: return "Demo Bundle"`
- Line 320: `tianz_enabled: Bool?` → `demo_enabled: Bool?`
- Line 321: `tianz_target_days: Int?` → `demo_target_days: Int?`
- Line 340: `if tianz_enabled == true { return .tianz }` → `if demo_enabled == true { return .demo }`
- Line 343: `if tianz_enabled == true, let days = tianz_target_days` → `if demo_enabled == true, let days = demo_target_days`
- Line 400: `tianz: BundleProgress?` → `demo: BundleProgress?`
- Line 405: `.tianz` → `.demo`
- Line 415: `case .tianz: return tianz` → `case .demo: return demo`
- Line 450: Properties `tianz_enabled` → `demo_enabled`, `tianz_target_days` → `demo_target_days`
- Line 470: Init params `tianzEnabled` → `demoEnabled`, `tianzTargetDays` → `demoTargetDays`
- Line 500: `tianz_words: Int?` → `demo_words: Int?`
- Line 505: `.tianz_words` → `.demo_words`

**Add new properties for Business English and Everyday English:**
```swift
// In SavedWord struct
var business_english: Bool?
var everyday_english: Bool?

// In BundlePreferenceResponse struct
var business_english_enabled: Bool?
var business_english_target_days: Int?
var everyday_english_enabled: Bool?
var everyday_english_target_days: Int?

// In BundleProgressResponse struct
var businessEnglish: BundleProgress?
var everydayEnglish: BundleProgress?
```

#### Manager Files:

**2. `/ios/dogetionary/dogetionary/Core/Managers/UserManager.swift`**

Lines to change:
- Line 27: `private let tianzEnabledKey` → `private let demoEnabledKey`
- Line 30: `private let tianzTargetDaysKey` → `private let demoTargetDaysKey`
- Line 142: `@Published var tianzEnabled: Bool` → `@Published var demoEnabled: Bool`
- Line 144: `tianzEnabledKey` → `demoEnabledKey`
- Line 150: `@Published var tianzTargetDays: Int` → `@Published var demoTargetDays: Int`
- Line 152: `tianzTargetDaysKey` → `demoTargetDaysKey`
- Lines 180-220: Replace all `tianzEnabled` → `demoEnabled`
- Lines 240-260: Update legacy sync methods
- Lines 280-300: Update `updateLegacyPropertiesFromActive()`
- Lines 320-340: Update `syncLegacyPropertiesToServer()`
- Lines 360-380: Update `loadPreferencesFromServer()`
- Lines 400-420: Replace all conditionals

**Add new properties:**
```swift
@Published var businessEnglishEnabled: Bool
@Published var businessEnglishTargetDays: Int
@Published var everydayEnglishEnabled: Bool
@Published var everydayEnglishTargetDays: Int
```

#### View Files:

**3. `/ios/dogetionary/dogetionary/Features/Schedule/ScheduleView.swift`**
- Line 150: `activeTestType = .tianz` → `activeTestType = .demo`
- Line 160: `if activeTestType == .tianz` → `if activeTestType == .demo`
- Line 170: `case .tianz: return "Tianz Test"` → `case .demo: return "Demo Bundle"`

**4. `/ios/dogetionary/dogetionary/Features/SavedWords/SavedWordsView.swift`**
- Line 300: `userManager.tianzEnabled && (savedWord.is_tianz == true)` → `userManager.demoEnabled && (savedWord.is_demo == true)`
- Add filters for `businessEnglishEnabled` and `everydayEnglishEnabled`

**5. `/ios/dogetionary/dogetionary/Shared/Theme/ThemeConstants.swift`**
- Line 80: `.tianz:` → `.demo:` in color theme definitions
- Add `.businessEnglish:` and `.everydayEnglish:` gradient definitions

### Global Search/Replace Commands:

```bash
cd /Users/biubiu/projects/dogetionary/ios/dogetionary/dogetionary

# Replace tianz → demo (careful with case sensitivity)
find . -name "*.swift" -exec sed -i '' 's/is_tianz/is_demo/g' {} +
find . -name "*.swift" -exec sed -i '' 's/tianzEnabled/demoEnabled/g' {} +
find . -name "*.swift" -exec sed -i '' 's/tianzTargetDays/demoTargetDays/g' {} +
find . -name "*.swift" -exec sed -i '' 's/tianz_enabled/demo_enabled/g' {} +
find . -name "*.swift" -exec sed -i '' 's/tianz_target_days/demo_target_days/g' {} +
find . -name "*.swift" -exec sed -i '' 's/\.tianz/.demo/g' {} +
find . -name "*.swift" -exec sed -i '' 's/"TIANZ"/"DEMO"/g' {} +
find . -name "*.swift" -exec sed -i '' 's/case tianz/case demo/g' {} +
```

### 3.3 Asset Files (Badge Images)

**Create placeholder badge imagesets:**

```bash
cd /Users/biubiu/projects/dogetionary/ios/dogetionary/dogetionary/Assets.xcassets

# Rename tianz_badge → demo_badge
mv tianz_badge.imageset demo_badge.imageset
sed -i '' 's/tianz_badge/demo_badge/g' demo_badge.imageset/Contents.json

# Copy toefl_beginner_badge as placeholder for business_english
cp -r toefl_beginner_badge.imageset business_english_badge.imageset
sed -i '' 's/toefl_beginner_badge/business_english_badge/g' business_english_badge.imageset/Contents.json

# Copy ielts_beginner_badge as placeholder for everyday_english
cp -r ielts_beginner_badge.imageset everyday_english_badge.imageset
sed -i '' 's/ielts_beginner_badge/everyday_english_badge/g' everyday_english_badge.imageset/Contents.json
```

---

## PHASE 4: DATA IMPORT (15 min)

### 4.1 Create Import Script

**File**: `/scripts/import_vocabulary_bundles.py`

```python
"""
Import vocabulary bundles from merged CSV file.
Imports 4,042 words with 8 bundle flags.
"""
import csv
import psycopg2
from pathlib import Path
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def import_bundles():
    # Database connection
    conn = psycopg2.connect(
        host="localhost",
        port=5432,
        database="dogetionary",
        user="postgres",
        password="postgres"
    )
    cursor = conn.cursor()

    # Read CSV
    csv_path = Path(__file__).parent.parent / 'resources' / 'words' / 'vocabulary_merged.csv'
    logger.info(f"Reading vocabulary from {csv_path}")

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    logger.info(f"Found {len(rows)} words in CSV")

    # Import each word
    inserted = 0
    updated = 0

    for row in rows:
        word = row['word'].strip().lower()

        # Convert CSV flags (0/1 strings) to boolean
        flags = {
            'is_toefl_beginner': row.get('toefl_beginner', '0') == '1',
            'is_toefl_intermediate': row.get('toefl_intermediate', '0') == '1',
            'is_toefl_advanced': row.get('toefl_advanced', '0') == '1',
            'is_ielts_beginner': row.get('ielts_beginner', '0') == '1',
            'is_ielts_intermediate': row.get('ielts_intermediate', '0') == '1',
            'is_ielts_advanced': row.get('ielts_advanced', '0') == '1',
            'is_demo': False,  # DEMO bundle is manually curated, not in CSV
            'business_english': row.get('business_english', '0') == '1',
            'everyday_english': row.get('everyday_english', '0') == '1',
        }

        # Upsert word
        cursor.execute("""
            INSERT INTO bundle_vocabularies (
                word, language,
                is_toefl_beginner, is_toefl_intermediate, is_toefl_advanced,
                is_ielts_beginner, is_ielts_intermediate, is_ielts_advanced,
                is_demo, business_english, everyday_english
            ) VALUES (
                %s, 'en',
                %s, %s, %s,
                %s, %s, %s,
                %s, %s, %s
            )
            ON CONFLICT (word, language) DO UPDATE SET
                is_toefl_beginner = EXCLUDED.is_toefl_beginner,
                is_toefl_intermediate = EXCLUDED.is_toefl_intermediate,
                is_toefl_advanced = EXCLUDED.is_toefl_advanced,
                is_ielts_beginner = EXCLUDED.is_ielts_beginner,
                is_ielts_intermediate = EXCLUDED.is_ielts_intermediate,
                is_ielts_advanced = EXCLUDED.is_ielts_advanced,
                business_english = EXCLUDED.business_english,
                everyday_english = EXCLUDED.everyday_english
            RETURNING (xmax = 0) as inserted
        """, [
            word,
            flags['is_toefl_beginner'], flags['is_toefl_intermediate'], flags['is_toefl_advanced'],
            flags['is_ielts_beginner'], flags['is_ielts_intermediate'], flags['is_ielts_advanced'],
            flags['is_demo'], flags['business_english'], flags['everyday_english']
        ])

        result = cursor.fetchone()
        if result and result[0]:
            inserted += 1
        else:
            updated += 1

    conn.commit()
    cursor.close()
    conn.close()

    logger.info(f"Import complete: {inserted} inserted, {updated} updated")

    # Print statistics
    print("\n=== IMPORT STATISTICS ===")
    print(f"Total words processed: {len(rows)}")
    print(f"New words inserted: {inserted}")
    print(f"Existing words updated: {updated}")

if __name__ == '__main__':
    import_bundles()
```

### 4.2 Execute Import

```bash
cd /Users/biubiu/projects/dogetionary
python3 scripts/import_vocabulary_bundles.py
```

### 4.3 Verify Import

```bash
docker exec dogetionary-postgres-1 psql -U postgres dogetionary -c "
SELECT
    COUNT(*) FILTER (WHERE business_english = TRUE) as business_english_count,
    COUNT(*) FILTER (WHERE everyday_english = TRUE) as everyday_english_count,
    COUNT(*) as total_words
FROM bundle_vocabularies;
"
```

Expected output:
```
 business_english_count | everyday_english_count | total_words
------------------------+------------------------+-------------
                   1500 |                   1500 |        4042
```

---

## PHASE 5: TESTING & VERIFICATION (20 min)

### 5.1 Backend Tests

```bash
# Test bundle vocabulary endpoint
curl -X GET "http://localhost:5001/v3/bundle-prep/config" | jq .

# Expected response should show all bundle types including DEMO, BUSINESS_ENGLISH, EVERYDAY_ENGLISH
```

### 5.2 Database Verification

```bash
# Verify all tables renamed
docker exec dogetionary-postgres-1 psql -U postgres dogetionary -c "\\dt" | grep bundle

# Verify user_preferences columns
docker exec dogetionary-postgres-1 psql -U postgres dogetionary -c "\\d user_preferences" | grep demo

# Check bundle word counts
docker exec dogetionary-postgres-1 psql -U postgres dogetionary -c "
SELECT
    COUNT(*) FILTER (WHERE is_demo) as demo,
    COUNT(*) FILTER (WHERE business_english) as business_english,
    COUNT(*) FILTER (WHERE everyday_english) as everyday_english,
    COUNT(*) as total
FROM bundle_vocabularies;
"
```

### 5.3 iOS Compilation Test

```bash
cd /Users/biubiu/projects/dogetionary/ios/dogetionary
xcodebuild clean build -project dogetionary.xcodeproj -scheme dogetionary -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

Expected: Build succeeds with 0 errors

### 5.4 Integration Test

Create test script: `/scripts/test_bundle_migration.py`

```python
"""
Test bundle migration completeness
"""
import requests
import uuid

BASE_URL = "http://localhost:5001"
USER_ID = str(uuid.uuid4())

def test_bundle_endpoints():
    # Test 1: Get bundle config
    response = requests.get(f"{BASE_URL}/v3/bundle-prep/config")
    assert response.status_code == 200
    data = response.json()
    assert 'DEMO' in str(data)
    assert 'BUSINESS_ENGLISH' in str(data)
    print("✅ Bundle config endpoint works")

    # Test 2: Update user preferences for demo bundle
    response = requests.post(f"{BASE_URL}/v3/bundle-prep/settings", json={
        "user_id": USER_ID,
        "demo_enabled": True,
        "demo_target_days": 30
    })
    assert response.status_code == 200
    print("✅ Demo bundle preferences updated")

    # Test 3: Get bundle progress
    response = requests.get(f"{BASE_URL}/v3/bundle-prep/progress", params={
        "user_id": USER_ID
    })
    assert response.status_code == 200
    data = response.json()
    assert 'demo' in data
    print("✅ Bundle progress endpoint works")

    print("\n=== ALL TESTS PASSED ===")

if __name__ == '__main__':
    test_bundle_endpoints()
```

Run test:
```bash
python3 scripts/test_bundle_migration.py
```

---

## ROLLBACK PLAN

If migration fails at any point:

```bash
# 1. Stop backend
docker-compose stop app

# 2. Restore database from backup
docker exec -i dogetionary-postgres-1 psql -U postgres dogetionary < backup_pre_bundle_migration_YYYYMMDD_HHMMSS.sql

# 3. Revert code changes using git
cd /Users/biubiu/projects/dogetionary
git checkout src/ ios/ db/

# 4. Restart services
docker-compose up -d
```

---

## POST-MIGRATION CLEANUP

### 1. Update Documentation
- Update API documentation with new bundle types
- Update README with bundle terminology
- Add MIGRATION_NOTES.md with changelog

### 2. Resource Files
```bash
# Rename resource files
mv resources/tianz.csv resources/demo.csv
```

### 3. Verify Grafana/Prometheus
- Check that metrics still work after backend restart
- Verify no references to old "test_vocabularies" in queries

### 4. Git Commit
```bash
git add -A
git commit -m "Migration: TIANZ→DEMO, test→bundle, add Business/Everyday English bundles

- Renamed TIANZ to DEMO throughout codebase (db/backend/ios)
- Renamed test_vocabularies → bundle_vocabularies table
- Added business_english and everyday_english bundle types
- Imported 4,042 words from vocabulary_merged.csv
- Updated all 36 affected files
- Created bundle_config.py for centralized configuration
- Added placeholder badges for new bundles

Migration verified: ✅ Database ✅ Backend ✅ iOS"
```

---

## DETAILED FILE CHECKLIST

### Database Files (3 files)
- [ ] `/db/init.sql` - Update schema (Phase 1)
- [ ] `/db/migration_009_bundle_vocabulary.sql` - Create migration (Phase 1)
- [ ] `/scripts/check_tianz_completeness.sql` - Rename to check_demo_completeness.sql

### Backend Python Files (26 files)
- [ ] `/src/config/bundle_config.py` - CREATE NEW FILE
- [ ] `/src/handlers/test_vocabulary.py` → `/src/handlers/bundle_vocabulary.py` - RENAME & UPDATE
- [ ] `/src/handlers/users.py` - UPDATE
- [ ] `/src/handlers/schedule.py` - UPDATE
- [ ] `/src/handlers/achievements.py` - UPDATE
- [ ] `/src/handlers/admin_questions.py` - UPDATE
- [ ] `/src/handlers/admin_questions_smart.py` - UPDATE
- [ ] `/src/handlers/practice_status.py` - UPDATE
- [ ] `/src/handlers/review_batch.py` - UPDATE
- [ ] `/src/handlers/words.py` - UPDATE
- [ ] `/src/services/schedule_service.py` - UPDATE
- [ ] `/src/workers/test_vocabulary_worker.py` → `/src/workers/bundle_vocabulary_worker.py` - RENAME & UPDATE
- [ ] `/scripts/import_test_vocabularies.py` → `/scripts/import_bundle_vocabularies.py` - RENAME & UPDATE
- [ ] `/scripts/import_vocabulary_bundles.py` - CREATE NEW FILE (Phase 4)
- [ ] `/scripts/prepopulate_local.py` - UPDATE
- [ ] `/scripts/prepopulate_questions.py` - UPDATE
- [ ] `/scripts/prepopulate_smart.py` - UPDATE
- [ ] `/scripts/test_bundle_migration.py` - CREATE NEW FILE (Phase 5)
- [ ] `/src/app.py` - UPDATE imports
- [ ] `/src/app_v3.py` - UPDATE routes (if needed)

### iOS Swift Files (12 files)
- [ ] `/ios/dogetionary/dogetionary/Core/Config/BundleConfig.swift` - CREATE NEW FILE
- [ ] `/ios/dogetionary/dogetionary/Core/Models/DictionaryModels.swift` - UPDATE (~30 changes)
- [ ] `/ios/dogetionary/dogetionary/Core/Managers/UserManager.swift` - UPDATE (~25 changes)
- [ ] `/ios/dogetionary/dogetionary/Features/Schedule/ScheduleView.swift` - UPDATE
- [ ] `/ios/dogetionary/dogetionary/Features/SavedWords/SavedWordsView.swift` - UPDATE
- [ ] `/ios/dogetionary/dogetionary/Shared/Theme/ThemeConstants.swift` - UPDATE

### Asset Files (4 imagesets)
- [ ] `/ios/.../Assets.xcassets/tianz_badge.imageset/` → `demo_badge.imageset/` - RENAME
- [ ] `/ios/.../Assets.xcassets/business_english_badge.imageset/` - CREATE (copy from toefl_beginner)
- [ ] `/ios/.../Assets.xcassets/everyday_english_badge.imageset/` - CREATE (copy from ielts_beginner)

### Resource Files (2 files)
- [ ] `/resources/tianz.csv` → `/resources/demo.csv` - RENAME
- [ ] `/resources/words/vocabulary_merged.csv` - VERIFY EXISTS

---

## ESTIMATED TIME BREAKDOWN

| Phase | Task | Time |
|-------|------|------|
| 0 | Pre-migration backup & prep | 5 min |
| 1 | Database migration | 10 min |
| 2 | Backend Python updates | 20 min |
| 3 | iOS Swift updates | 15 min |
| 4 | Data import (4,042 words) | 15 min |
| 5 | Testing & verification | 20 min |
| 6 | Post-migration cleanup | 5 min |
| **TOTAL** | | **90 min** |

---

## SUCCESS CRITERIA

✅ Database migration completes without errors
✅ All 4,042 words imported with correct bundle flags
✅ Backend API responds with new bundle types (DEMO, BUSINESS_ENGLISH, EVERYDAY_ENGLISH)
✅ iOS app compiles without errors
✅ Integration tests pass
✅ Grafana dashboard still displays metrics correctly
✅ No references to "tianz" or "test_vocabularies" remain in active code

---

**Ready to execute?** Let's proceed phase by phase with verification at each step.
