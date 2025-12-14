#!/bin/bash

# Debug script for postgres connection issues on production

echo "=== Postgres Connection Debug ==="
echo ""

echo "1. Checking container status..."
docker ps --filter "name=dogetionary" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""

echo "2. Checking Docker network..."
docker network inspect dogetionary_dogetionary-network --format '{{range .Containers}}{{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}'
echo ""

echo "3. Checking app container environment variables..."
docker exec dogetionary_app_1 env | grep -E "POSTGRES|DATABASE" | sort
echo ""

echo "4. Testing network connectivity from app to postgres..."
docker exec dogetionary_app_1 nc -zv postgres 5432 2>&1
echo ""

echo "5. Testing postgres is accepting connections..."
docker exec dogetionary_postgres_1 pg_isready -U dogetionary
echo ""

echo "6. Checking if app can resolve 'postgres' hostname..."
docker exec dogetionary_app_1 getent hosts postgres
echo ""

echo "7. Recent app logs (errors only)..."
docker logs dogetionary_app_1 2>&1 | grep -i "error\|traceback" | tail -20
echo ""

echo "=== Diagnosis Complete ==="
echo ""
echo "Common fixes:"
echo "1. Restart both services: docker-compose restart postgres app"
echo "2. Full restart: docker-compose down && docker-compose up -d"
echo "3. Check env vars match docker-compose.yml database settings"
