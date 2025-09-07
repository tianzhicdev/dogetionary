-- Create the saved_words table
CREATE TABLE IF NOT EXISTS saved_words (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    word VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(user_id, word)
);

-- Create index on user_id for faster queries
CREATE INDEX IF NOT EXISTS idx_saved_words_user_id ON saved_words(user_id);

-- Create index on created_at for sorting
CREATE INDEX IF NOT EXISTS idx_saved_words_created_at ON saved_words(created_at);

-- Create the words table for caching LLM results
CREATE TABLE IF NOT EXISTS words (
    id SERIAL PRIMARY KEY,
    word VARCHAR(255) NOT NULL UNIQUE,
    word_lower VARCHAR(255) NOT NULL,
    definition_data JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    access_count INTEGER DEFAULT 1,
    last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index on word (case-insensitive) for faster lookups
CREATE INDEX IF NOT EXISTS idx_words_word_lower ON words(word_lower);

-- Create index on last_accessed for cache cleanup if needed
CREATE INDEX IF NOT EXISTS idx_words_last_accessed ON words(last_accessed);