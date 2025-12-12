-- Migration: Add audio transcript support for Whisper API integration
-- Purpose: Store audio-extracted transcripts alongside metadata transcripts for improved accuracy
-- Created: 2025-12-11

-- Add audio transcript columns to videos table
ALTER TABLE videos
ADD COLUMN IF NOT EXISTS audio_transcript TEXT,
ADD COLUMN IF NOT EXISTS audio_transcript_verified BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS whisper_metadata JSONB;

-- Add transcript source tracking to word_to_video table
ALTER TABLE word_to_video
ADD COLUMN IF NOT EXISTS transcript_source VARCHAR(20) DEFAULT 'metadata',
ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP;

-- Add indexes for efficient filtering
CREATE INDEX IF NOT EXISTS idx_videos_audio_verified ON videos(audio_transcript_verified);
CREATE INDEX IF NOT EXISTS idx_word_to_video_transcript_source ON word_to_video(transcript_source);

-- Add comments
COMMENT ON COLUMN videos.audio_transcript IS 'Clean transcript extracted from video audio using Whisper API';
COMMENT ON COLUMN videos.audio_transcript_verified IS 'Whether audio transcript has been extracted and verified';
COMMENT ON COLUMN videos.whisper_metadata IS 'Whisper API metadata including word-level timestamps and confidence scores';
COMMENT ON COLUMN word_to_video.transcript_source IS 'Source of transcript used for mapping: metadata (ClipCafe) or audio (Whisper)';
COMMENT ON COLUMN word_to_video.verified_at IS 'Timestamp when audio transcript verification was completed';
