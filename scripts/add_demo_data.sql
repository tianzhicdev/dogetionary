-- Demo Data Script for Dogetionary
-- Adds sample saved words and review records for demo user 5E0DAFB6-756C-463E-8061-F88DEAC2E20B

-- Demo user ID
-- 5E0DAFB6-756C-463E-8061-F88DEAC2E20B

-- Clean existing data for demo user
DELETE FROM reviews WHERE user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
DELETE FROM saved_words WHERE user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';

-- Ensure user preferences exist
INSERT INTO user_preferences (user_id, learning_language, native_language)
VALUES ('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'en', 'zh')
ON CONFLICT (user_id) DO UPDATE SET
    learning_language = EXCLUDED.learning_language,
    native_language = EXCLUDED.native_language;

-- Add saved words with realistic creation dates (last 30 days)
INSERT INTO saved_words (user_id, word, learning_language, created_at) VALUES
-- Easy words (learned well)
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'hello', 'en', NOW() - INTERVAL '25 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'goodbye', 'en', NOW() - INTERVAL '23 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'thank', 'en', NOW() - INTERVAL '28 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'please', 'en', NOW() - INTERVAL '22 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'water', 'en', NOW() - INTERVAL '26 days'),

-- Medium words (learning progress)
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'beautiful', 'en', NOW() - INTERVAL '18 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'important', 'en', NOW() - INTERVAL '16 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'understand', 'en', NOW() - INTERVAL '20 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'remember', 'en', NOW() - INTERVAL '15 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'different', 'en', NOW() - INTERVAL '19 days'),

-- Harder words (struggling)
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'serendipity', 'en', NOW() - INTERVAL '14 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'ephemeral', 'en', NOW() - INTERVAL '12 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'ubiquitous', 'en', NOW() - INTERVAL '13 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'pernicious', 'en', NOW() - INTERVAL '11 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'perspicacious', 'en', NOW() - INTERVAL '10 days'),

-- Recently added (few reviews)
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'magnificent', 'en', NOW() - INTERVAL '8 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'adventure', 'en', NOW() - INTERVAL '5 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'knowledge', 'en', NOW() - INTERVAL '9 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'creativity', 'en', NOW() - INTERVAL '6 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'friendship', 'en', NOW() - INTERVAL '4 days'),

-- More words for comprehensive testing
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'challenge', 'en', NOW() - INTERVAL '17 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'opportunity', 'en', NOW() - INTERVAL '21 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'curiosity', 'en', NOW() - INTERVAL '7 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'perseverance', 'en', NOW() - INTERVAL '24 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'imagination', 'en', NOW() - INTERVAL '3 days');

-- Add review records with realistic patterns
-- Note: Using simplified approach without complex spaced repetition calculations

-- Reviews for 'hello' (high success rate - well learned)
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '24 days', NOW() - INTERVAL '22 days' FROM saved_words WHERE word = 'hello' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '22 days', NOW() - INTERVAL '18 days' FROM saved_words WHERE word = 'hello' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '18 days', NOW() - INTERVAL '12 days' FROM saved_words WHERE word = 'hello' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '12 days', NOW() + INTERVAL '10 days' FROM saved_words WHERE word = 'hello' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';

-- Reviews for 'serendipity' (low success rate - struggling)
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, false, NOW() - INTERVAL '13 days', NOW() - INTERVAL '12 days' FROM saved_words WHERE word = 'serendipity' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, false, NOW() - INTERVAL '12 days', NOW() - INTERVAL '11 days' FROM saved_words WHERE word = 'serendipity' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '11 days', NOW() - INTERVAL '8 days' FROM saved_words WHERE word = 'serendipity' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, false, NOW() - INTERVAL '8 days', NOW() - INTERVAL '1 day' FROM saved_words WHERE word = 'serendipity' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';

-- Reviews for 'beautiful' (medium success rate)
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '17 days', NOW() - INTERVAL '15 days' FROM saved_words WHERE word = 'beautiful' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, false, NOW() - INTERVAL '15 days', NOW() - INTERVAL '14 days' FROM saved_words WHERE word = 'beautiful' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '14 days', NOW() - INTERVAL '10 days' FROM saved_words WHERE word = 'beautiful' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '10 days', NOW() + INTERVAL '2 days' FROM saved_words WHERE word = 'beautiful' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';

-- Reviews for words due now/overdue
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '6 days', NOW() - INTERVAL '2 hours' FROM saved_words WHERE word = 'challenge' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, false, NOW() - INTERVAL '4 days', NOW() - INTERVAL '3 hours' FROM saved_words WHERE word = 'ephemeral' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '3 days', NOW() - INTERVAL '1 hour' FROM saved_words WHERE word = 'opportunity' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';

-- Add more reviews for variety
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '21 days', NOW() - INTERVAL '19 days' FROM saved_words WHERE word = 'thank' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '19 days', NOW() - INTERVAL '15 days' FROM saved_words WHERE word = 'thank' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '15 days', NOW() + INTERVAL '7 days' FROM saved_words WHERE word = 'thank' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';

INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, false, NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days' FROM saved_words WHERE word = 'ubiquitous' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, false, NOW() - INTERVAL '4 days', NOW() + INTERVAL '30 minutes' FROM saved_words WHERE word = 'ubiquitous' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';

-- Recently added words with minimal reviews
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '7 days', NOW() - INTERVAL '4 days' FROM saved_words WHERE word = 'magnificent' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, false, NOW() - INTERVAL '4 days', NOW() + INTERVAL '45 minutes' FROM saved_words WHERE word = 'magnificent' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';

INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT '5E0DAFB6-756C-463E-8061-F88DEAC2E20B', id, true, NOW() - INTERVAL '4 days', NOW() + INTERVAL '2 days' FROM saved_words WHERE word = 'adventure' AND user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';

-- Print summary
SELECT 
    'DEMO DATA SUMMARY' as info,
    (SELECT COUNT(*) FROM saved_words WHERE user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B') as saved_words_count,
    (SELECT COUNT(*) FROM reviews WHERE user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B') as total_reviews,
    (SELECT COUNT(DISTINCT sw.id) 
     FROM saved_words sw 
     JOIN reviews r ON sw.id = r.word_id 
     WHERE sw.user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B' 
     AND r.next_review_date <= NOW()
     AND r.id = (SELECT MAX(id) FROM reviews r2 WHERE r2.word_id = sw.id)
    ) as words_due_for_review;