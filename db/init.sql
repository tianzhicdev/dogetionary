-- Create the saved_words table
CREATE TABLE IF NOT EXISTS saved_words (
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

-- Create index on user_id for faster queries
CREATE INDEX IF NOT EXISTS idx_saved_words_user_id ON saved_words(user_id);

-- Create index on created_at for sorting
CREATE INDEX IF NOT EXISTS idx_saved_words_created_at ON saved_words(created_at);

-- Create index on next_review_date for due words queries
CREATE INDEX IF NOT EXISTS idx_saved_words_next_review_date ON saved_words(next_review_date);

-- Create compound index for user + next_review_date queries
CREATE INDEX IF NOT EXISTS idx_saved_words_user_next_review ON saved_words(user_id, next_review_date);

-- Create the words table for caching LLM results
CREATE TABLE IF NOT EXISTS words (
    id SERIAL PRIMARY KEY,
    word VARCHAR(255) NOT NULL UNIQUE,
    word_lower VARCHAR(255) NOT NULL,
    definition_data JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    access_count INTEGER DEFAULT 1,
    last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Audio data for pronunciations
    audio_data TEXT NULL
);

-- Create index on word (case-insensitive) for faster lookups
CREATE INDEX IF NOT EXISTS idx_words_word_lower ON words(word_lower);

-- Create index on last_accessed for cache cleanup if needed
CREATE INDEX IF NOT EXISTS idx_words_last_accessed ON words(last_accessed);

-- Create the reviews table for tracking review history
CREATE TABLE IF NOT EXISTS reviews (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    word_id INTEGER NOT NULL REFERENCES saved_words(id) ON DELETE CASCADE,
    response BOOLEAN NOT NULL,
    response_time_ms INTEGER NULL,
    review_type VARCHAR(50) DEFAULT 'regular',
    reviewed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for reviews table
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_word_id ON reviews(word_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewed_at ON reviews(reviewed_at);