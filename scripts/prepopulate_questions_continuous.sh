#!/bin/bash
# Continuous Question Pre-population Script
# Processes words one at a time with real-time progress
#
# Usage:
#   ./prepopulate_questions_continuous.sh                    # Use localhost
#   ./prepopulate_questions_continuous.sh https://kwafy.com/api  # Use production

set -e  # Exit on error

# Configuration
BACKEND_URL="${1:-http://localhost:5001}"
SOURCE="tianz_test"
LEARNING_LANG="en"
NATIVE_LANG="zh"

echo "================================================================================"
echo "🔄 CONTINUOUS QUESTION PRE-POPULATION (One word at a time)"
echo "================================================================================"
echo "Backend URL: $BACKEND_URL"
echo "Source: $SOURCE"
echo "Learning Language: $LEARNING_LANG"
echo "Native Language: $NATIVE_LANG"
echo "================================================================================"
echo ""

# Get word list from database
echo "🔍 Fetching word list from database..."
WORD_LIST=$(python3 -c "
import sys
sys.path.insert(0, '../src')
from utils.database import db_fetch_all

words = db_fetch_all('''
    SELECT word
    FROM test_vocabularies
    WHERE is_tianz = true
    AND language = %s
    ORDER BY word
''', ('$LEARNING_LANG',))

for row in words:
    print(row['word'])
")

# Convert to array
mapfile -t WORDS <<< "$WORD_LIST"
TOTAL_WORDS=${#WORDS[@]}

echo "📊 Total words to process: $TOTAL_WORDS"
echo ""

# Confirm before starting
read -p "▶️  Press ENTER to start continuous processing (or Ctrl+C to cancel)..."
echo ""

# Track statistics
PROCESSED=0
NEW_QUESTIONS=0
CACHED_QUESTIONS=0
ERRORS=0
START_TIME=$(date +%s)

# Process each word one at a time
for word in "${WORDS[@]}"; do
    PROCESSED=$((PROCESSED + 1))

    echo "================================================================================"
    echo "[$PROCESSED/$TOTAL_WORDS] Processing: $word"
    echo "================================================================================"

    # Call API for this single word
    RESPONSE=$(python3 prepopulate_questions.py \
        --words "$word" \
        --backend-url "$BACKEND_URL" \
        --learning-language "$LEARNING_LANG" \
        --native-language "$NATIVE_LANG" 2>&1)

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        # Extract statistics from response
        NEW=$(echo "$RESPONSE" | grep "New Generations:" | awk '{print $3}' || echo "0")
        CACHED=$(echo "$RESPONSE" | grep "Cache Hits:" | awk '{print $3}' || echo "0")

        NEW_QUESTIONS=$((NEW_QUESTIONS + NEW))
        CACHED_QUESTIONS=$((CACHED_QUESTIONS + CACHED))

        echo "✅ Word '$word' complete: $NEW new, $CACHED cached"
    else
        ERRORS=$((ERRORS + 1))
        echo "❌ Word '$word' failed"
        echo "$RESPONSE"

        # Ask user whether to continue or stop
        echo ""
        read -p "⚠️  Error occurred. Continue with next word? (y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "🛑 Stopping at user request"
            break
        fi
    fi

    # Show running statistics every 10 words
    if [ $((PROCESSED % 10)) -eq 0 ]; then
        ELAPSED=$(($(date +%s) - START_TIME))
        AVG_TIME=$((ELAPSED / PROCESSED))
        REMAINING=$((TOTAL_WORDS - PROCESSED))
        ETA=$((REMAINING * AVG_TIME))
        ETA_MIN=$((ETA / 60))

        echo ""
        echo "📊 Progress Update:"
        echo "   Processed: $PROCESSED/$TOTAL_WORDS words"
        echo "   New questions: $NEW_QUESTIONS"
        echo "   Cached: $CACHED_QUESTIONS"
        echo "   Errors: $ERRORS"
        echo "   Avg time per word: ${AVG_TIME}s"
        echo "   ETA: ~${ETA_MIN} minutes"
        echo ""
    fi

    echo ""
done

# Calculate final statistics
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo "================================================================================"
echo "🎉 PROCESSING COMPLETE!"
echo "================================================================================"
echo "Words processed: $PROCESSED/$TOTAL_WORDS"
echo "New questions generated: $NEW_QUESTIONS"
echo "Questions from cache: $CACHED_QUESTIONS"
echo "Errors: $ERRORS"
echo "Total duration: ${MINUTES}m ${SECONDS}s"
echo "Average per word: $((DURATION / PROCESSED))s"
echo "================================================================================"
echo ""
echo "✨ Questions are cached! Review sessions will be fast."
echo ""
