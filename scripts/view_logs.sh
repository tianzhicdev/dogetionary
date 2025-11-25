#!/bin/bash

LOGS_DIR="./logs/app"

case "$1" in
  errors)
    echo "📕 Showing real-time errors..."
    tail -f "$LOGS_DIR/error.log"
    ;;

  errors-recent)
    echo "📕 Last 50 errors:"
    tail -n 50 "$LOGS_DIR/error.log"
    ;;

  errors-today)
    echo "📕 Errors from today:"
    # Handle both macOS and Linux date commands
    date_str=$(date +%Y-%m-%d 2>/dev/null || date -d "today" +%Y-%m-%d)
    grep "$date_str" "$LOGS_DIR/error.log" 2>/dev/null || echo "No errors today! 🎉"
    ;;

  errors-count)
    echo "📊 Error count by date (last 7 days):"
    for i in {0..6}; do
      # Handle both macOS and Linux date commands
      if date -v-${i}d +%Y-%m-%d 2>/dev/null >/dev/null; then
        # macOS
        date_str=$(date -v-${i}d +%Y-%m-%d)
      else
        # Linux
        date_str=$(date -d "${i} days ago" +%Y-%m-%d)
      fi
      count=$(grep "$date_str" "$LOGS_DIR/error.log" 2>/dev/null | wc -l | tr -d ' ')
      echo "  $date_str: $count errors"
    done
    ;;

  errors-search)
    if [ -z "$2" ]; then
      echo "Usage: ./scripts/view_logs.sh errors-search <pattern>"
      exit 1
    fi
    echo "🔍 Searching for: $2"
    grep -i "$2" "$LOGS_DIR/error.log"
    ;;

  app)
    echo "📗 Showing real-time app logs..."
    tail -f "$LOGS_DIR/app.log"
    ;;

  app-recent)
    echo "📗 Last 100 app logs:"
    tail -n 100 "$LOGS_DIR/app.log"
    ;;

  clear-old)
    echo "🗑️  Clearing logs older than 30 days..."
    find "$LOGS_DIR" -name "*.log.*" -mtime +30 -delete
    echo "Done!"
    ;;

  *)
    echo "Usage: ./scripts/view_logs.sh {command}"
    echo ""
    echo "Commands:"
    echo "  errors           - Real-time error logs"
    echo "  errors-recent    - Last 50 errors"
    echo "  errors-today     - Errors from today"
    echo "  errors-count     - Error count by date (last 7 days)"
    echo "  errors-search    - Search errors (e.g., errors-search ValueError)"
    echo "  app              - Real-time all logs"
    echo "  app-recent       - Last 100 app logs"
    echo "  clear-old        - Delete logs older than 30 days"
    exit 1
    ;;
esac
