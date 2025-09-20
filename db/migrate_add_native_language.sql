-- Migration: Add native_language to saved_words table
-- This script handles existing data migration

-- Step 1: Add the new column (nullable initially)
ALTER TABLE saved_words ADD COLUMN native_language VARCHAR(10);

-- Step 2: Populate existing records with current user preferences
UPDATE saved_words
SET native_language = (
    SELECT native_language
    FROM user_preferences
    WHERE user_preferences.user_id = saved_words.user_id
)
WHERE native_language IS NULL;

-- Step 3: Set default for any remaining null values (fallback)
UPDATE saved_words
SET native_language = 'zh'
WHERE native_language IS NULL;

-- Step 4: Make the column NOT NULL
ALTER TABLE saved_words ALTER COLUMN native_language SET NOT NULL;

-- Step 5: Drop the old unique constraint
ALTER TABLE saved_words DROP CONSTRAINT saved_words_user_id_word_learning_language_key;

-- Step 6: Add new unique constraint including native_language
ALTER TABLE saved_words ADD CONSTRAINT saved_words_user_id_word_learning_native_key
    UNIQUE(user_id, word, learning_language, native_language);