-- Migration 009: Rename TIANZ → DEMO, Test → Bundle, Add New Bundles
-- Date: 2025-12-14
-- Description: Complete refactoring of vocabulary bundle system

BEGIN;

-- ============================================================================
-- STEP 1: RENAME TABLE test_vocabularies → bundle_vocabularies
-- ============================================================================

ALTER TABLE test_vocabularies RENAME TO bundle_vocabularies;

-- Rename indexes
ALTER INDEX idx_test_vocab_toefl RENAME TO idx_bundle_vocab_toefl;
ALTER INDEX idx_test_vocab_toefl_beginner RENAME TO idx_bundle_vocab_toefl_beginner;
ALTER INDEX idx_test_vocab_toefl_intermediate RENAME TO idx_bundle_vocab_toefl_intermediate;
ALTER INDEX idx_test_vocab_toefl_advanced RENAME TO idx_bundle_vocab_toefl_advanced;
ALTER INDEX idx_test_vocab_ielts RENAME TO idx_bundle_vocab_ielts;
ALTER INDEX idx_test_vocab_ielts_beginner RENAME TO idx_bundle_vocab_ielts_beginner;
ALTER INDEX idx_test_vocab_ielts_intermediate RENAME TO idx_bundle_vocab_ielts_intermediate;
ALTER INDEX idx_test_vocab_ielts_advanced RENAME TO idx_bundle_vocab_ielts_advanced;
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

-- First, update existing TIANZ schedules to DEMO
UPDATE study_schedules SET test_type = 'DEMO' WHERE test_type = 'TIANZ';

-- Drop old CHECK constraint
ALTER TABLE study_schedules DROP CONSTRAINT IF EXISTS study_schedules_test_type_check;

-- Add new CHECK constraint with updated values
ALTER TABLE study_schedules ADD CONSTRAINT study_schedules_test_type_check CHECK (
    test_type IN ('TOEFL_BEGINNER', 'TOEFL_INTERMEDIATE', 'TOEFL_ADVANCED',
                  'IELTS_BEGINNER', 'IELTS_INTERMEDIATE', 'IELTS_ADVANCED',
                  'DEMO', 'BUSINESS_ENGLISH', 'EVERYDAY_ENGLISH',
                  'TOEFL', 'IELTS', 'BOTH')
);

-- Rename test_type column to bundle_type (optional - keeping as test_type for now)
-- Uncomment if you want to rename the column:
-- ALTER TABLE study_schedules RENAME COLUMN test_type TO bundle_type;

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
