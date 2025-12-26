-- Migration 010: Add reported_content table for user reports
-- Created: 2025-12-25
-- Purpose: Allow users to report inappropriate, incorrect, or problematic question content

CREATE TABLE reported_content (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES user_preferences(user_id) ON DELETE CASCADE,

    -- Question identification (matches review_questions table structure)
    word VARCHAR(255) NOT NULL,
    learning_language VARCHAR(10) NOT NULL,
    native_language VARCHAR(10) NOT NULL,
    question_type VARCHAR(50) NOT NULL,

    -- Video-specific (optional, only for video_mc questions)
    video_id INTEGER,

    -- Report details
    report_type VARCHAR(50) NOT NULL,  -- Flexible text field: 'Inappropriate', 'Incorrect', 'Copyright', 'Other'
    comment TEXT,  -- Optional user comment (for future enhancement)

    -- Metadata and admin workflow
    reported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'pending',  -- 'pending', 'reviewed', 'resolved', 'dismissed'
    reviewed_by VARCHAR(100),  -- Admin who reviewed (for future)
    reviewed_at TIMESTAMP,

    -- Prevent spam: unique constraint per user+question+type
    UNIQUE(user_id, word, learning_language, native_language, question_type, report_type)
);

-- Indexes for efficient queries
CREATE INDEX idx_reported_content_status ON reported_content(status, reported_at DESC);
CREATE INDEX idx_reported_content_user ON reported_content(user_id);
CREATE INDEX idx_reported_content_question ON reported_content(word, learning_language, native_language, question_type);
CREATE INDEX idx_reported_content_video ON reported_content(video_id) WHERE video_id IS NOT NULL;

-- Table and column comments
COMMENT ON TABLE reported_content IS 'User reports of inappropriate, incorrect, or problematic question content';
COMMENT ON COLUMN reported_content.report_type IS 'Flexible text field for report categories: Inappropriate, Incorrect, Copyright, Other';
COMMENT ON COLUMN reported_content.status IS 'Report status: pending (new), reviewed (admin viewed), resolved (fixed), dismissed (invalid)';
COMMENT ON COLUMN reported_content.video_id IS 'Video ID for video_mc questions (enables filtering copyright reports by video)';
