-- Migration: Create bundle_vocabularies table
-- Purpose: Map bundle names to vocabulary words for video pipeline
-- Created: 2025-12-16

-- Create bundle_vocabularies table
CREATE TABLE IF NOT EXISTS bundle_vocabularies (
    id SERIAL PRIMARY KEY,
    bundle_name VARCHAR(100) NOT NULL,           -- e.g., 'toefl_beginner', 'ielts_advanced', 'custom_medical'
    word VARCHAR(100) NOT NULL,
    learning_language VARCHAR(10) NOT NULL DEFAULT 'en',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Ensure unique word per bundle
    CONSTRAINT unique_bundle_word UNIQUE(bundle_name, word, learning_language)
);

-- Create indexes for efficient lookups
CREATE INDEX IF NOT EXISTS idx_bundle_vocabularies_bundle ON bundle_vocabularies(bundle_name);
CREATE INDEX IF NOT EXISTS idx_bundle_vocabularies_word ON bundle_vocabularies(word, learning_language);
CREATE INDEX IF NOT EXISTS idx_bundle_vocabularies_bundle_word ON bundle_vocabularies(bundle_name, word);

-- Add comments for documentation
COMMENT ON TABLE bundle_vocabularies IS 'Maps bundle names to vocabulary words for organizing video collections';
COMMENT ON COLUMN bundle_vocabularies.bundle_name IS 'Bundle identifier (e.g., toefl_beginner, ielts_advanced)';
COMMENT ON COLUMN bundle_vocabularies.word IS 'Vocabulary word in the bundle';
COMMENT ON COLUMN bundle_vocabularies.learning_language IS 'Language of the word (default: en)';

-- Populate with existing test vocabularies
-- Map TOEFL beginner words
INSERT INTO bundle_vocabularies (bundle_name, word, learning_language)
SELECT 'toefl_beginner', word, language
FROM test_vocabularies
WHERE is_toefl_beginner = TRUE
ON CONFLICT (bundle_name, word, learning_language) DO NOTHING;

-- Map TOEFL intermediate words
INSERT INTO bundle_vocabularies (bundle_name, word, learning_language)
SELECT 'toefl_intermediate', word, language
FROM test_vocabularies
WHERE is_toefl_intermediate = TRUE
ON CONFLICT (bundle_name, word, learning_language) DO NOTHING;

-- Map TOEFL advanced words
INSERT INTO bundle_vocabularies (bundle_name, word, learning_language)
SELECT 'toefl_advanced', word, language
FROM test_vocabularies
WHERE is_toefl_advanced = TRUE
ON CONFLICT (bundle_name, word, learning_language) DO NOTHING;

-- Map IELTS beginner words
INSERT INTO bundle_vocabularies (bundle_name, word, learning_language)
SELECT 'ielts_beginner', word, language
FROM test_vocabularies
WHERE is_ielts_beginner = TRUE
ON CONFLICT (bundle_name, word, learning_language) DO NOTHING;

-- Map IELTS intermediate words
INSERT INTO bundle_vocabularies (bundle_name, word, learning_language)
SELECT 'ielts_intermediate', word, language
FROM test_vocabularies
WHERE is_ielts_intermediate = TRUE
ON CONFLICT (bundle_name, word, learning_language) DO NOTHING;

-- Map IELTS advanced words
INSERT INTO bundle_vocabularies (bundle_name, word, learning_language)
SELECT 'ielts_advanced', word, language
FROM test_vocabularies
WHERE is_ielts_advanced = TRUE
ON CONFLICT (bundle_name, word, learning_language) DO NOTHING;
