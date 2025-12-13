-- Check completeness of tianz_test words
-- Shows which words are missing definitions or questions

WITH tianz_words AS (
    SELECT word, language
    FROM test_vocabularies
    WHERE is_tianz = true
    AND language = 'en'
),
word_status AS (
    SELECT
        tw.word,
        EXISTS (
            SELECT 1 FROM definitions d
            WHERE d.word = tw.word
            AND d.learning_language = tw.language
            AND d.native_language = 'zh'
        ) AS has_definition,
        (
            SELECT COUNT(DISTINCT question_type)
            FROM review_questions rq
            WHERE rq.word = tw.word
            AND rq.learning_language = tw.language
            AND rq.native_language = 'zh'
        ) AS question_count,
        EXISTS (
            SELECT 1 FROM word_to_video w2v
            WHERE w2v.word = tw.word
            AND w2v.learning_language = tw.language
        ) AS has_video
    FROM tianz_words tw
)
SELECT
    '=== TIANZ TEST COMPLETENESS ===' AS section,
    COUNT(*) AS total_words,
    COUNT(*) FILTER (WHERE has_definition) AS has_def,
    COUNT(*) FILTER (WHERE question_count = 5) AS has_all_q,
    COUNT(*) FILTER (WHERE has_definition AND question_count = 5) AS complete,
    ROUND(COUNT(*) FILTER (WHERE has_definition AND question_count = 5)::numeric / COUNT(*)::numeric * 100, 1) AS pct_complete
FROM word_status

UNION ALL

SELECT
    'Missing Definition' AS section,
    COUNT(*),
    0,
    0,
    0,
    0
FROM word_status
WHERE NOT has_definition

UNION ALL

SELECT
    'Missing Questions' AS section,
    COUNT(*),
    0,
    0,
    0,
    0
FROM word_status
WHERE has_definition AND question_count < 5

UNION ALL

SELECT
    'Has Video' AS section,
    COUNT(*) FILTER (WHERE has_video),
    0,
    0,
    0,
    0
FROM word_status;
