#!/bin/bash
# Batch Question Pre-population Script
# Processes all words from tianz_test in safe batches of 50 words
#
# Usage:
#   ./prepopulate_questions_batched.sh                    # Use localhost
#   ./prepopulate_questions_batched.sh https://kwafy.com/api  # Use production

set -e  # Exit on error

# Configuration
BACKEND_URL="${1:-http://localhost:5001}"
SOURCE="tianz_test"
BATCH_SIZE=50
LEARNING_LANG="en"
NATIVE_LANG="zh"

echo "================================================================================"
echo "📦 BATCH QUESTION PRE-POPULATION"
echo "================================================================================"
echo "Backend URL: $BACKEND_URL"
echo "Source: $SOURCE"
echo "Batch Size: $BATCH_SIZE words"
echo "Learning Language: $LEARNING_LANG"
echo "Native Language: $NATIVE_LANG"
echo "================================================================================"
echo ""

# Get total word count
echo "🔍 Checking total words in $SOURCE..."
TOTAL_WORDS=$(python3 -c "
import sys
sys.path.insert(0, '../src')
from utils.database import db_fetch_one
result = db_fetch_one('SELECT COUNT(*) as count FROM test_vocabularies WHERE is_tianz = true AND language = %s', ('$LEARNING_LANG',))
print(result['count'] if result else 0)
")

echo "📊 Total words to process: $TOTAL_WORDS"
echo ""

# Calculate number of batches
BATCHES=$(( ($TOTAL_WORDS + $BATCH_SIZE - 1) / $BATCH_SIZE ))
echo "🎯 Will run $BATCHES batches of $BATCH_SIZE words each"
echo ""

# Confirm before starting
read -p "▶️  Press ENTER to start batch processing (or Ctrl+C to cancel)..."
echo ""

# Track overall statistics
TOTAL_NEW=0
TOTAL_CACHED=0
TOTAL_ERRORS=0
START_TIME=$(date +%s)

# Process in batches
for ((batch=1; batch<=BATCHES; batch++)); do
    MAX_WORDS=$((batch * BATCH_SIZE))

    echo "================================================================================"
    echo "📦 BATCH $batch/$BATCHES (processing up to word $MAX_WORDS)"
    echo "================================================================================"

    # Run prepopulation
    python3 prepopulate_questions.py \
        --source "$SOURCE" \
        --backend-url "$BACKEND_URL" \
        --learning-language "$LEARNING_LANG" \
        --native-language "$NATIVE_LANG" \
        --max-words "$MAX_WORDS" \
        --skip-existing

    BATCH_EXIT_CODE=$?

    if [ $BATCH_EXIT_CODE -ne 0 ]; then
        echo "❌ Batch $batch failed with exit code $BATCH_EXIT_CODE"
        echo "💡 You can resume by running this script again (it will skip completed batches)"
        exit $BATCH_EXIT_CODE
    fi

    echo ""
    echo "✅ Batch $batch/$BATCHES complete"
    echo ""

    # Small delay between batches to avoid overwhelming the server
    if [ $batch -lt $BATCHES ]; then
        echo "⏸️  Waiting 5 seconds before next batch..."
        sleep 5
        echo ""
    fi
done

# Calculate total time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo "================================================================================"
echo "🎉 ALL BATCHES COMPLETE!"
echo "================================================================================"
echo "Total words processed: $TOTAL_WORDS"
echo "Number of batches: $BATCHES"
echo "Batch size: $BATCH_SIZE words"
echo "Total duration: ${MINUTES}m ${SECONDS}s"
echo "================================================================================"
echo ""
echo "✨ All questions are now cached! Review sessions will be instant."
echo ""
