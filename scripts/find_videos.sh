#!/bin/bash
# find_videos.sh - Download and process videos (download-only mode)
#
# Usage:
#   ./find_videos.sh --csv words.csv --output-dir /path/to/output [options]

set -e  # Exit on error

# Default values
STORAGE_DIR="/Volumes/databank/dogetionary-pipeline"
OUTPUT_DIR=""
CSV_FILE=""
MAX_VIDEOS=100
MIN_SCORE=0.7

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --csv)
      CSV_FILE="$2"
      shift 2
      ;;
    --storage-dir)
      STORAGE_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --max-videos)
      MAX_VIDEOS="$2"
      shift 2
      ;;
    --min-score)
      MIN_SCORE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 --csv <word_list.csv> --output-dir <output_dir> [OPTIONS]"
      echo ""
      echo "Downloads and processes videos without uploading to server."
      echo "Saves MP3 audio and metadata.json to output directory."
      echo ""
      echo "Options:"
      echo "  --csv <file>           Path to CSV file with word list (required)"
      echo "  --output-dir <dir>     Output directory for videos (required)"
      echo "  --storage-dir <dir>    Base directory for caching (default: /Volumes/databank/dogetionary-pipeline)"
      echo "  --max-videos <n>       Max videos per word (default: 100)"
      echo "  --min-score <float>    Min relevance score (default: 0.7)"
      echo ""
      echo "Examples:"
      echo "  $0 --csv test_words.csv --output-dir /tmp/videos-output"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [ -z "$CSV_FILE" ]; then
  echo "Error: --csv argument required"
  echo "Use --help for usage information"
  exit 1
fi

if [ -z "$OUTPUT_DIR" ]; then
  echo "Error: --output-dir argument required"
  echo "Use --help for usage information"
  exit 1
fi

# Check if CSV file exists
if [ ! -f "$CSV_FILE" ]; then
  echo "Error: CSV file not found: $CSV_FILE"
  exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if Python script exists
PYTHON_SCRIPT="$SCRIPT_DIR/find_videos.py"
if [ ! -f "$PYTHON_SCRIPT" ]; then
  echo "Error: Python script not found: $PYTHON_SCRIPT"
  exit 1
fi

# Check if .env.secrets exists
SECRETS_FILE="$SCRIPT_DIR/../src/.env.secrets"
if [ ! -f "$SECRETS_FILE" ]; then
  echo "Warning: Secrets file not found: $SECRETS_FILE"
  echo "Make sure API keys are set in environment or .env.secrets"
fi

# Run Python script in download-only mode
echo "Starting video discovery pipeline (DOWNLOAD-ONLY MODE)..."
echo "  CSV File: $CSV_FILE"
echo "  Storage Dir: $STORAGE_DIR"
echo "  Output Dir: $OUTPUT_DIR"
echo "  Max Videos: $MAX_VIDEOS"
echo "  Min Score: $MIN_SCORE"
echo ""

python3 "$PYTHON_SCRIPT" \
  --csv "$CSV_FILE" \
  --storage-dir "$STORAGE_DIR" \
  --output-dir "$OUTPUT_DIR" \
  --max-videos "$MAX_VIDEOS" \
  --min-score "$MIN_SCORE" \
  --download-only

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo ""
  echo "Pipeline completed successfully!"
  echo "Videos saved to: $OUTPUT_DIR"
else
  echo ""
  echo "Pipeline failed with exit code $EXIT_CODE"
  exit $EXIT_CODE
fi
