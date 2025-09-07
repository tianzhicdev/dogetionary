-- Add review system support to the database
-- This migration adds a reviews table for tracking review history
-- and extends saved_words table with review scheduling fields

-- Create reviews table for tracking all review sessions
CREATE TABLE IF NOT EXISTS reviews (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    word_id INTEGER NOT NULL,
    response BOOLEAN NOT NULL, -- true for "yes", false for "no"
    response_time_ms INTEGER, -- how long user took to respond (optional)
    reviewed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_reviews_user_date ON reviews(user_id, reviewed_at);
CREATE INDEX IF NOT EXISTS idx_reviews_word_date ON reviews(word_id, reviewed_at);

-- Extend saved_words table with review scheduling fields
ALTER TABLE saved_words ADD COLUMN IF NOT EXISTS review_count INTEGER DEFAULT 0;
ALTER TABLE saved_words ADD COLUMN IF NOT EXISTS ease_factor DECIMAL(3,2) DEFAULT 2.5;
ALTER TABLE saved_words ADD COLUMN IF NOT EXISTS interval_days INTEGER DEFAULT 1;
ALTER TABLE saved_words ADD COLUMN IF NOT EXISTS next_review_date DATE DEFAULT CURRENT_DATE + INTERVAL '1 day';
ALTER TABLE saved_words ADD COLUMN IF NOT EXISTS last_reviewed_at TIMESTAMP;

-- Add index for efficient due word queries
CREATE INDEX IF NOT EXISTS idx_saved_words_next_review ON saved_words(user_id, next_review_date);

-- Add foreign key constraint (will only work if saved_words.id exists)
-- Note: We'll add this constraint in the backend to handle cases where saved_words table structure varies
-- ALTER TABLE reviews ADD CONSTRAINT fk_reviews_word_id FOREIGN KEY (word_id) REFERENCES saved_words(id) ON DELETE CASCADE;