#!/bin/bash

echo "Stopping all services..."
docker-compose down

echo "Removing Python cache files..."
find src -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find src -name "*.pyc" -delete

echo "Rebuilding all containers (this may take a few minutes)..."
docker-compose build --no-cache

echo "Starting all services..."
docker-compose up -d

echo ""
echo "✅ All services rebuilt and restarted successfully!"
echo ""
echo "Services running:"
echo "  - Backend API: http://localhost:5001"
echo "  - Nginx: http://localhost:80"
echo "  - Grafana: http://localhost:3000"
echo "  - Prometheus: http://localhost:9090"
echo "  - Loki: http://localhost:3100"
echo ""
echo "Test backend: curl http://localhost:5001/health"