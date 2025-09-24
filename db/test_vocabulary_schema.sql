-- Add test vocabulary support to the database
-- Run this after the main init.sql

-- Test vocabulary table to store TOEFL/IELTS words
CREATE TABLE IF NOT EXISTS test_vocabularies (
    word VARCHAR(100) NOT NULL,
    language VARCHAR(10) NOT NULL DEFAULT 'en',
    is_toefl BOOLEAN DEFAULT FALSE,
    is_ielts BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (word, language)
);

-- Add test preparation settings to user preferences
ALTER TABLE user_preferences
ADD COLUMN IF NOT EXISTS toefl_enabled BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS ielts_enabled BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS last_test_words_added DATE;

-- Index for efficient queries
CREATE INDEX IF NOT EXISTS idx_test_vocab_toefl ON test_vocabularies(is_toefl) WHERE is_toefl = TRUE;
CREATE INDEX IF NOT EXISTS idx_test_vocab_ielts ON test_vocabularies(is_ielts) WHERE is_ielts = TRUE;
CREATE INDEX IF NOT EXISTS idx_user_pref_test_enabled ON user_preferences(user_id)
    WHERE toefl_enabled = TRUE OR ielts_enabled = TRUE;

-- Function to get random test words for a user
CREATE OR REPLACE FUNCTION get_random_test_words(
    p_user_id UUID,
    p_learning_language VARCHAR,
    p_native_language VARCHAR,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    word VARCHAR,
    language VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    WITH user_settings AS (
        SELECT toefl_enabled, ielts_enabled
        FROM user_preferences
        WHERE user_id = p_user_id
    ),
    existing_words AS (
        SELECT sw.word
        FROM saved_words sw
        WHERE sw.user_id = p_user_id
        AND sw.learning_language = p_learning_language
    )
    SELECT DISTINCT tv.word, tv.language
    FROM test_vocabularies tv
    CROSS JOIN user_settings us
    WHERE tv.language = p_learning_language
    AND (
        (us.toefl_enabled = TRUE AND tv.is_toefl = TRUE) OR
        (us.ielts_enabled = TRUE AND tv.is_ielts = TRUE)
    )
    AND tv.word NOT IN (SELECT word FROM existing_words)
    ORDER BY RANDOM()
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Function to add test words to user's saved words
CREATE OR REPLACE FUNCTION add_daily_test_words(
    p_user_id UUID,
    p_learning_language VARCHAR DEFAULT 'en',
    p_native_language VARCHAR DEFAULT 'zh'
)
RETURNS INTEGER AS $$
DECLARE
    v_words_added INTEGER := 0;
    v_word RECORD;
BEGIN
    -- Check if user has test mode enabled and hasn't added words today
    IF NOT EXISTS (
        SELECT 1 FROM user_preferences
        WHERE user_id = p_user_id
        AND (toefl_enabled = TRUE OR ielts_enabled = TRUE)
        AND (last_test_words_added IS NULL OR last_test_words_added < CURRENT_DATE)
    ) THEN
        RETURN 0;
    END IF;

    -- Get random test words and add them
    FOR v_word IN
        SELECT * FROM get_random_test_words(p_user_id, p_learning_language, p_native_language, 10)
    LOOP
        INSERT INTO saved_words (user_id, word, learning_language, native_language)
        VALUES (p_user_id, v_word.word, p_learning_language, p_native_language)
        ON CONFLICT DO NOTHING;

        v_words_added := v_words_added + 1;
    END LOOP;

    -- Update last added date
    IF v_words_added > 0 THEN
        UPDATE user_preferences
        SET last_test_words_added = CURRENT_DATE
        WHERE user_id = p_user_id;
    END IF;

    RETURN v_words_added;
END;
$$ LANGUAGE plpgsql;

-- View to track test vocabulary progress
CREATE OR REPLACE VIEW test_vocabulary_progress AS
WITH user_test_stats AS (
    SELECT
        up.user_id,
        up.learning_language,
        up.native_language,
        up.toefl_enabled,
        up.ielts_enabled,
        COUNT(DISTINCT CASE WHEN tv.is_toefl THEN sw.word END) as toefl_saved,
        COUNT(DISTINCT CASE WHEN tv.is_ielts THEN sw.word END) as ielts_saved
    FROM user_preferences up
    LEFT JOIN saved_words sw ON sw.user_id = up.user_id
    LEFT JOIN test_vocabularies tv ON tv.word = sw.word AND tv.language = sw.learning_language
    WHERE up.toefl_enabled = TRUE OR up.ielts_enabled = TRUE
    GROUP BY up.user_id, up.learning_language, up.native_language, up.toefl_enabled, up.ielts_enabled
),
total_counts AS (
    SELECT
        language,
        COUNT(DISTINCT CASE WHEN is_toefl THEN word END) as total_toefl,
        COUNT(DISTINCT CASE WHEN is_ielts THEN word END) as total_ielts
    FROM test_vocabularies
    GROUP BY language
)
SELECT
    uts.*,
    tc.total_toefl,
    tc.total_ielts,
    CASE WHEN uts.toefl_enabled AND tc.total_toefl > 0
         THEN ROUND(100.0 * uts.toefl_saved / tc.total_toefl, 1)
         ELSE 0 END as toefl_progress,
    CASE WHEN uts.ielts_enabled AND tc.total_ielts > 0
         THEN ROUND(100.0 * uts.ielts_saved / tc.total_ielts, 1)
         ELSE 0 END as ielts_progress
FROM user_test_stats uts
LEFT JOIN total_counts tc ON tc.language = uts.learning_language;