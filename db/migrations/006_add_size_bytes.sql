-- Migration: Add size_bytes to videos table
-- Purpose: Track video file size for filtering and optimization
-- Created: 2025-12-11

-- Add size_bytes column
ALTER TABLE videos
ADD COLUMN IF NOT EXISTS size_bytes INTEGER;

-- Add index for filtering by size
CREATE INDEX IF NOT EXISTS idx_videos_size_bytes ON videos(size_bytes);

-- Add comment
COMMENT ON COLUMN videos.size_bytes IS 'Video file size in bytes';
