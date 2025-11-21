-- Dogetionary Database Schema v4 - Ultra Simplified Architecture
-- Minimal tables with calculated spaced repetition

-- User Preferences Table (language settings)
CREATE TABLE user_preferences (
    user_id UUID PRIMARY KEY,
    learning_language VARCHAR(10) DEFAULT 'en',
    native_language VARCHAR(10) DEFAULT 'zh',
    user_name VARCHAR(255),
    user_motto TEXT,
    -- Test preparation settings
    toefl_enabled BOOLEAN DEFAULT FALSE,
    ielts_enabled BOOLEAN DEFAULT FALSE,
    last_test_words_added DATE,
    toefl_target_days INTEGER DEFAULT 30,
    ielts_target_days INTEGER DEFAULT 30,
    -- Notification settings
    push_notifications_enabled BOOLEAN DEFAULT TRUE,
    email_notifications_enabled BOOLEAN DEFAULT FALSE,
    daily_reminder_time TIME DEFAULT '09:00:00',
    weekly_report_enabled BOOLEAN DEFAULT TRUE,
    streak_notifications_enabled BOOLEAN DEFAULT TRUE,
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
    schema_version INTEGER NOT NULL DEFAULT 1,
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
    native_language VARCHAR(10) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(user_id, word, learning_language, native_language)
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
CREATE INDEX idx_definitions_schema_version ON definitions(schema_version);
CREATE INDEX idx_saved_words_user_id ON saved_words(user_id);
CREATE INDEX idx_reviews_user_id ON reviews(user_id);
CREATE INDEX idx_reviews_word_id ON reviews(word_id);
CREATE INDEX idx_reviews_reviewed_at ON reviews(reviewed_at);
CREATE INDEX idx_reviews_next_review_date ON reviews(next_review_date);
CREATE INDEX idx_user_preferences_learning_lang ON user_preferences(learning_language);
CREATE INDEX idx_user_preferences_native_lang ON user_preferences(native_language);

-- Test vocabulary table to store TOEFL/IELTS words
CREATE TABLE test_vocabularies (
    word VARCHAR(100) NOT NULL,
    language VARCHAR(10) NOT NULL DEFAULT 'en',
    is_toefl BOOLEAN DEFAULT FALSE,
    is_ielts BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (word, language)
);

-- User actions analytics table
CREATE TABLE user_actions (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,
    category VARCHAR(30) NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    session_id VARCHAR(100),
    platform VARCHAR(20) DEFAULT 'ios'::character varying,
    app_version VARCHAR(20),
    CONSTRAINT fk_user_actions_user_id FOREIGN KEY (user_id) REFERENCES user_preferences(user_id) ON DELETE CASCADE
);

-- Pronunciation practice table
CREATE TABLE pronunciation_practice (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    word VARCHAR(255) NOT NULL,
    language VARCHAR(10) NOT NULL,
    user_audio_url TEXT,
    reference_audio_url TEXT,
    similarity_score FLOAT CHECK (similarity_score >= 0 AND similarity_score <= 1),
    feedback JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Notification logs table
CREATE TABLE notification_logs (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    title TEXT,
    body TEXT,
    metadata JSONB DEFAULT '{}',
    sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    opened_at TIMESTAMP,
    dismissed_at TIMESTAMP
);

-- API Usage Logs table (for tracking endpoint usage and deprecation)
CREATE TABLE api_usage_logs (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP NOT NULL DEFAULT NOW(),
    endpoint VARCHAR(255) NOT NULL,
    method VARCHAR(10) NOT NULL,
    user_id UUID,
    response_status INTEGER,
    duration_ms FLOAT,
    user_agent TEXT,
    api_version VARCHAR(10)  -- 'v1', 'v2', 'v3', or NULL for unversioned
);

-- Streak Days table (track daily completion streaks per schedule)
-- Note: This table is created by migration add_schedule_tables.sql
-- Kept here for reference but will be created by migration
-- CREATE TABLE streak_days (
--     id SERIAL PRIMARY KEY,
--     schedule_id INTEGER NOT NULL REFERENCES study_schedules(id) ON DELETE CASCADE,
--     streak_date DATE NOT NULL,
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     UNIQUE(schedule_id, streak_date)
-- );

-- Additional indexes for new tables
CREATE INDEX idx_test_vocab_toefl ON test_vocabularies(is_toefl) WHERE is_toefl = TRUE;
CREATE INDEX idx_test_vocab_ielts ON test_vocabularies(is_ielts) WHERE is_ielts = TRUE;
CREATE INDEX idx_user_pref_test_enabled ON user_preferences(user_id)
    WHERE toefl_enabled = TRUE OR ielts_enabled = TRUE;
CREATE INDEX idx_user_actions_user_id ON user_actions(user_id);
CREATE INDEX idx_user_actions_action ON user_actions(action);
CREATE INDEX idx_user_actions_category ON user_actions(category);
CREATE INDEX idx_user_actions_created_at ON user_actions(created_at DESC);
CREATE INDEX idx_user_actions_daily ON user_actions(DATE(created_at), action);
CREATE INDEX idx_user_actions_user_date ON user_actions(user_id, created_at DESC);
CREATE INDEX idx_pronunciation_user_id ON pronunciation_practice(user_id);
CREATE INDEX idx_pronunciation_word ON pronunciation_practice(word);
CREATE INDEX idx_notification_logs_user_id ON notification_logs(user_id);
CREATE INDEX idx_notification_logs_type ON notification_logs(notification_type);
CREATE INDEX idx_api_usage_endpoint_timestamp ON api_usage_logs(endpoint, timestamp DESC);
CREATE INDEX idx_api_usage_timestamp ON api_usage_logs(timestamp DESC);
CREATE INDEX idx_api_usage_user_id ON api_usage_logs(user_id);
-- Streak days index created by migration
-- CREATE INDEX idx_streak_days_schedule_date ON streak_days(schedule_id, streak_date DESC);
