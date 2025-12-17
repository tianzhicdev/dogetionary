-- Migration 010: Create user_badges table for tracking earned/shown badges
-- Date: 2025-12-17
-- Description: Track which badges users have earned and shown to prevent duplicate celebrations

BEGIN;

-- Create user_badges table
CREATE TABLE IF NOT EXISTS user_badges (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES user_preferences(user_id) ON DELETE CASCADE,
    badge_id VARCHAR(100) NOT NULL,  -- e.g., "DEMO", "BUSINESS_ENGLISH", "score_1000"
    badge_type VARCHAR(50) NOT NULL CHECK (badge_type IN ('test_completion', 'score_milestone')),
    earned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    shown_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,  -- Set when badge is first returned to client

    -- Ensure each user can only earn each badge once
    CONSTRAINT unique_user_badge UNIQUE(user_id, badge_id)
);

-- Create indexes for efficient lookups
CREATE INDEX idx_user_badges_user ON user_badges(user_id);
CREATE INDEX idx_user_badges_badge_id ON user_badges(badge_id);
CREATE INDEX idx_user_badges_type ON user_badges(badge_type);
CREATE INDEX idx_user_badges_earned_at ON user_badges(earned_at DESC);

-- Add comments for documentation
COMMENT ON TABLE user_badges IS 'Tracks which badges users have earned to prevent duplicate celebrations';
COMMENT ON COLUMN user_badges.badge_id IS 'Unique identifier for badge (e.g., DEMO, score_1000)';
COMMENT ON COLUMN user_badges.badge_type IS 'Type of badge: test_completion or score_milestone';
COMMENT ON COLUMN user_badges.earned_at IS 'Timestamp when badge was first earned';
COMMENT ON COLUMN user_badges.shown_at IS 'Timestamp when badge was first shown to user (same as earned_at for new badges)';

COMMIT;
