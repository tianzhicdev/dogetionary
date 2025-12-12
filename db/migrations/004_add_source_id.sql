-- Migration: Add source_id to videos and word_to_video tables
-- Purpose: Track which pipeline run created each video/mapping for debugging
-- Created: 2025-12-11

-- Add source_id to videos table
ALTER TABLE videos
ADD COLUMN IF NOT EXISTS source_id VARCHAR(100);

-- Add source_id to word_to_video table
ALTER TABLE word_to_video
ADD COLUMN IF NOT EXISTS source_id VARCHAR(100);

-- Add indexes for efficient filtering by source_id
CREATE INDEX IF NOT EXISTS idx_videos_source_id ON videos(source_id);
CREATE INDEX IF NOT EXISTS idx_word_to_video_source_id ON word_to_video(source_id);

-- Add comments
COMMENT ON COLUMN videos.source_id IS 'Pipeline run identifier (e.g., find_videos_20251211_143022) for debugging and reporting';
COMMENT ON COLUMN word_to_video.source_id IS 'Pipeline run identifier (e.g., find_videos_20251211_143022) for debugging and reporting';
