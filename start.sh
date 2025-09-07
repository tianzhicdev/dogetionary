#!/bin/bash

echo "Stopping any existing services..."
docker-compose down

echo "Building and starting services..."
docker-compose up --build -d

echo "Dictionary app is now running on http://localhost:5000"
echo "Test with: curl 'http://localhost:5000/word?w=hello'"