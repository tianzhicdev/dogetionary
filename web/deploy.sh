#!/bin/bash

# Deploy script for Unforgettable Dictionary Web
set -e

# Check deployment mode
DEPLOY_MODE=${1:-dev}
COMPOSE_FILE="docker-compose.yml"

if [ "$DEPLOY_MODE" = "prod" ]; then
    COMPOSE_FILE="docker-compose.prod.yml"
    echo "🚀 Starting PRODUCTION deployment with SSL..."

    # Check for SSL certificates
    if [ ! -f "nginx/ssl/cloudflare.pem" ] || [ ! -f "nginx/ssl/cloudflare.key" ]; then
        echo "❌ Error: Cloudflare SSL certificates not found!"
        echo "📋 Please place your certificates in nginx/ssl/"
        echo "   - cloudflare.pem (certificate)"
        echo "   - cloudflare.key (private key)"
        exit 1
    fi
else
    echo "🚀 Starting DEVELOPMENT deployment (HTTP only)..."
fi

# Check if we're in the web directory
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "❌ Error: Please run this script from the web directory"
    exit 1
fi

# Copy production environment
echo "📝 Setting up environment..."
if [ -f ".env.production" ]; then
    cp .env.production .env
else
    echo "⚠️  Warning: .env.production not found, using default .env"
fi

# Build and start services
echo "🏗️  Building Docker images..."
docker-compose -f $COMPOSE_FILE build --no-cache

echo "🔄 Stopping existing containers..."
docker-compose -f $COMPOSE_FILE down

echo "🚀 Starting services..."
docker-compose -f $COMPOSE_FILE up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Check if services are running
echo "🔍 Checking service status..."
docker-compose ps

# Test the web service
echo "🧪 Testing web service..."
sleep 5

if [ "$DEPLOY_MODE" = "prod" ]; then
    if curl -f -k https://localhost/ > /dev/null 2>&1; then
        echo "✅ HTTPS service is running successfully!"
        echo "🌐 Your site is available at: https://localhost"
        echo "🌐 Production URL: https://unforgettable-dictionary.com"
    else
        echo "❌ HTTPS service health check failed"
        echo "📋 Showing logs..."
        docker-compose -f $COMPOSE_FILE logs web
        exit 1
    fi
else
    if curl -f http://localhost/ > /dev/null 2>&1; then
        echo "✅ HTTP service is running successfully!"
        echo "🌐 Your site is available at: http://localhost"
        echo "🌐 Production URL: https://unforgettable-dictionary.com"
    else
        echo "❌ HTTP service health check failed"
        echo "📋 Showing logs..."
        docker-compose -f $COMPOSE_FILE logs web
        exit 1
    fi
fi

echo "✅ Deployment completed successfully!"
echo ""
echo "📊 Service Status:"
docker-compose -f $COMPOSE_FILE ps
echo ""
echo "📋 To view logs: docker-compose -f $COMPOSE_FILE logs -f"
echo "🛑 To stop: docker-compose -f $COMPOSE_FILE down"

if [ "$DEPLOY_MODE" = "prod" ]; then
    echo ""
    echo "🔐 SSL Configuration:"
    echo "   - Certificate: nginx/ssl/cloudflare.pem"
    echo "   - Private key: nginx/ssl/cloudflare.key"
    echo "   - HTTPS Port: 443"
fi