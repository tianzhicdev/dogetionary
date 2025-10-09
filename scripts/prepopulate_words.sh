#!/bin/bash
# Prepopulate words script wrapper for Dogetionary
# This script wraps the Python implementation with argument validation

set -e

# Default values
DOMAIN="https://dogetionary.webhop.net/api"
WORDS=10
LEARNING_LANGUAGE=""
NATIVE_LANGUAGE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain=*)
            DOMAIN="${1#*=}"
            shift
            ;;
        --words=*)
            WORDS="${1#*=}"
            shift
            ;;
        --learning_language=*)
            LEARNING_LANGUAGE="${1#*=}"
            shift
            ;;
        --native_language=*)
            NATIVE_LANGUAGE="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--domain=URL] [--words=N] --learning_language=LANG --native_language=LANG"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$LEARNING_LANGUAGE" ] || [ -z "$NATIVE_LANGUAGE" ]; then
    echo "Error: --learning_language and --native_language are required"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --domain=URL              API domain (default: https://dogetionary.webhop.net/api)"
    echo "                            Examples: localhost:5000, https://dogetionary.webhop.net/api"
    echo "  --words=N                 Number of words to generate (default: 10)"
    echo "  --learning_language=LANG  Learning language code (required, e.g., en, de, zh)"
    echo "  --native_language=LANG    Native language code (required, e.g., zh, en)"
    echo ""
    echo "Example:"
    echo "  $0 --domain=localhost:5000 --words=50 --learning_language=en --native_language=zh"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run Python script
python3 "$SCRIPT_DIR/prepopulate_words.py" \
    --domain="$DOMAIN" \
    --words="$WORDS" \
    --learning_language="$LEARNING_LANGUAGE" \
    --native_language="$NATIVE_LANGUAGE"
