#!/bin/bash

# Server startup script for Dogetionary
# Handles both docker-compose and docker compose (plugin version)

set -e

echo "🚀 Starting Dogetionary Server..."

# Function to detect Docker Compose command
get_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo "❌ Docker Compose not found!"
        echo "Please install Docker Compose:"
        echo "  sudo apt update"
        echo "  sudo apt install docker-compose-plugin"
        exit 1
    fi
}

# Get the appropriate compose command
COMPOSE_CMD=$(get_compose_cmd)
echo "📦 Using: $COMPOSE_CMD"

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ docker-compose.yml not found in current directory"
    echo "Please run this script from the project root directory"
    exit 1
fi

# Check Docker access
if ! docker ps &> /dev/null; then
    echo "❌ Cannot access Docker. Please ensure:"
    echo "  1. Docker is running"
    echo "  2. User is in docker group: sudo usermod -aG docker $USER"
    echo "  3. Log out and back in to apply group changes"
    exit 1
fi

# Check SSL certificates for HTTPS
CERT_DIR="/etc/letsencrypt/live/dogetionary.webhop.net"
if [ -f "$CERT_DIR/fullchain.pem" ] && [ -f "$CERT_DIR/privkey.pem" ]; then
    echo "✅ SSL certificates found - HTTPS enabled"
    USE_HTTPS=true
else
    echo "⚠️  SSL certificates not found - HTTP only mode"
    echo "Certificates should be at: $CERT_DIR"
    USE_HTTPS=false
fi

# Stop existing services
echo "🛑 Stopping any existing services..."
$COMPOSE_CMD down || true

# Clean up old containers and images if requested
if [ "$1" = "--clean" ]; then
    echo "🧹 Cleaning up old containers and images..."
    docker system prune -f
    docker volume prune -f
fi

# Build and start services
echo "🏗️  Building and starting services..."
if [ "$USE_HTTPS" = true ]; then
    $COMPOSE_CMD up -d --build
    PROTOCOL="https"
    PORT_INFO="80 (HTTP redirect) and 443 (HTTPS)"
else
    # For HTTP-only mode, expose app directly
    echo "⚠️  Running in HTTP-only mode (no SSL certificates found)"
    $COMPOSE_CMD up -d --build postgres app
    PROTOCOL="http"
    PORT_INFO="5000"
fi

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Health check
echo "🏥 Performing health checks..."

# Check database
DB_STATUS=$($COMPOSE_CMD exec -T postgres pg_isready -U dogeuser -d dogetionary 2>/dev/null || echo "failed")
if [[ $DB_STATUS == *"accepting connections"* ]]; then
    echo "✅ Database: Ready"
else
    echo "❌ Database: Not ready"
fi

# Check application
if [ "$USE_HTTPS" = true ]; then
    # Test through nginx
    APP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://localhost/api/health 2>/dev/null || echo "000")
    if [ "$APP_STATUS" = "200" ]; then
        echo "✅ Application (via HTTPS): Ready"
    else
        echo "❌ Application (via HTTPS): Not ready (Status: $APP_STATUS)"
    fi
else
    # Test app directly
    APP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/health 2>/dev/null || echo "000")
    if [ "$APP_STATUS" = "200" ]; then
        echo "✅ Application: Ready"
    else
        echo "❌ Application: Not ready (Status: $APP_STATUS)"
    fi
fi

# Show running containers
echo ""
echo "📊 Running services:"
$COMPOSE_CMD ps

# Show recent logs
echo ""
echo "📋 Recent logs:"
$COMPOSE_CMD logs --tail=5

echo ""
echo "🎉 Dogetionary server is running!"
echo ""
if [ "$USE_HTTPS" = true ]; then
    echo "🌐 Website: https://dogetionary.webhop.net"
    echo "🔗 API: https://dogetionary.webhop.net/api/"
    echo "🧪 Test API: curl 'https://dogetionary.webhop.net/api/health'"
    echo "📖 Test word: curl 'https://dogetionary.webhop.net/api/word?w=hello'"
else
    echo "🌐 API: http://localhost:$PORT_INFO"
    echo "🧪 Test API: curl 'http://localhost:5000/health'"
    echo "📖 Test word: curl 'http://localhost:5000/word?w=hello'"
fi
echo ""
echo "📚 Useful commands:"
echo "  $COMPOSE_CMD logs -f           # View all logs"
echo "  $COMPOSE_CMD logs -f app       # View app logs only"
echo "  $COMPOSE_CMD restart app       # Restart app"
echo "  $COMPOSE_CMD down              # Stop all services"
echo "  ./server_start.sh --clean      # Clean restart"
echo ""
echo "💡 Logs location: docker containers (use commands above)"
echo "🔄 To restart: ./server_start.sh"