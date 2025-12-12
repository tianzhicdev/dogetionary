#!/bin/bash
# upload_videos.sh - Upload videos from directory to backend
#
# Usage:
#   ./upload_videos.sh --dir <directory> --backend-url <url>

set -e  # Exit on error

# Default values
INPUT_DIR=""
BACKEND_URL="http://localhost:5001"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dir)
      INPUT_DIR="$2"
      shift 2
      ;;
    --backend-url)
      BACKEND_URL="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 --dir <directory> [OPTIONS]"
      echo ""
      echo "Uploads videos from directory structure to backend server."
      echo "Each subdirectory should contain <name>.mp3 and metadata.json"
      echo ""
      echo "Options:"
      echo "  --dir <directory>      Input directory containing video subdirectories (required)"
      echo "  --backend-url <url>    Backend API URL (default: http://localhost:5001)"
      echo ""
      echo "Examples:"
      echo "  $0 --dir /tmp/videos-output"
      echo "  $0 --dir /tmp/videos-output --backend-url https://kwafy.com/api"
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
if [ -z "$INPUT_DIR" ]; then
  echo "Error: --dir argument required"
  echo "Use --help for usage information"
  exit 1
fi

# Check if directory exists
if [ ! -d "$INPUT_DIR" ]; then
  echo "Error: Directory not found: $INPUT_DIR"
  exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if Python script exists
PYTHON_SCRIPT="$SCRIPT_DIR/upload_videos.py"
if [ ! -f "$PYTHON_SCRIPT" ]; then
  echo "Error: Python script not found: $PYTHON_SCRIPT"
  exit 1
fi

# Run Python script
echo "Starting video upload..."
echo "  Input Dir: $INPUT_DIR"
echo "  Backend URL: $BACKEND_URL"
echo ""

python3 "$PYTHON_SCRIPT" \
  --dir "$INPUT_DIR" \
  --backend-url "$BACKEND_URL"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo ""
  echo "Upload completed successfully!"
else
  echo ""
  echo "Upload failed with exit code $EXIT_CODE"
  exit $EXIT_CODE
fi
