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
#     [--api-base https://kwafy.com]
#

set -e

# Default values
API_BASE="http://localhost:5001"
INCLUDE_QUESTIONS="false"
BATCH_SIZE=50

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
        --api-base)
            API_BASE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --csv FILE --learning_lang LANG --native_lang LANG [--include-questions] [--api-base URL]"
            exit 1
            ;;
    esac
done

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
echo "Batch Pre-population Configuration"
echo "========================================="
echo "CSV File:         $CSV_FILE"
echo "Learning Lang:    $LEARNING_LANG"
echo "Native Lang:      $NATIVE_LANG"
echo "Include Questions: $INCLUDE_QUESTIONS"
echo "API Base:         $API_BASE"
echo "Batch Size:       $BATCH_SIZE words"
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

# Calculate number of batches
NUM_BATCHES=$(( (TOTAL_WORDS + BATCH_SIZE - 1) / BATCH_SIZE ))

echo "🚀 Starting batch processing ($NUM_BATCHES batches)..."
echo ""

# Track overall statistics
TOTAL_DEFS_GENERATED=0
TOTAL_DEFS_CACHED=0
TOTAL_QUESTIONS_GENERATED=0
TOTAL_QUESTIONS_CACHED=0
TOTAL_ERRORS=0

# Process in batches
for ((batch_num=0; batch_num<NUM_BATCHES; batch_num++)); do
    START_IDX=$((batch_num * BATCH_SIZE))
    END_IDX=$((START_IDX + BATCH_SIZE))

    if [[ $END_IDX -gt $TOTAL_WORDS ]]; then
        END_IDX=$TOTAL_WORDS
    fi

    # Extract batch of words
    BATCH_WORDS=("${ALL_WORDS[@]:$START_IDX:$((END_IDX - START_IDX))}")

    # Convert to JSON array
    WORDS_JSON=$(printf '%s\n' "${BATCH_WORDS[@]}" | jq -R . | jq -s .)

    # Build request payload
    REQUEST_JSON=$(jq -n \
        --argjson words "$WORDS_JSON" \
        --arg learning_lang "$LEARNING_LANG" \
        --arg native_lang "$NATIVE_LANG" \
        --argjson gen_questions "$INCLUDE_QUESTIONS" \
        '{
            words: $words,
            learning_language: $learning_lang,
            native_language: $native_lang,
            generate_definitions: true,
            generate_questions: $gen_questions
        }')

    echo "📦 Batch $((batch_num + 1))/$NUM_BATCHES (words $((START_IDX + 1))-$END_IDX)..."

    # Make API request
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$REQUEST_JSON" \
        "$API_BASE/api/test-prep/batch-populate")

    # Parse response
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success // false')

    if [[ "$SUCCESS" == "true" ]]; then
        # Extract statistics
        DEFS_GEN=$(echo "$RESPONSE" | jq -r '.summary.definitions_generated // 0')
        DEFS_CACHED=$(echo "$RESPONSE" | jq -r '.summary.definitions_cached // 0')
        QUESTIONS_GEN=$(echo "$RESPONSE" | jq -r '.summary.questions_generated // 0')
        QUESTIONS_CACHED=$(echo "$RESPONSE" | jq -r '.summary.questions_cached // 0')
        ERRORS=$(echo "$RESPONSE" | jq -r '.summary.errors | length // 0')
        TIME=$(echo "$RESPONSE" | jq -r '.processing_time_seconds // 0')

        # Update totals
        TOTAL_DEFS_GENERATED=$((TOTAL_DEFS_GENERATED + DEFS_GEN))
        TOTAL_DEFS_CACHED=$((TOTAL_DEFS_CACHED + DEFS_CACHED))
        TOTAL_QUESTIONS_GENERATED=$((TOTAL_QUESTIONS_GENERATED + QUESTIONS_GEN))
        TOTAL_QUESTIONS_CACHED=$((TOTAL_QUESTIONS_CACHED + QUESTIONS_CACHED))
        TOTAL_ERRORS=$((TOTAL_ERRORS + ERRORS))

        echo "   ✓ Completed in ${TIME}s"
        echo "   Definitions: $DEFS_GEN generated, $DEFS_CACHED cached"

        if [[ "$INCLUDE_QUESTIONS" == "true" ]]; then
            echo "   Questions: $QUESTIONS_GEN generated, $QUESTIONS_CACHED cached"
        fi

        if [[ $ERRORS -gt 0 ]]; then
            echo "   ⚠️  $ERRORS errors encountered"
        fi
    else
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // "Unknown error"')
        echo "   ❌ Batch failed: $ERROR_MSG"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    fi

    echo ""
done

# Print final summary
echo "========================================="
echo "✅ Batch Pre-population Complete"
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
