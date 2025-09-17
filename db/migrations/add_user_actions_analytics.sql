-- Migration: Add user actions analytics table
-- This migration adds comprehensive user action tracking for analytics

-- User Actions Analytics Table
CREATE TABLE user_actions (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,
    category VARCHAR(30) NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    session_id VARCHAR(100),
    platform VARCHAR(20) DEFAULT 'ios',
    app_version VARCHAR(20)
);

-- Indexes for performance
CREATE INDEX idx_user_actions_user_id ON user_actions(user_id);
CREATE INDEX idx_user_actions_action ON user_actions(action);
CREATE INDEX idx_user_actions_category ON user_actions(category);
CREATE INDEX idx_user_actions_created_at ON user_actions(created_at DESC);
CREATE INDEX idx_user_actions_user_date ON user_actions(user_id, created_at DESC);

-- Compound index for daily analytics
CREATE INDEX idx_user_actions_daily ON user_actions(
    DATE(created_at),
    action
);

-- Action enum constraint for data integrity
ALTER TABLE user_actions
ADD CONSTRAINT valid_action CHECK (
    action IN (
        'dictionary_search',
        'dictionary_search_audio',
        'dictionary_save',
        'dictionary_example_audio',
        'dictionary_illustration',
        'review_start',
        'review_answer_correct',
        'review_answer_incorrect',
        'review_audio',
        'review_next',
        'review_complete',
        'nav_tab_dictionary',
        'nav_tab_saved',
        'nav_tab_review',
        'nav_tab_leaderboard',
        'nav_tab_settings',
        'profile_name_update',
        'profile_motto_update',
        'profile_language_learning',
        'profile_language_native',
        'settings_notification_enable',
        'settings_notification_disable',
        'settings_notification_time',
        'settings_timezone_update',
        'saved_view_details',
        'feedback_submit',
        'app_launch',
        'app_background',
        'app_foreground'
    )
);

-- Add foreign key constraint to user_preferences
ALTER TABLE user_actions
ADD CONSTRAINT fk_user_actions_user_id
FOREIGN KEY (user_id) REFERENCES user_preferences(user_id) ON DELETE CASCADE;