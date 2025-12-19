-- Migration 010: Add Performance Indexes for Reviews Table
-- Created: 2025-12-19
-- Purpose: Optimize review history queries and daily review lookups
--          Addresses N+1 query performance issues in schedule endpoints

-- Index 1: Word Review History Queries
-- Used by: get_word_review_history() - fetches all reviews for a specific word
-- Query pattern: SELECT * FROM reviews WHERE word_id = X ORDER BY reviewed_at DESC
-- Impact: Speeds up schedule calculation (most common query)
CREATE INDEX IF NOT EXISTS idx_reviews_word_reviewed
ON reviews(word_id, reviewed_at DESC);

-- Index 2: User Daily Review Queries
-- Used by: get_words_reviewed_on_date() - finds words reviewed by user on specific date
-- Query pattern: SELECT * FROM reviews WHERE user_id = X AND reviewed_at >= Y
-- Impact: Speeds up "reviewed today" checks in practice_status and schedule
CREATE INDEX IF NOT EXISTS idx_reviews_user_date
ON reviews(user_id, reviewed_at DESC);

-- Index 3: Composite for Review Stats
-- Used by: calculate_user_score() and other aggregation queries
-- Query pattern: SELECT COUNT(*), AVG(response) FROM reviews WHERE user_id = X
-- Impact: Faster user statistics calculation
CREATE INDEX IF NOT EXISTS idx_reviews_user_response
ON reviews(user_id, response, reviewed_at DESC);

-- Verify indexes were created
-- Run this query to confirm:
-- SELECT schemaname, tablename, indexname, indexdef
-- FROM pg_indexes
-- WHERE tablename = 'reviews'
-- ORDER BY indexname;

-- Expected performance improvement:
-- - Review history queries: 100-500ms → 10-50ms (per word)
-- - Daily review lookups: 200-800ms → 20-80ms
-- - User score calculation: 500-2000ms → 50-200ms
-- - Overall schedule endpoint: 5-10s → 0.3-0.7s (combined with N+1 fix)
