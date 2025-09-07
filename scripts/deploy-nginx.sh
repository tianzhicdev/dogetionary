#!/bin/bash

# Script to deploy Nginx with HTTPS for Dogetionary
set -e

echo "🚀 Deploying Dogetionary with Nginx HTTPS..."

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "⚠️  Don't run this script as root. Run as regular user with docker access."
    exit 1
fi

# Check if certificates exist
CERT_DIR="/etc/letsencrypt/live/dogetionary.webhop.net"
if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
    echo "❌ SSL certificates not found at $CERT_DIR"
    echo "Please ensure Let's Encrypt certificates are properly installed"
    exit 1
fi

# Check certificate permissions
if ! sudo test -r "$CERT_DIR/fullchain.pem" || ! sudo test -r "$CERT_DIR/privkey.pem"; then
    echo "❌ Cannot read SSL certificates. Checking permissions..."
    sudo ls -la "$CERT_DIR/"
    exit 1
fi

echo "✅ SSL certificates found and readable"

# Stop existing containers
echo "🛑 Stopping existing containers..."
docker-compose down || true

# Build and start services
echo "🏗️  Building and starting services..."
docker-compose up -d --build

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Test HTTP redirect
echo "🧪 Testing HTTP redirect..."
HTTP_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://dogetionary.webhop.net/health || echo "000")
if [ "$HTTP_RESPONSE" = "301" ]; then
    echo "✅ HTTP redirect working"
else
    echo "⚠️  HTTP redirect status: $HTTP_RESPONSE"
fi

# Test HTTPS
echo "🧪 Testing HTTPS..."
HTTPS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" https://dogetionary.webhop.net/health || echo "000")
if [ "$HTTPS_RESPONSE" = "200" ]; then
    echo "✅ HTTPS working"
else
    echo "❌ HTTPS not working. Status: $HTTPS_RESPONSE"
fi

# Test API
echo "🧪 Testing API..."
API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" https://dogetionary.webhop.net/api/health || echo "000")
if [ "$API_RESPONSE" = "200" ]; then
    echo "✅ API working"
else
    echo "❌ API not working. Status: $API_RESPONSE"
fi

# Show running containers
echo ""
echo "📊 Running containers:"
docker-compose ps

# Show logs for debugging
echo ""
echo "📋 Recent nginx logs:"
docker-compose logs nginx --tail=10

echo ""
echo "🎉 Deployment complete!"
echo "🌐 Website: https://dogetionary.webhop.net"
echo "🔗 API: https://dogetionary.webhop.net/api/"
echo ""
echo "📚 Useful commands:"
echo "  docker-compose logs -f nginx    # View nginx logs"
echo "  docker-compose logs -f app      # View app logs"
echo "  docker-compose restart nginx   # Restart nginx"
echo "  docker-compose down             # Stop all services"