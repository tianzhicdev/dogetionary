-- Dogetionary Database Schema
-- Complete schema with all tables and indexes

-- Saved Words Table (user's vocabulary with spaced repetition)
CREATE TABLE saved_words (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    word VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb,
    -- Spaced Repetition Fields
    review_count INTEGER DEFAULT 0,
    ease_factor DECIMAL(3,1) DEFAULT 2.5,
    interval_days INTEGER DEFAULT 1,
    next_review_date DATE DEFAULT CURRENT_DATE + INTERVAL '1 day',
    last_reviewed_at TIMESTAMP NULL,
    UNIQUE(user_id, word)
);

-- Words Cache Table (LLM definitions and audio)
CREATE TABLE words (
    word_lower VARCHAR(255) PRIMARY KEY,
    definition_data JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    access_count INTEGER DEFAULT 1,
    last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Audio data (binary)
    audio_data BYTEA NULL,
    audio_content_type VARCHAR(50) DEFAULT 'audio/mpeg',
    audio_generated_at TIMESTAMP NULL
);

-- Review History Table (track all review responses)
CREATE TABLE reviews (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    word_id INTEGER NOT NULL REFERENCES saved_words(id) ON DELETE CASCADE,
    response BOOLEAN NOT NULL,
    response_time_ms INTEGER NULL,
    review_type VARCHAR(50) DEFAULT 'regular',
    reviewed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for saved_words
CREATE INDEX idx_saved_words_user_id ON saved_words(user_id);
CREATE INDEX idx_saved_words_created_at ON saved_words(created_at);
CREATE INDEX idx_saved_words_next_review_date ON saved_words(next_review_date);
CREATE INDEX idx_saved_words_user_next_review ON saved_words(user_id, next_review_date);

-- Indexes for words
CREATE INDEX idx_words_last_accessed ON words(last_accessed);

-- Indexes for reviews
CREATE INDEX idx_reviews_user_id ON reviews(user_id);
CREATE INDEX idx_reviews_word_id ON reviews(word_id);
CREATE INDEX idx_reviews_reviewed_at ON reviews(reviewed_at);