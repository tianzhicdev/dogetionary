-- Migration: Add is_known column to saved_words table
-- Purpose: Allow users to mark words as "known" to exclude them from practice and schedule

ALTER TABLE saved_words
ADD COLUMN IF NOT EXISTS is_known BOOLEAN DEFAULT FALSE;

-- Add index for filtering known/learning words
CREATE INDEX IF NOT EXISTS idx_saved_words_is_known ON saved_words(user_id, is_known);

-- Add comment for documentation
COMMENT ON COLUMN saved_words.is_known IS 'Whether the user has marked this word as already known. Known words are excluded from reviews and schedules.';
