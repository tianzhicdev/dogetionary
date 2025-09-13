#!/bin/bash

echo "Stopping app and nginx services (keeping database running)..."
docker-compose stop app nginx
docker-compose rm -f app nginx

echo "Building and starting app and nginx services..."
docker-compose up --build -d app nginx

echo "Dictionary app is now running on http://localhost:5000"
echo "Test with: curl 'http://localhost:5000/word?w=hello'"