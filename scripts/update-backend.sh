#!/bin/bash

# Script to update backend with latest changes
set -e

echo "🔄 Updating backend with latest changes..."

# Function to detect Docker Compose command
get_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo "❌ Docker Compose not found!"
        exit 1
    fi
}

COMPOSE_CMD=$(get_compose_cmd)

# Rebuild and restart the app container
echo "🏗️  Rebuilding app container..."
$COMPOSE_CMD build app

echo "🔄 Restarting app container..."
$COMPOSE_CMD up -d app

echo "🗃️ Database will be initialized from init.sql on restart"

echo "⏳ Waiting for app to start..."
sleep 5

# Test the fix
echo "🧪 Testing cached word retrieval..."
TEST_RESULT=$(curl -s 'https://dogetionary.webhop.net/api/word?w=beauty' | head -1)

if [[ $TEST_RESULT == *"error"* ]]; then
    echo "❌ Test failed - API still returning errors"
    echo "Response: $TEST_RESULT"
    exit 1
else
    echo "✅ Test passed - API responding properly"
fi

echo ""
echo "🎉 Backend update complete!"
echo "📊 Container status:"
$COMPOSE_CMD ps app

echo ""
echo "📋 Recent logs:"
$COMPOSE_CMD logs app --tail=5