-- Demo Data Script for Dogetionary
-- Adds sample saved words and review records for demo user 5E0DAFB6-756C-463E-8061-F88DEAC2E20B

-- Demo user ID
-- 5E0DAFB6-756C-463E-8061-F88DEAC2E20B

-- Clean existing data for demo user
DELETE FROM reviews WHERE user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';
DELETE FROM saved_words WHERE user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';

-- Create multiple demo users with AI-generated profiles for leaderboard testing
INSERT INTO user_preferences (user_id, learning_language, native_language, user_name, user_motto) VALUES
-- Demo User 1 (highest scorer)
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'en', 'zh', 'WordMaster', 'Every mistake is a lesson learned!'),
-- Demo User 2 (second place)  
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'es', 'en', 'LanguageExplorer', 'Growing stronger with every word!'),
-- Demo User 3 (third place)
('A1B2C3D4-5678-90AB-CDEF-123456789002', 'fr', 'en', 'CuriousLearner', 'Adventure awaits in every conversation!'),
-- Demo User 4
('A1B2C3D4-5678-90AB-CDEF-123456789003', 'de', 'en', 'StudyBuddy', 'Practice makes progress!'),
-- Demo User 5
('A1B2C3D4-5678-90AB-CDEF-123456789004', 'it', 'en', 'WordSeeker', 'Learning one word at a time!'),
-- Demo User 6
('A1B2C3D4-5678-90AB-CDEF-123456789005', 'pt', 'en', 'BraveStudent', 'Courage to learn something new!'),
-- Demo User 7
('A1B2C3D4-5678-90AB-CDEF-123456789006', 'ja', 'en', 'KnowledgeHunter', 'Every day brings new discoveries!'),
-- Demo User 8
('A1B2C3D4-5678-90AB-CDEF-123456789007', 'ko', 'en', 'WisdomSeeker', 'Building bridges through words!'),
-- Demo User 9
('A1B2C3D4-5678-90AB-CDEF-123456789008', 'ru', 'en', 'ProgressMaker', 'Small steps lead to big victories!'),
-- Demo User 10 (lowest scorer for demonstration)
('A1B2C3D4-5678-90AB-CDEF-123456789009', 'ar', 'en', 'NewBeginning', 'The journey of a thousand miles starts here!')
ON CONFLICT (user_id) DO UPDATE SET
    learning_language = EXCLUDED.learning_language,
    native_language = EXCLUDED.native_language,
    user_name = EXCLUDED.user_name,
    user_motto = EXCLUDED.user_motto;

-- Add saved words with realistic creation dates (last 30 days)
INSERT INTO saved_words (user_id, word, learning_language, native_language, created_at) VALUES
-- Easy words (learned well)
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'hello', 'en', 'zh', NOW() - INTERVAL '25 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'goodbye', 'en', 'zh', NOW() - INTERVAL '23 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'thank', 'en', 'zh', NOW() - INTERVAL '28 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'please', 'en', 'zh', NOW() - INTERVAL '22 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'water', 'en', 'zh', NOW() - INTERVAL '26 days'),

-- Medium words (learning progress)
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'beautiful', 'en', 'zh', NOW() - INTERVAL '18 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'important', 'en', 'zh', NOW() - INTERVAL '16 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'understand', 'en', 'zh', NOW() - INTERVAL '20 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'remember', 'en', 'zh', NOW() - INTERVAL '15 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'different', 'en', 'zh', NOW() - INTERVAL '19 days'),

-- Harder words (struggling)
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'serendipity', 'en', 'zh', NOW() - INTERVAL '14 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'ephemeral', 'en', 'zh', NOW() - INTERVAL '12 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'ubiquitous', 'en', 'zh', NOW() - INTERVAL '13 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'pernicious', 'en', 'zh', NOW() - INTERVAL '11 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'perspicacious', 'en', 'zh', NOW() - INTERVAL '10 days'),

-- Recently added (few reviews)
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'magnificent', 'en', 'zh', NOW() - INTERVAL '8 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'adventure', 'en', 'zh', NOW() - INTERVAL '5 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'knowledge', 'en', 'zh', NOW() - INTERVAL '9 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'creativity', 'en', 'zh', NOW() - INTERVAL '6 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'friendship', 'en', 'zh', NOW() - INTERVAL '4 days'),

-- More words for comprehensive testing
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'challenge', 'en', 'zh', NOW() - INTERVAL '17 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'opportunity', 'en', 'zh', NOW() - INTERVAL '21 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'curiosity', 'en', 'zh', NOW() - INTERVAL '7 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'perseverance', 'en', 'zh', NOW() - INTERVAL '24 days'),
('5E0DAFB6-756C-463E-8061-F88DEAC2E20B', 'imagination', 'en', 'zh', NOW() - INTERVAL '3 days');

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

-- Demo User 2: LanguageExplorer (second highest - Spanish learner, 95 reviews)
INSERT INTO saved_words (user_id, word, learning_language, native_language, created_at) VALUES
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'hola', 'es', 'en', NOW() - INTERVAL '20 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'gracias', 'es', 'en', NOW() - INTERVAL '18 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'amor', 'es', 'en', NOW() - INTERVAL '16 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'familia', 'es', 'en', NOW() - INTERVAL '14 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'tiempo', 'es', 'en', NOW() - INTERVAL '12 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'hermoso', 'es', 'en', NOW() - INTERVAL '10 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'aventura', 'es', 'en', NOW() - INTERVAL '8 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'esperanza', 'es', 'en', NOW() - INTERVAL '6 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'libertad', 'es', 'en', NOW() - INTERVAL '4 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789001', 'felicidad', 'es', 'en', NOW() - INTERVAL '2 days');

-- Add multiple reviews for User 2 to get ~95 total reviews
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT 'A1B2C3D4-5678-90AB-CDEF-123456789001', sw.id, 
       CASE WHEN (i % 3) = 0 THEN false ELSE true END,
       NOW() - INTERVAL '19 days' + (i::text || ' hours')::interval, 
       NOW() + INTERVAL '1 day' 
FROM saved_words sw, generate_series(1, 95) as i 
WHERE sw.user_id = 'A1B2C3D4-5678-90AB-CDEF-123456789001' 
  AND sw.id = (SELECT MIN(id) FROM saved_words WHERE user_id = sw.user_id);

-- Demo User 3: CuriousLearner (third place - French learner, 78 reviews)
INSERT INTO saved_words (user_id, word, learning_language, native_language, created_at) VALUES
('A1B2C3D4-5678-90AB-CDEF-123456789002', 'bonjour', 'fr', 'en', NOW() - INTERVAL '15 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789002', 'merci', 'fr', 'en', NOW() - INTERVAL '13 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789002', 'amour', 'fr', 'en', NOW() - INTERVAL '11 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789002', 'famille', 'fr', 'en', NOW() - INTERVAL '9 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789002', 'temps', 'fr', 'en', NOW() - INTERVAL '7 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789002', 'beau', 'fr', 'en', NOW() - INTERVAL '5 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789002', 'voyage', 'fr', 'en', NOW() - INTERVAL '3 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789002', 'espoir', 'fr', 'en', NOW() - INTERVAL '1 day');

-- Add reviews for User 3 to get ~78 total reviews
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT 'A1B2C3D4-5678-90AB-CDEF-123456789002', sw.id, 
       CASE WHEN (i % 4) = 0 THEN false ELSE true END,
       NOW() - INTERVAL '14 days' + (i::text || ' hours')::interval, 
       NOW() + INTERVAL '2 days' 
FROM saved_words sw, generate_series(1, 78) as i 
WHERE sw.user_id = 'A1B2C3D4-5678-90AB-CDEF-123456789002' 
  AND sw.id = (SELECT MIN(id) FROM saved_words WHERE user_id = sw.user_id);

-- Demo User 4: StudyBuddy (German learner, 62 reviews)
INSERT INTO saved_words (user_id, word, learning_language, native_language, created_at) VALUES
('A1B2C3D4-5678-90AB-CDEF-123456789003', 'hallo', 'de', 'en', NOW() - INTERVAL '12 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789003', 'danke', 'de', 'en', NOW() - INTERVAL '10 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789003', 'liebe', 'de', 'en', NOW() - INTERVAL '8 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789003', 'familie', 'de', 'en', NOW() - INTERVAL '6 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789003', 'zeit', 'de', 'en', NOW() - INTERVAL '4 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789003', 'schön', 'de', 'en', NOW() - INTERVAL '2 days');

-- Add reviews for User 4 to get ~62 total reviews
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT 'A1B2C3D4-5678-90AB-CDEF-123456789003', sw.id, 
       CASE WHEN (i % 3) = 0 THEN false ELSE true END,
       NOW() - INTERVAL '11 days' + (i::text || ' hours')::interval, 
       NOW() + INTERVAL '3 days' 
FROM saved_words sw, generate_series(1, 62) as i 
WHERE sw.user_id = 'A1B2C3D4-5678-90AB-CDEF-123456789003' 
  AND sw.id = (SELECT MIN(id) FROM saved_words WHERE user_id = sw.user_id);

-- Demo User 5: WordSeeker (Italian learner, 45 reviews)
INSERT INTO saved_words (user_id, word, learning_language, native_language, created_at) VALUES
('A1B2C3D4-5678-90AB-CDEF-123456789004', 'ciao', 'it', 'en', NOW() - INTERVAL '10 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789004', 'grazie', 'it', 'en', NOW() - INTERVAL '8 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789004', 'amore', 'it', 'en', NOW() - INTERVAL '6 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789004', 'famiglia', 'it', 'en', NOW() - INTERVAL '4 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789004', 'tempo', 'it', 'en', NOW() - INTERVAL '2 days');

-- Add reviews for User 5 to get ~45 total reviews
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT 'A1B2C3D4-5678-90AB-CDEF-123456789004', sw.id, 
       CASE WHEN (i % 4) = 0 THEN false ELSE true END,
       NOW() - INTERVAL '9 days' + (i::text || ' hours')::interval, 
       NOW() + INTERVAL '4 days' 
FROM saved_words sw, generate_series(1, 45) as i 
WHERE sw.user_id = 'A1B2C3D4-5678-90AB-CDEF-123456789004' 
  AND sw.id = (SELECT MIN(id) FROM saved_words WHERE user_id = sw.user_id);

-- Demo User 6: BraveStudent (Portuguese learner, 33 reviews)
INSERT INTO saved_words (user_id, word, learning_language, native_language, created_at) VALUES
('A1B2C3D4-5678-90AB-CDEF-123456789005', 'olá', 'pt', 'en', NOW() - INTERVAL '8 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789005', 'obrigado', 'pt', 'en', NOW() - INTERVAL '6 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789005', 'amor', 'pt', 'en', NOW() - INTERVAL '4 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789005', 'família', 'pt', 'en', NOW() - INTERVAL '2 days');

-- Add reviews for User 6 to get ~33 total reviews
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT 'A1B2C3D4-5678-90AB-CDEF-123456789005', sw.id, 
       CASE WHEN (i % 3) = 0 THEN false ELSE true END,
       NOW() - INTERVAL '7 days' + (i::text || ' hours')::interval, 
       NOW() + INTERVAL '5 days' 
FROM saved_words sw, generate_series(1, 33) as i 
WHERE sw.user_id = 'A1B2C3D4-5678-90AB-CDEF-123456789005' 
  AND sw.id = (SELECT MIN(id) FROM saved_words WHERE user_id = sw.user_id);

-- Demo User 7: KnowledgeHunter (Japanese learner, 25 reviews)
INSERT INTO saved_words (user_id, word, learning_language, native_language, created_at) VALUES
('A1B2C3D4-5678-90AB-CDEF-123456789006', 'こんにちは', 'ja', 'en', NOW() - INTERVAL '6 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789006', 'ありがとう', 'ja', 'en', NOW() - INTERVAL '4 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789006', '愛', 'ja', 'en', NOW() - INTERVAL '2 days');

-- Add reviews for User 7 to get ~25 total reviews
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT 'A1B2C3D4-5678-90AB-CDEF-123456789006', sw.id, 
       CASE WHEN (i % 5) = 0 THEN false ELSE true END,
       NOW() - INTERVAL '5 days' + (i::text || ' hours')::interval, 
       NOW() + INTERVAL '6 days' 
FROM saved_words sw, generate_series(1, 25) as i 
WHERE sw.user_id = 'A1B2C3D4-5678-90AB-CDEF-123456789006' 
  AND sw.id = (SELECT MIN(id) FROM saved_words WHERE user_id = sw.user_id);

-- Demo User 8: WisdomSeeker (Korean learner, 18 reviews)
INSERT INTO saved_words (user_id, word, learning_language, native_language, created_at) VALUES
('A1B2C3D4-5678-90AB-CDEF-123456789007', '안녕하세요', 'ko', 'en', NOW() - INTERVAL '5 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789007', '감사합니다', 'ko', 'en', NOW() - INTERVAL '3 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789007', '사랑', 'ko', 'en', NOW() - INTERVAL '1 day');

-- Add reviews for User 8 to get ~18 total reviews
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT 'A1B2C3D4-5678-90AB-CDEF-123456789007', sw.id, 
       CASE WHEN (i % 4) = 0 THEN false ELSE true END,
       NOW() - INTERVAL '4 days' + (i::text || ' hours')::interval, 
       NOW() + INTERVAL '7 days' 
FROM saved_words sw, generate_series(1, 18) as i 
WHERE sw.user_id = 'A1B2C3D4-5678-90AB-CDEF-123456789007' 
  AND sw.id = (SELECT MIN(id) FROM saved_words WHERE user_id = sw.user_id);

-- Demo User 9: ProgressMaker (Russian learner, 12 reviews)
INSERT INTO saved_words (user_id, word, learning_language, native_language, created_at) VALUES
('A1B2C3D4-5678-90AB-CDEF-123456789008', 'привет', 'ru', 'en', NOW() - INTERVAL '4 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789008', 'спасибо', 'ru', 'en', NOW() - INTERVAL '2 days');

-- Add reviews for User 9 to get ~12 total reviews
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT 'A1B2C3D4-5678-90AB-CDEF-123456789008', sw.id, 
       CASE WHEN (i % 3) = 0 THEN false ELSE true END,
       NOW() - INTERVAL '3 days' + (i::text || ' hours')::interval, 
       NOW() + INTERVAL '8 days' 
FROM saved_words sw, generate_series(1, 12) as i 
WHERE sw.user_id = 'A1B2C3D4-5678-90AB-CDEF-123456789008' 
  AND sw.id = (SELECT MIN(id) FROM saved_words WHERE user_id = sw.user_id);

-- Demo User 10: NewBeginning (Arabic learner, 5 reviews - just started)
INSERT INTO saved_words (user_id, word, learning_language, native_language, created_at) VALUES
('A1B2C3D4-5678-90AB-CDEF-123456789009', 'مرحبا', 'ar', 'en', NOW() - INTERVAL '2 days'),
('A1B2C3D4-5678-90AB-CDEF-123456789009', 'شكرا', 'ar', 'en', NOW() - INTERVAL '1 day');

-- Add minimal reviews for User 10 to get ~5 total reviews
INSERT INTO reviews (user_id, word_id, response, reviewed_at, next_review_date) 
SELECT 'A1B2C3D4-5678-90AB-CDEF-123456789009', sw.id, 
       true,
       NOW() - INTERVAL '1 day' + (i::text || ' hours')::interval, 
       NOW() + INTERVAL '9 days' 
FROM saved_words sw, generate_series(1, 5) as i 
WHERE sw.user_id = 'A1B2C3D4-5678-90AB-CDEF-123456789009' 
  AND sw.id = (SELECT MIN(id) FROM saved_words WHERE user_id = sw.user_id);

-- Print summary for all demo users (leaderboard order)
SELECT 
    up.user_name,
    up.learning_language,
    COUNT(DISTINCT sw.id) as saved_words,
    COUNT(r.id) as total_reviews,
    COUNT(CASE WHEN r.response = true THEN 1 END) as successful_reviews
FROM user_preferences up
LEFT JOIN saved_words sw ON up.user_id = sw.user_id
LEFT JOIN reviews r ON sw.id = r.word_id
WHERE up.user_id IN (
    '5E0DAFB6-756C-463E-8061-F88DEAC2E20B',
    'A1B2C3D4-5678-90AB-CDEF-123456789001',
    'A1B2C3D4-5678-90AB-CDEF-123456789002',
    'A1B2C3D4-5678-90AB-CDEF-123456789003',
    'A1B2C3D4-5678-90AB-CDEF-123456789004',
    'A1B2C3D4-5678-90AB-CDEF-123456789005',
    'A1B2C3D4-5678-90AB-CDEF-123456789006',
    'A1B2C3D4-5678-90AB-CDEF-123456789007',
    'A1B2C3D4-5678-90AB-CDEF-123456789008',
    'A1B2C3D4-5678-90AB-CDEF-123456789009'
)
GROUP BY up.user_id, up.user_name, up.learning_language
ORDER BY total_reviews DESC;