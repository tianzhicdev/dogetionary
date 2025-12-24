-- SQL Query: Add all words with videos from word_to_video to demo bundle
-- This query inserts/updates bundle_vocabularies to mark all words that have videos as part of the demo bundle

-- Step 1: Insert new words (that don't exist in bundle_vocabularies yet)
INSERT INTO bundle_vocabularies (word, language, is_demo)
SELECT DISTINCT
    wtv.word,
    wtv.learning_language,
    TRUE
FROM word_to_video wtv
WHERE NOT EXISTS (
    SELECT 1
    FROM bundle_vocabularies bv
    WHERE bv.word = wtv.word
    AND bv.language = wtv.learning_language
)
ON CONFLICT (word, language) DO NOTHING;

-- Step 2: Update existing words to mark them as demo
UPDATE bundle_vocabularies
SET is_demo = TRUE
WHERE (word, language) IN (
    SELECT DISTINCT word, learning_language
    FROM word_to_video
);

-- Verification queries
SELECT
    'Total unique words with videos:' as description,
    COUNT(DISTINCT word) as count
FROM word_to_video
UNION ALL
SELECT
    'Words now in demo bundle:' as description,
    COUNT(*) as count
FROM bundle_vocabularies
WHERE is_demo = TRUE;
