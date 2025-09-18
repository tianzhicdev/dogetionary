-- Migration: Add pronunciation practice table
-- This table stores user pronunciation practice attempts with audio and results

CREATE TABLE pronunciation_practice (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    original_text TEXT NOT NULL,
    user_audio BYTEA NOT NULL,
    speech_to_text TEXT,
    result BOOLEAN NOT NULL,
    similarity_score FLOAT CHECK (similarity_score >= 0 AND similarity_score <= 1),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB DEFAULT '{}',

    -- Foreign key to user_preferences
    CONSTRAINT fk_pronunciation_user_id
    FOREIGN KEY (user_id) REFERENCES user_preferences(user_id) ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX idx_pronunciation_user_id ON pronunciation_practice(user_id);
CREATE INDEX idx_pronunciation_created_at ON pronunciation_practice(created_at DESC);
CREATE INDEX idx_pronunciation_result ON pronunciation_practice(result);
CREATE INDEX idx_pronunciation_user_date ON pronunciation_practice(user_id, created_at DESC);

-- Index for analytics queries
CREATE INDEX idx_pronunciation_daily ON pronunciation_practice(
    DATE(created_at),
    result
);

COMMENT ON TABLE pronunciation_practice IS 'Stores user pronunciation practice attempts with speech-to-text results';
COMMENT ON COLUMN pronunciation_practice.original_text IS 'The word or sentence the user is trying to pronounce';
COMMENT ON COLUMN pronunciation_practice.user_audio IS 'Binary audio data of user recording';
COMMENT ON COLUMN pronunciation_practice.speech_to_text IS 'Text recognized from user audio by OpenAI Whisper';
COMMENT ON COLUMN pronunciation_practice.result IS 'Whether pronunciation was considered correct';
COMMENT ON COLUMN pronunciation_practice.similarity_score IS 'Similarity score between original and recognized text (0-1)';
COMMENT ON COLUMN pronunciation_practice.metadata IS 'JSON metadata including word_id, language, source type, etc.';