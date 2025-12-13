#!/bin/bash
# Helper script to run SQL against Docker Postgres

# Get the container name
CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | head -1)

if [ -z "$CONTAINER" ]; then
    echo "❌ Postgres container not found"
    exit 1
fi

# Run SQL file
SQL_FILE="${1:-check_tianz_completeness.sql}"

if [ ! -f "$SQL_FILE" ]; then
    echo "❌ SQL file not found: $SQL_FILE"
    exit 1
fi

echo "📊 Running SQL: $SQL_FILE"
echo "🐳 Container: $CONTAINER"
echo ""

docker exec -i "$CONTAINER" psql -U dogeuser -d dogetionary < "$SQL_FILE"
