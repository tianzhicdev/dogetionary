-- Bundle Video Coverage Analysis
-- This query calculates the percentage of vocabulary words with videos for each bundle
--
-- Usage:
--   Local: docker-compose exec -T postgres psql -U dogeuser -d dogetionary -f scripts/bundle_video_coverage.sql
--   Production: psql -U <user> -d <database> -f scripts/bundle_video_coverage.sql
--
-- Output columns:
--   - bundle_name: Name of the vocabulary bundle
--   - total_words: Total number of words in the bundle
--   - words_with_videos: Number of words that have at least one video
--   - total_video_mappings: Total number of video-word associations
--   - coverage_pct: Percentage of words with videos
--   - avg_videos_per_word: Average number of videos per word (across all words)
--   - avg_videos_per_word_with_video: Average number of videos per word (only words with videos)

WITH bundle_unpivot AS (
    -- Convert boolean flags to bundle names
    SELECT word, language, 'toefl_beginner' AS bundle_name
    FROM bundle_vocabularies WHERE is_toefl_beginner = TRUE
    UNION ALL
    SELECT word, language, 'toefl_intermediate' AS bundle_name
    FROM bundle_vocabularies WHERE is_toefl_intermediate = TRUE
    UNION ALL
    SELECT word, language, 'toefl_advanced' AS bundle_name
    FROM bundle_vocabularies WHERE is_toefl_advanced = TRUE
    UNION ALL
    SELECT word, language, 'ielts_beginner' AS bundle_name
    FROM bundle_vocabularies WHERE is_ielts_beginner = TRUE
    UNION ALL
    SELECT word, language, 'ielts_intermediate' AS bundle_name
    FROM bundle_vocabularies WHERE is_ielts_intermediate = TRUE
    UNION ALL
    SELECT word, language, 'ielts_advanced' AS bundle_name
    FROM bundle_vocabularies WHERE is_ielts_advanced = TRUE
    UNION ALL
    SELECT word, language, 'business_english' AS bundle_name
    FROM bundle_vocabularies WHERE business_english = TRUE
    UNION ALL
    SELECT word, language, 'everyday_english' AS bundle_name
    FROM bundle_vocabularies WHERE everyday_english = TRUE
    UNION ALL
    SELECT word, language, 'demo' AS bundle_name
    FROM bundle_vocabularies WHERE is_demo = TRUE
)
SELECT
    bv.bundle_name,
    COUNT(DISTINCT bv.word) AS total_words,
    COUNT(DISTINCT wtv.word) AS words_with_videos,
    COUNT(wtv.id) AS total_video_mappings,
    ROUND(
        (COUNT(DISTINCT wtv.word)::DECIMAL / NULLIF(COUNT(DISTINCT bv.word), 0) * 100),
        2
    ) AS coverage_pct,
    ROUND(
        (COUNT(wtv.id)::DECIMAL / NULLIF(COUNT(DISTINCT bv.word), 0)),
        2
    ) AS avg_videos_per_word,
    ROUND(
        (COUNT(wtv.id)::DECIMAL / NULLIF(COUNT(DISTINCT wtv.word), 0)),
        2
    ) AS avg_videos_per_word_with_video
FROM bundle_unpivot bv
LEFT JOIN word_to_video wtv
    ON LOWER(bv.word) = LOWER(wtv.word)
    AND bv.language = wtv.learning_language
GROUP BY bv.bundle_name
HAVING COUNT(DISTINCT bv.word) > 0
ORDER BY coverage_pct DESC, bundle_name;
