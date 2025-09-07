#!/bin/bash

# Clean restart script - removes all data and starts fresh
set -e

echo "🧹 Clean restart - this will DELETE ALL DATA"
read -p "Are you sure? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

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

echo "🛑 Stopping all services..."
$COMPOSE_CMD down

echo "🗑️ Removing volumes (deleting all data)..."
$COMPOSE_CMD down -v

echo "🏗️ Building fresh containers..."
$COMPOSE_CMD build

echo "🚀 Starting services with clean database..."
$COMPOSE_CMD up -d

echo "⏳ Waiting for services to start..."
sleep 10

echo "🏥 Testing services..."
echo "Database status:"
$COMPOSE_CMD exec postgres pg_isready -U dogeuser -d dogetionary

echo ""
echo "API status:"
curl -s 'https://dogetionary.webhop.net/api/health' || echo "API not ready yet"

echo ""
echo "🎉 Clean restart complete!"
echo "📊 Running containers:"
$COMPOSE_CMD ps