-- Migration 007: Add vocabulary level support
-- Adds granular level columns for TOEFL and IELTS tests
-- Each level is cumulative: advanced includes intermediate and beginner words

-- ============================================================
-- ADD NEW LEVEL COLUMNS TO test_vocabularies
-- ============================================================

-- Add TOEFL level columns (cumulative)
ALTER TABLE test_vocabularies
ADD COLUMN is_toefl_beginner BOOLEAN DEFAULT FALSE,
ADD COLUMN is_toefl_intermediate BOOLEAN DEFAULT FALSE,
ADD COLUMN is_toefl_advanced BOOLEAN DEFAULT FALSE;

-- Add IELTS level columns (cumulative)
ALTER TABLE test_vocabularies
ADD COLUMN is_ielts_beginner BOOLEAN DEFAULT FALSE,
ADD COLUMN is_ielts_intermediate BOOLEAN DEFAULT FALSE,
ADD COLUMN is_ielts_advanced BOOLEAN DEFAULT FALSE;

-- Temporary backward compatibility: map old is_toefl to is_toefl_advanced
UPDATE test_vocabularies
SET is_toefl_advanced = is_toefl
WHERE is_toefl = TRUE;

UPDATE test_vocabularies
SET is_ielts_advanced = is_ielts
WHERE is_ielts = TRUE;

-- ============================================================
-- ADD NEW LEVEL COLUMNS TO user_preferences
-- ============================================================

-- Add TOEFL level enabled flags (mutually exclusive)
ALTER TABLE user_preferences
ADD COLUMN toefl_beginner_enabled BOOLEAN DEFAULT FALSE,
ADD COLUMN toefl_intermediate_enabled BOOLEAN DEFAULT FALSE,
ADD COLUMN toefl_advanced_enabled BOOLEAN DEFAULT FALSE;

-- Add IELTS level enabled flags (mutually exclusive)
ALTER TABLE user_preferences
ADD COLUMN ielts_beginner_enabled BOOLEAN DEFAULT FALSE,
ADD COLUMN ielts_intermediate_enabled BOOLEAN DEFAULT FALSE,
ADD COLUMN ielts_advanced_enabled BOOLEAN DEFAULT FALSE;

-- Add target days for each level
ALTER TABLE user_preferences
ADD COLUMN toefl_beginner_target_days INTEGER DEFAULT 30,
ADD COLUMN toefl_intermediate_target_days INTEGER DEFAULT 30,
ADD COLUMN toefl_advanced_target_days INTEGER DEFAULT 30,
ADD COLUMN ielts_beginner_target_days INTEGER DEFAULT 30,
ADD COLUMN ielts_intermediate_target_days INTEGER DEFAULT 30,
ADD COLUMN ielts_advanced_target_days INTEGER DEFAULT 30;

-- Migrate existing users to advanced level (most conservative mapping)
-- This ensures existing users see all their test vocabulary
UPDATE user_preferences
SET toefl_advanced_enabled = toefl_enabled,
    toefl_advanced_target_days = toefl_target_days
WHERE toefl_enabled = TRUE;

UPDATE user_preferences
SET ielts_advanced_enabled = ielts_enabled,
    ielts_advanced_target_days = ielts_target_days
WHERE ielts_enabled = TRUE;

-- ============================================================
-- CREATE INDEXES FOR PERFORMANCE
-- ============================================================

-- Partial indexes on test_vocabularies for fast filtering
CREATE INDEX idx_test_vocab_toefl_beginner ON test_vocabularies(word) WHERE is_toefl_beginner = TRUE;
CREATE INDEX idx_test_vocab_toefl_intermediate ON test_vocabularies(word) WHERE is_toefl_intermediate = TRUE;
CREATE INDEX idx_test_vocab_toefl_advanced ON test_vocabularies(word) WHERE is_toefl_advanced = TRUE;
CREATE INDEX idx_test_vocab_ielts_beginner ON test_vocabularies(word) WHERE is_ielts_beginner = TRUE;
CREATE INDEX idx_test_vocab_ielts_intermediate ON test_vocabularies(word) WHERE is_ielts_intermediate = TRUE;
CREATE INDEX idx_test_vocab_ielts_advanced ON test_vocabularies(word) WHERE is_ielts_advanced = TRUE;

-- ============================================================
-- UPDATE study_schedules CONSTRAINT
-- ============================================================

-- Drop old constraint
ALTER TABLE study_schedules
DROP CONSTRAINT IF EXISTS study_schedules_test_type_check;

-- Add new constraint supporting level-based test types
ALTER TABLE study_schedules
ADD CONSTRAINT study_schedules_test_type_check CHECK (test_type IN (
    'TOEFL_BEGINNER', 'TOEFL_INTERMEDIATE', 'TOEFL_ADVANCED',
    'IELTS_BEGINNER', 'IELTS_INTERMEDIATE', 'IELTS_ADVANCED',
    'TIANZ',
    -- Legacy values for migration period
    'TOEFL', 'IELTS', 'BOTH'
));

-- ============================================================
-- ADD MUTUAL EXCLUSIVITY CONSTRAINT
-- ============================================================

-- Ensure only one test level is enabled at a time
ALTER TABLE user_preferences
ADD CONSTRAINT check_single_test_level CHECK (
    (toefl_beginner_enabled::int + toefl_intermediate_enabled::int + toefl_advanced_enabled::int +
     ielts_beginner_enabled::int + ielts_intermediate_enabled::int + ielts_advanced_enabled::int +
     tianz_enabled::int) <= 1
);

-- ============================================================
-- ADD DOCUMENTATION COMMENTS
-- ============================================================

COMMENT ON COLUMN test_vocabularies.is_toefl_beginner IS 'Cumulative: includes only beginner-level TOEFL words';
COMMENT ON COLUMN test_vocabularies.is_toefl_intermediate IS 'Cumulative: includes beginner + intermediate TOEFL words';
COMMENT ON COLUMN test_vocabularies.is_toefl_advanced IS 'Cumulative: includes all TOEFL words (beginner + intermediate + advanced)';
COMMENT ON COLUMN test_vocabularies.is_ielts_beginner IS 'Cumulative: includes only beginner-level IELTS words';
COMMENT ON COLUMN test_vocabularies.is_ielts_intermediate IS 'Cumulative: includes beginner + intermediate IELTS words';
COMMENT ON COLUMN test_vocabularies.is_ielts_advanced IS 'Cumulative: includes all IELTS words (beginner + intermediate + advanced)';

COMMENT ON CONSTRAINT check_single_test_level ON user_preferences IS 'Ensures only one test level is active at a time';
