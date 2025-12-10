#!/bin/bash

#
# Pre-populate test vocabulary definitions and questions
#
# Usage:
#   ./scripts/pre_populate_test.sh \
#     --csv /path/to/words.csv \
#     --learning_lang en \
#     --native_lang zh \
#     [--include-questions] \
#     [--env production|development]
#
# Environment:
#   - development|dev: http://localhost:5001 (direct to Flask, no nginx)
#   - production|prod: https://kwafy.com/api (through nginx, strips /api prefix)
#

set -e

# Default values
ENVIRONMENT="development"
INCLUDE_QUESTIONS="false"

# Environment-based API configuration (like iOS Configuration.swift)
function get_api_base() {
    case "$1" in
        production|prod)
            echo "https://kwafy.com/api"
            ;;
        development|dev)
            echo "http://localhost:5001"
            ;;
        *)
            echo "http://localhost:5001"
            ;;
    esac
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --csv)
            CSV_FILE="$2"
            shift 2
            ;;
        --learning_lang)
            LEARNING_LANG="$2"
            shift 2
            ;;
        --native_lang)
            NATIVE_LANG="$2"
            shift 2
            ;;
        --include-questions)
            INCLUDE_QUESTIONS="true"
            shift
            ;;
        --env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --csv FILE --learning_lang LANG --native_lang LANG [--include-questions] [--env prod|dev]"
            exit 1
            ;;
    esac
done

# Set API_BASE from environment
API_BASE=$(get_api_base "$ENVIRONMENT")

# Validate required arguments
if [[ -z "$CSV_FILE" ]]; then
    echo "Error: --csv is required"
    exit 1
fi

if [[ ! -f "$CSV_FILE" ]]; then
    echo "Error: CSV file not found: $CSV_FILE"
    exit 1
fi

if [[ -z "$LEARNING_LANG" ]]; then
    echo "Error: --learning_lang is required"
    exit 1
fi

if [[ -z "$NATIVE_LANG" ]]; then
    echo "Error: --native_lang is required"
    exit 1
fi

# Print configuration
echo "========================================="
echo "Pre-population Configuration"
echo "========================================="
echo "CSV File:          $CSV_FILE"
echo "Learning Lang:     $LEARNING_LANG"
echo "Native Lang:       $NATIVE_LANG"
echo "Include Questions: $INCLUDE_QUESTIONS"
echo "Environment:       $ENVIRONMENT"
echo "API Base:          $API_BASE"
echo "Mode:              Word-by-word (1 word per request)"
echo "========================================="
echo ""

# Read all words from CSV (skip empty lines) - compatible with bash 3.2+
ALL_WORDS=()
while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines
    if [[ -n "${line// /}" ]]; then
        # Remove carriage returns and add to array
        ALL_WORDS+=("${line//$'\r'/}")
    fi
done < "$CSV_FILE"
TOTAL_WORDS=${#ALL_WORDS[@]}

echo "📚 Loaded $TOTAL_WORDS words from CSV"
echo ""

# Validate endpoint exists before processing
echo "🔍 Validating endpoint: $API_BASE/v3/test-prep/batch-populate"
TEST_PAYLOAD='{"words":["test"],"learning_language":"en","native_language":"zh","generate_definitions":true,"generate_questions":false}'
TEST_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$TEST_PAYLOAD" \
    "$API_BASE/v3/test-prep/batch-populate")

# Extract HTTP status code (last line)
HTTP_CODE=$(echo "$TEST_RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$TEST_RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
    echo ""
    echo "❌ ERROR: Endpoint validation failed!"
    echo "   URL: $API_BASE/v3/test-prep/batch-populate"
    echo "   HTTP Status: $HTTP_CODE"
    echo "   Response: $RESPONSE_BODY"
    echo ""
    echo "This usually means:"
    echo "  - The endpoint doesn't exist on this server yet"
    echo "  - The server is using a different URL path"
    echo "  - The server requires authentication"
    echo ""
    echo "If using production (--env prod), make sure"
    echo "the latest code with v3 batch-populate endpoint has been deployed."
    echo ""
    exit 1
fi

echo "   ✓ Endpoint is available"
echo ""

echo "🚀 Starting parallel processing ($TOTAL_WORDS words, 10 concurrent requests)..."
echo ""

# Create temp directory for statistics tracking (file-based for parallel safety)
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Initialize statistics files
echo "0" > "$TEMP_DIR/defs_generated"
echo "0" > "$TEMP_DIR/defs_cached"
echo "0" > "$TEMP_DIR/questions_generated"
echo "0" > "$TEMP_DIR/questions_cached"
echo "0" > "$TEMP_DIR/errors"
echo "0" > "$TEMP_DIR/processed"

# Simple file-based locking function (bash 3.2 compatible)
lock_and_increment() {
    local file="$1"
    local amount="$2"
    local lockfile="$TEMP_DIR/.lock"

    # Simple spin lock
    while ! mkdir "$lockfile" 2>/dev/null; do
        sleep 0.01
    done

    # Critical section
    local current=$(cat "$file")
    echo $((current + amount)) > "$file"

    # Release lock
    rmdir "$lockfile"
}

# Function to process a single word (runs in background)
process_word() {
    local WORD="$1"
    local WORD_NUM="$2"
    local TOTAL="$3"

    # Build request payload for single word
    REQUEST_JSON=$(jq -n \
        --arg word "$WORD" \
        --arg learning_lang "$LEARNING_LANG" \
        --arg native_lang "$NATIVE_LANG" \
        --argjson gen_questions "$INCLUDE_QUESTIONS" \
        '{
            words: [$word],
            learning_language: $learning_lang,
            native_language: $native_lang,
            generate_definitions: true,
            generate_questions: $gen_questions
        }')

    # Make API request
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$REQUEST_JSON" \
        "$API_BASE/v3/test-prep/batch-populate" \
        --max-time 120)

    # Parse response
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false' 2>/dev/null)

    if [[ "$SUCCESS" == "true" ]]; then
        # Extract statistics
        DEFS_GEN=$(echo "$RESPONSE" | jq -r '.summary.definitions_generated // 0')
        DEFS_CACHED=$(echo "$RESPONSE" | jq -r '.summary.definitions_cached // 0')
        QUESTIONS_GEN=$(echo "$RESPONSE" | jq -r '.summary.questions_generated // 0')
        QUESTIONS_CACHED=$(echo "$RESPONSE" | jq -r '.summary.questions_cached // 0')
        TIME=$(echo "$RESPONSE" | jq -r '.processing_time_seconds // 0')

        # Atomic increment using simple lock
        lock_and_increment "$TEMP_DIR/defs_generated" "$DEFS_GEN"
        lock_and_increment "$TEMP_DIR/defs_cached" "$DEFS_CACHED"
        lock_and_increment "$TEMP_DIR/questions_generated" "$QUESTIONS_GEN"
        lock_and_increment "$TEMP_DIR/questions_cached" "$QUESTIONS_CACHED"
        lock_and_increment "$TEMP_DIR/processed" "1"

        # Status indicator
        if [[ $DEFS_GEN -gt 0 ]]; then
            STATUS="✨ generated"
        else
            STATUS="✓ cached"
        fi

        printf "[%d/%d] %-20s %s (%.2fs)\n" "$WORD_NUM" "$TOTAL" "$WORD" "$STATUS" "$TIME"
    else
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // "Unknown error"' 2>/dev/null)
        if [[ -z "$ERROR_MSG" || "$ERROR_MSG" == "null" ]]; then
            ERROR_MSG="Request failed"
        fi

        # Atomic increment error counter
        lock_and_increment "$TEMP_DIR/errors" "1"
        lock_and_increment "$TEMP_DIR/processed" "1"

        # Log full error for first failure only
        if [[ ! -f "$TEMP_DIR/first_error.log" ]]; then
            echo "   → First error details: $RESPONSE" >> "$TEMP_DIR/first_error.log"
        fi

        printf "[%d/%d] %-20s ❌ %s\n" "$WORD_NUM" "$TOTAL" "$WORD" "$ERROR_MSG"
    fi
}

# Export function and variables for subshells
export -f process_word lock_and_increment
export API_BASE LEARNING_LANG NATIVE_LANG INCLUDE_QUESTIONS TEMP_DIR

# Process words in parallel (10 at a time) - bash 3.2 compatible
MAX_PARALLEL=10

# Process in batches
for ((i=0; i<TOTAL_WORDS; i+=MAX_PARALLEL)); do
    # Launch batch of jobs
    for ((j=0; j<MAX_PARALLEL && i+j<TOTAL_WORDS; j++)); do
        WORD="${ALL_WORDS[$i+$j]}"
        WORD_NUM=$((i + j + 1))
        process_word "$WORD" "$WORD_NUM" "$TOTAL_WORDS" &
    done

    # Wait for entire batch to complete
    wait

    # Show progress
    PROCESSED=$(cat "$TEMP_DIR/processed")
    echo ""
    echo "Progress: $PROCESSED / $TOTAL_WORDS words completed"
    echo ""
done

# Show first error if any occurred
if [[ -f "$TEMP_DIR/first_error.log" ]]; then
    echo ""
    echo "First error details:"
    cat "$TEMP_DIR/first_error.log"
fi

# Read final statistics from files
TOTAL_DEFS_GENERATED=$(cat "$TEMP_DIR/defs_generated")
TOTAL_DEFS_CACHED=$(cat "$TEMP_DIR/defs_cached")
TOTAL_QUESTIONS_GENERATED=$(cat "$TEMP_DIR/questions_generated")
TOTAL_QUESTIONS_CACHED=$(cat "$TEMP_DIR/questions_cached")
TOTAL_ERRORS=$(cat "$TEMP_DIR/errors")

echo ""

# Print final summary
echo "========================================="
echo "✅ Pre-population Complete"
echo "========================================="
echo "Total Words:               $TOTAL_WORDS"
echo ""
echo "Definitions:"
echo "  - Generated:             $TOTAL_DEFS_GENERATED"
echo "  - Cached:                $TOTAL_DEFS_CACHED"
echo ""

if [[ "$INCLUDE_QUESTIONS" == "true" ]]; then
    echo "Questions:"
    echo "  - Generated:             $TOTAL_QUESTIONS_GENERATED"
    echo "  - Cached:                $TOTAL_QUESTIONS_CACHED"
    echo ""
fi

echo "Errors:                    $TOTAL_ERRORS"
echo "========================================="
