#!/bin/bash
#
# verify_questions.sh - Verify AI-generated review questions
#
# This script:
# 1. Creates/activates a Python virtual environment
# 2. Installs required dependencies
# 3. Runs the question verification script
# 4. Generates a CSV report of verification events
#
# Usage:
#   ./verify_questions.sh [--limit N] [--dry-run]
#
# Environment variables:
#   OPENAI_API_KEY - Required for LLM verification
#   DATABASE_URL   - Optional, defaults to local postgres
#
# Examples:
#   ./verify_questions.sh --limit 10          # Verify 10 questions
#   ./verify_questions.sh --dry-run           # Test without updating DB
#   ./verify_questions.sh                     # Verify all unverified

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$SCRIPT_DIR/.venv"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$SCRIPT_DIR/questions_verification_report_${TIMESTAMP}.csv"

echo "=============================================="
echo "  Question Verification Script"
echo "=============================================="
echo ""

# Source environment variables if available
ENV_FILE="$PROJECT_DIR/src/.env.secrets"
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment from: $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
fi

# Check for OPENAI_API_KEY
if [ -z "$OPENAI_API_KEY" ]; then
    echo "ERROR: OPENAI_API_KEY environment variable is required"
    echo ""
    echo "Set it with:"
    echo "  export OPENAI_API_KEY='your-api-key'"
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
    echo "Virtual environment created at: $VENV_DIR"
fi

# Activate virtual environment
echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

# Install/upgrade dependencies
echo "Installing dependencies..."
pip install --quiet --upgrade pip
pip install --quiet psycopg2-binary openai

echo ""
echo "Running verification..."
echo ""

# Run the Python verification script with all passed arguments
python "$SCRIPT_DIR/verify_questions.py" --output "$OUTPUT_FILE" "$@"

# Check if report was generated
if [ -f "$OUTPUT_FILE" ]; then
    echo ""
    echo "Report saved to: $OUTPUT_FILE"

    # Show preview of events
    EVENT_COUNT=$(wc -l < "$OUTPUT_FILE")
    EVENT_COUNT=$((EVENT_COUNT - 1))  # Subtract header row

    if [ $EVENT_COUNT -gt 0 ]; then
        echo ""
        echo "Preview of verification events (first 5):"
        echo "----------------------------------------"
        head -6 "$OUTPUT_FILE" | tail -5
    fi
fi

echo ""
echo "Done!"
