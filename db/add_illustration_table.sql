-- Create illustration table for AI-generated word illustrations
CREATE TABLE illustrations (
    word VARCHAR(255) NOT NULL,
    language VARCHAR(10) NOT NULL,
    scene_description TEXT NOT NULL,
    image_data BYTEA NOT NULL,
    content_type VARCHAR(50) DEFAULT 'image/png',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (word, language),
    FOREIGN KEY (word, language) REFERENCES definitions(word, learning_language)
);

-- Add index for better performance
CREATE INDEX idx_illustrations_word_lang ON illustrations(word, language);