-- Migration: Add enhanced review questions support
-- Description: Add review_questions cache table and question_type tracking

-- Create review_questions cache table
CREATE TABLE IF NOT EXISTS review_questions (
    id SERIAL PRIMARY KEY,
    word VARCHAR(255) NOT NULL,
    learning_language VARCHAR(10) NOT NULL,
    native_language VARCHAR(10) NOT NULL,
    question_type VARCHAR(50) NOT NULL,  -- 'recognition', 'mc_definition', 'mc_word', 'fill_blank'
    question_data JSONB NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(word, learning_language, native_language, question_type)
);

-- Create index for fast lookups
CREATE INDEX IF NOT EXISTS idx_review_questions_lookup
ON review_questions(word, learning_language, native_language, question_type);

-- Add question_type column to reviews table
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS question_type VARCHAR(50) DEFAULT 'recognition';

-- Create index on question_type for analytics
CREATE INDEX IF NOT EXISTS idx_reviews_question_type ON reviews(question_type);

-- Add comment for documentation
COMMENT ON TABLE review_questions IS 'Cache for LLM-generated review questions to avoid regenerating same questions';
COMMENT ON COLUMN reviews.question_type IS 'Type of question shown during review: recognition, mc_definition, mc_word, fill_blank';
