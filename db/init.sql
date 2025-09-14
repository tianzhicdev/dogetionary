-- Dogetionary Database Schema v4 - Ultra Simplified Architecture
-- Minimal tables with calculated spaced repetition

-- User Preferences Table (language settings)
CREATE TABLE user_preferences (
    user_id UUID PRIMARY KEY,
    learning_language VARCHAR(10) DEFAULT 'en',
    native_language VARCHAR(10) DEFAULT 'zh',
    user_name VARCHAR(255),
    user_motto TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Simple Audio Table (text + language -> audio bytes)
CREATE TABLE audio (
    text_content TEXT NOT NULL,
    language VARCHAR(10) NOT NULL,
    audio_data BYTEA NOT NULL,
    content_type VARCHAR(50) DEFAULT 'audio/mpeg',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (text_content, language)
);

-- Language-Specific Definitions Table
CREATE TABLE definitions (
    word VARCHAR(255) NOT NULL,
    learning_language VARCHAR(10) NOT NULL,
    native_language VARCHAR(10) NOT NULL,
    definition_data JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (word, learning_language, native_language)
);

-- Minimal Saved Words Table (user's vocabulary)
CREATE TABLE saved_words (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    word VARCHAR(255) NOT NULL,
    learning_language VARCHAR(10) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(user_id, word, learning_language)
);

-- Minimal Review History Table (track all review responses)
CREATE TABLE reviews (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    word_id INTEGER NOT NULL REFERENCES saved_words(id) ON DELETE CASCADE,
    response BOOLEAN NOT NULL,
    reviewed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    next_review_date TIMESTAMP
);

-- Create illustration table for AI-generated word illustrations
CREATE TABLE illustrations (
    word VARCHAR(255) NOT NULL,
    language VARCHAR(10) NOT NULL,
    scene_description TEXT NOT NULL,
    image_data BYTEA NOT NULL,
    content_type VARCHAR(50) DEFAULT 'image/png',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (word, language)
);

-- Add index for better performance
CREATE INDEX idx_illustrations_word_lang ON illustrations(word, language);

-- User Feedback Table
CREATE TABLE user_feedback (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    feedback TEXT NOT NULL CHECK (LENGTH(feedback) <= 500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add index for feedback queries
CREATE INDEX idx_user_feedback_user_id ON user_feedback(user_id);
CREATE INDEX idx_user_feedback_created_at ON user_feedback(created_at);

-- Indexes for performance
CREATE INDEX idx_definitions_word_learning ON definitions(word, learning_language);
CREATE INDEX idx_saved_words_user_id ON saved_words(user_id);
CREATE INDEX idx_reviews_user_id ON reviews(user_id);
CREATE INDEX idx_reviews_word_id ON reviews(word_id);
CREATE INDEX idx_reviews_reviewed_at ON reviews(reviewed_at);
CREATE INDEX idx_reviews_next_review_date ON reviews(next_review_date);
CREATE INDEX idx_user_preferences_learning_lang ON user_preferences(learning_language);
CREATE INDEX idx_user_preferences_native_lang ON user_preferences(native_language);

-- Sample data
INSERT INTO user_preferences (user_id, learning_language, native_language) 
VALUES ('00000000-0000-0000-0000-000000000001', 'en', 'zh');