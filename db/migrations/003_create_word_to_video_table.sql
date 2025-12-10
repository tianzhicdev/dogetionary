-- Migration: Create word_to_video linking table
-- Purpose: Many-to-many relationship between words and videos
-- Created: 2025-12-09

-- Create word_to_video linking table
CREATE TABLE IF NOT EXISTS word_to_video (
    id SERIAL PRIMARY KEY,
    word VARCHAR(255) NOT NULL,
    learning_language VARCHAR(10) NOT NULL,
    video_id INTEGER NOT NULL REFERENCES videos(id) ON DELETE CASCADE,

    -- Optional relevance score for ranking videos (0.00 to 1.00)
    relevance_score DECIMAL(3,2) CHECK (relevance_score IS NULL OR (relevance_score >= 0.00 AND relevance_score <= 1.00)),

    created_at TIMESTAMP DEFAULT NOW(),

    -- Ensure each word+language can link to a video only once
    CONSTRAINT unique_word_language_video UNIQUE(word, learning_language, video_id)
);

-- Indexes for efficient lookups
CREATE INDEX IF NOT EXISTS idx_word_to_video_word ON word_to_video(word, learning_language);
CREATE INDEX IF NOT EXISTS idx_word_to_video_video_id ON word_to_video(video_id);
CREATE INDEX IF NOT EXISTS idx_word_to_video_relevance ON word_to_video(relevance_score DESC NULLS LAST);

-- Add comments for documentation
COMMENT ON TABLE word_to_video IS 'Many-to-many linking table between words and videos for video practice questions';
COMMENT ON COLUMN word_to_video.word IS 'The vocabulary word (e.g., "abdominal")';
COMMENT ON COLUMN word_to_video.learning_language IS 'Language of the word being taught (e.g., "en")';
COMMENT ON COLUMN word_to_video.video_id IS 'Foreign key to videos table';
COMMENT ON COLUMN word_to_video.relevance_score IS 'Optional quality/relevance score (0.00-1.00) for ranking videos, NULL means unscored';
