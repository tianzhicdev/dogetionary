#!/bin/bash

# Database migration script to add missing columns and tables
set -e

echo "🔄 Running database migration..."

# Function to detect Docker Compose command
get_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo "❌ Docker Compose not found!"
        exit 1
    fi
}

COMPOSE_CMD=$(get_compose_cmd)

# Execute migration SQL
echo "📝 Adding missing columns and tables..."

$COMPOSE_CMD exec postgres psql -U dogeuser -d dogetionary << 'EOF'
-- Add spaced repetition columns to saved_words if they don't exist
ALTER TABLE saved_words 
    ADD COLUMN IF NOT EXISTS review_count INTEGER DEFAULT 0,
    ADD COLUMN IF NOT EXISTS ease_factor DECIMAL(3,1) DEFAULT 2.5,
    ADD COLUMN IF NOT EXISTS interval_days INTEGER DEFAULT 1,
    ADD COLUMN IF NOT EXISTS next_review_date DATE DEFAULT CURRENT_DATE + INTERVAL '1 day',
    ADD COLUMN IF NOT EXISTS last_reviewed_at TIMESTAMP NULL;

-- Add audio_data column to words table if it doesn't exist
ALTER TABLE words 
    ADD COLUMN IF NOT EXISTS audio_data TEXT NULL;

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_saved_words_next_review_date ON saved_words(next_review_date);
CREATE INDEX IF NOT EXISTS idx_saved_words_user_next_review ON saved_words(user_id, next_review_date);

-- Create the reviews table if it doesn't exist
CREATE TABLE IF NOT EXISTS reviews (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    word_id INTEGER NOT NULL REFERENCES saved_words(id) ON DELETE CASCADE,
    response BOOLEAN NOT NULL,
    response_time_ms INTEGER NULL,
    review_type VARCHAR(50) DEFAULT 'regular',
    reviewed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for reviews table
CREATE INDEX IF NOT EXISTS idx_reviews_user_id ON reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_word_id ON reviews(word_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewed_at ON reviews(reviewed_at);

-- Show table structure
\d saved_words
\d words
\d reviews
EOF

echo "✅ Database migration completed!"
echo ""
echo "🧪 Testing API endpoints..."

# Test the API
echo "Testing word endpoint..."
curl -s 'https://dogetionary.webhop.net/api/word?w=test' | head -3

echo ""
echo "Testing health endpoint..."
curl -s 'https://dogetionary.webhop.net/api/health'

echo ""
echo "🎉 Migration complete! API should now work properly."