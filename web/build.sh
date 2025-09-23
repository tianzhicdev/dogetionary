#!/bin/bash

# Unforgettable Dictionary - Build Script
set -e

echo "🚀 Building Unforgettable Dictionary Static Site..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BUILD_DIR="./dist"
BACKUP_DIR="./backup"
LOG_FILE="./build.log"

# Functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

error() {
    echo -e "${RED}❌ ERROR: $1${NC}" | tee -a $LOG_FILE
    exit 1
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a $LOG_FILE
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a $LOG_FILE
}

# Parse command line arguments
COMMAND=${1:-"build"}
ENVIRONMENT=${2:-"development"}

case $COMMAND in
    "build")
        log "Starting build process for environment: $ENVIRONMENT"

        # Check if .env file exists
        if [ ! -f .env ]; then
            if [ -f .env.example ]; then
                warning ".env file not found. Copying from .env.example"
                cp .env.example .env
                warning "Please edit .env file with your configuration"
            else
                error ".env file not found and no .env.example available"
            fi
        fi

        # Backup existing build if it exists
        if [ -d "$BUILD_DIR" ]; then
            warning "Backing up existing build..."
            rm -rf $BACKUP_DIR
            mv $BUILD_DIR $BACKUP_DIR
        fi

        # Build with Docker
        log "Building static site generator..."
        docker-compose build generator || error "Docker build failed"

        # Generate the site
        log "Generating static site..."
        docker-compose run --rm generator || error "Site generation failed"

        # Check if build was successful
        if [ ! -d "$BUILD_DIR" ] || [ ! -f "$BUILD_DIR/index.html" ]; then
            error "Build failed - no output generated"
        fi

        # Count generated files
        WORD_COUNT=$(find $BUILD_DIR/words -name "*.html" | wc -l)
        LETTER_COUNT=$(find $BUILD_DIR/letters -name "*.html" | wc -l)
        TOTAL_PAGES=$(find $BUILD_DIR -name "*.html" | wc -l)

        success "Build completed successfully!"
        log "Generated: $WORD_COUNT word pages, $LETTER_COUNT letter pages, $TOTAL_PAGES total pages"
        ;;

    "serve")
        log "Starting local server..."

        if [ ! -d "$BUILD_DIR" ]; then
            error "No build found. Run './build.sh build' first"
        fi

        # Start local server
        PORT=${3:-8000}
        log "Serving site on http://localhost:$PORT"
        cd $BUILD_DIR && python3 -m http.server $PORT
        ;;

    "deploy")
        log "Deploying to $ENVIRONMENT environment..."

        # Build first
        ./build.sh build $ENVIRONMENT || error "Build failed"

        # Deploy based on environment
        case $ENVIRONMENT in
            "production")
                log "Deploying to production..."
                docker-compose -f docker-compose.prod.yml up -d --build
                ;;
            "staging")
                log "Deploying to staging..."
                docker-compose -f docker-compose.staging.yml up -d --build
                ;;
            *)
                log "Deploying to development..."
                docker-compose up -d --build
                ;;
        esac

        success "Deployment completed!"
        ;;

    "clean")
        log "Cleaning build artifacts..."
        rm -rf $BUILD_DIR $BACKUP_DIR
        docker-compose down --volumes --remove-orphans
        docker system prune -f
        success "Cleanup completed!"
        ;;

    "test")
        log "Running tests..."

        # Check if build exists
        if [ ! -d "$BUILD_DIR" ]; then
            warning "No build found. Building first..."
            ./build.sh build
        fi

        # Test homepage
        if [ ! -f "$BUILD_DIR/index.html" ]; then
            error "Homepage not found"
        fi

        # Test sitemap
        if [ ! -f "$BUILD_DIR/sitemap.xml" ]; then
            error "Sitemap not found"
        fi

        # Test robots.txt
        if [ ! -f "$BUILD_DIR/robots.txt" ]; then
            error "robots.txt not found"
        fi

        # Test word pages structure
        if [ ! -d "$BUILD_DIR/words" ]; then
            error "Words directory not found"
        fi

        # Check for broken links (basic)
        log "Checking for basic issues..."
        grep -r "href=\"#\"" $BUILD_DIR && warning "Found placeholder links"
        grep -r "src=\"\"" $BUILD_DIR && warning "Found empty src attributes"

        success "Basic tests passed!"
        ;;

    "stats")
        log "Generating build statistics..."

        if [ ! -d "$BUILD_DIR" ]; then
            error "No build found. Run './build.sh build' first"
        fi

        echo "📊 Build Statistics:"
        echo "==================="
        echo "Total HTML pages: $(find $BUILD_DIR -name "*.html" | wc -l)"
        echo "Word pages: $(find $BUILD_DIR/words -name "*.html" | wc -l)"
        echo "Letter pages: $(find $BUILD_DIR/letters -name "*.html" | wc -l)"
        echo "Total size: $(du -sh $BUILD_DIR | cut -f1)"
        echo "CSS files: $(find $BUILD_DIR -name "*.css" | wc -l)"
        echo "JS files: $(find $BUILD_DIR -name "*.js" | wc -l)"
        echo "Image files: $(find $BUILD_DIR -name "*.png" -o -name "*.jpg" -o -name "*.svg" | wc -l)"

        # Check sitemap size
        if [ -f "$BUILD_DIR/sitemap.xml" ]; then
            SITEMAP_URLS=$(grep -c "<url>" $BUILD_DIR/sitemap.xml || echo "0")
            echo "Sitemap URLs: $SITEMAP_URLS"
        fi
        ;;

    "help")
        echo "🔧 Unforgettable Dictionary Build Script"
        echo "========================================"
        echo ""
        echo "Usage: ./build.sh [command] [environment] [options]"
        echo ""
        echo "Commands:"
        echo "  build [env]     - Build the static site (default: development)"
        echo "  serve [port]    - Serve the built site locally (default: 8000)"
        echo "  deploy [env]    - Build and deploy (production|staging|development)"
        echo "  clean           - Clean all build artifacts and Docker resources"
        echo "  test            - Run basic tests on the built site"
        echo "  stats           - Show build statistics"
        echo "  help            - Show this help message"
        echo ""
        echo "Environments:"
        echo "  development     - Local development (default)"
        echo "  staging         - Staging environment"
        echo "  production      - Production environment"
        echo ""
        echo "Examples:"
        echo "  ./build.sh build production"
        echo "  ./build.sh serve 3000"
        echo "  ./build.sh deploy staging"
        echo "  ./build.sh clean"
        ;;

    *)
        error "Unknown command: $COMMAND. Use './build.sh help' for usage information."
        ;;
esac