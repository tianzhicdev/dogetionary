-- Add audio support to words table
ALTER TABLE words ADD COLUMN IF NOT EXISTS audio_data BYTEA;
ALTER TABLE words ADD COLUMN IF NOT EXISTS audio_content_type VARCHAR(50) DEFAULT 'audio/mpeg';
ALTER TABLE words ADD COLUMN IF NOT EXISTS audio_generated_at TIMESTAMP;

-- Create index on audio_generated_at for audio cache management
CREATE INDEX IF NOT EXISTS idx_words_audio_generated_at ON words(audio_generated_at);

-- Add comment for documentation
COMMENT ON COLUMN words.audio_data IS 'Cached MP3 audio data from OpenAI TTS API';
COMMENT ON COLUMN words.audio_content_type IS 'MIME type of the audio data (e.g., audio/mpeg)';
COMMENT ON COLUMN words.audio_generated_at IS 'Timestamp when the audio was generated and cached';