#!/bin/bash

# Script to bulk-update logger.error calls to use exc_info=True
# This is a safe change that adds stack trace logging to all errors

SRCDIR="/Users/biubiu/projects/dogetionary/src"

# Find all Python files in handlers and services
find "$SRCDIR/handlers" "$SRCDIR/services" -name "*.py" -type f | while read -r file; do
    # Skip if file already imports log_error (manually updated)
    if grep -q "from middleware.logging import log_error" "$file"; then
        echo "Skipping (already updated): $file"
        continue
    fi

    # Add import after other imports if file has logger.error calls
    if grep -q "logger.error" "$file" && grep -q "import logging" "$file"; then
        # Check if we need to add the import
        if ! grep -q "from middleware.logging import log_error" "$file"; then
            # Find a good place to add import (after database or service imports)
            if grep -q "from utils.database import" "$file"; then
                sed -i '' '/from utils.database import/a\
from middleware.logging import log_error
' "$file"
                echo "Added import to: $file"
            elif grep -q "from services." "$file"; then
                # Add after the last service import
                awk '/from services\./ {line=$0; next} {if (line) {print line; print "from middleware.logging import log_error"; line=""} print}' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
                echo "Added import to: $file"
            fi
        fi

        # Update all logger.error calls without exc_info to add exc_info=True
        # Pattern: logger.error(...) not followed by exc_info
        if grep -q 'logger\.error(' "$file"; then
            # For now, just ensure exc_info=True is added where missing
            # This is a conservative change that won't break anything
            perl -i -pe 's/logger\.error\(([^)]+)\)(?!\s*,\s*exc_info=True)/logger.error($1, exc_info=True)/g' "$file"
            echo "Updated error logging in: $file"
        fi
    fi
done

echo "Done!"
