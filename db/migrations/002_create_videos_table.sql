-- Migration: Create videos table for storing video content
-- Purpose: Store video files as binary data with metadata for practice mode
-- Created: 2025-12-09

-- Create videos table
CREATE TABLE IF NOT EXISTS videos (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,              -- Filename without extension (e.g., "hello", "world")
    format VARCHAR(10) NOT NULL,             -- Video format: mp4, mov, webm, etc.
    video_data BYTEA NOT NULL,               -- Binary video file content
    transcript TEXT,                          -- Optional transcript of spoken words in video
    metadata JSONB DEFAULT '{}'::jsonb,      -- Flexible metadata (duration, size, resolution, word, language, etc.)
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    -- Ensure unique combination of name and format
    CONSTRAINT unique_name_format UNIQUE(name, format)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_videos_name ON videos(name);
CREATE INDEX IF NOT EXISTS idx_videos_format ON videos(format);
CREATE INDEX IF NOT EXISTS idx_videos_metadata ON videos USING GIN(metadata);

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_videos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_videos_updated_at
    BEFORE UPDATE ON videos
    FOR EACH ROW
    EXECUTE FUNCTION update_videos_updated_at();

-- Add comments for documentation
COMMENT ON TABLE videos IS 'Stores video content for practice mode with metadata';
COMMENT ON COLUMN videos.name IS 'Filename without extension, typically the word being taught';
COMMENT ON COLUMN videos.format IS 'Video format (mp4, mov, webm)';
COMMENT ON COLUMN videos.video_data IS 'Binary video file content stored as BYTEA';
COMMENT ON COLUMN videos.transcript IS 'Optional transcript of spoken words in the video';
COMMENT ON COLUMN videos.metadata IS 'JSONB metadata including duration, size, resolution, word, language, codec, etc.';

-- Example metadata structure:
-- {
--   "duration_seconds": 5.2,
--   "file_size_bytes": 524288,
--   "resolution": "1920x1080",
--   "word": "hello",
--   "language": "en",
--   "codec": "h264",
--   "bitrate": 800000,
--   "fps": 30,
--   "tags": ["greeting", "beginner"]
-- }
