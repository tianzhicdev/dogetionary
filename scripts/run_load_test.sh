#!/bin/bash
#
# Quick Load Test Runner for Dogetionary API
# ===========================================
#
# This script provides preset configurations for common load testing scenarios.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
HOST="${LOAD_TEST_HOST:-https://kwafy.com}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Dogetionary Load Test Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Create and activate virtual environment
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}📦 Creating virtual environment...${NC}"
    python3 -m venv "$VENV_DIR"
    echo -e "${GREEN}✅ Virtual environment created${NC}"
fi

# Activate virtual environment
echo -e "${BLUE}🔧 Activating virtual environment...${NC}"
source "$VENV_DIR/bin/activate"

# Check if dependencies are installed
if ! python -c "import locust" 2>/dev/null; then
    echo -e "${YELLOW}📥 Installing dependencies...${NC}"
    pip install --upgrade pip
    pip install -r "$SCRIPT_DIR/load_test_requirements.txt"
    echo -e "${GREEN}✅ Dependencies installed${NC}"
fi

# Function to display usage
usage() {
    echo "Usage: $0 [scenario] [options]"
    echo ""
    echo "Scenarios:"
    echo "  quick       - Quick 1-minute test (10 users)"
    echo "  smoke       - Smoke test with minimal load (5 users, 30s)"
    echo "  load        - Standard load test (25 users, 5 minutes)"
    echo "  stress      - Stress test (50 users, 10 minutes)"
    echo "  spike       - Spike test (100 users, 2 minutes)"
    echo "  simple      - Simple benchmark without Locust (10 users, 30s)"
    echo "  web         - Start Locust web UI"
    echo ""
    echo "Options:"
    echo "  --host=URL  - API host URL (default: $HOST)"
    echo ""
    echo "Examples:"
    echo "  $0 quick"
    echo "  $0 load --host=https://staging.kwafy.com"
    echo "  $0 web"
    echo ""
    exit 1
}

# Parse command line arguments
SCENARIO="${1:-}"
shift || true

for arg in "$@"; do
    case $arg in
        --host=*)
            HOST="${arg#*=}"
            ;;
        --help|-h)
            usage
            ;;
    esac
done

# Run the appropriate scenario
case "$SCENARIO" in
    quick)
        echo -e "${GREEN}Running QUICK test (10 users, 1 minute)${NC}"
        python -m locust -f "$SCRIPT_DIR/load_test.py" \
            --host="$HOST" \
            --headless \
            --users 10 \
            --spawn-rate 2 \
            --run-time 1m
        ;;

    smoke)
        echo -e "${GREEN}Running SMOKE test (5 users, 30 seconds)${NC}"
        python -m locust -f "$SCRIPT_DIR/load_test.py" \
            --host="$HOST" \
            --headless \
            --users 5 \
            --spawn-rate 1 \
            --run-time 30s
        ;;

    load)
        echo -e "${GREEN}Running LOAD test (25 users, 5 minutes)${NC}"
        python -m locust -f "$SCRIPT_DIR/load_test.py" \
            --host="$HOST" \
            --headless \
            --users 25 \
            --spawn-rate 5 \
            --run-time 5m
        ;;

    stress)
        echo -e "${YELLOW}Running STRESS test (50 users, 10 minutes)${NC}"
        echo -e "${YELLOW}⚠️  This will put significant load on the server${NC}"
        read -p "Continue? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            python -m locust -f "$SCRIPT_DIR/load_test.py" \
                --host="$HOST" \
                --headless \
                --users 50 \
                --spawn-rate 10 \
                --run-time 10m
        else
            echo "Cancelled."
            exit 0
        fi
        ;;

    spike)
        echo -e "${RED}Running SPIKE test (100 users, 2 minutes)${NC}"
        echo -e "${RED}⚠️  WARNING: This will spike the server to 100 concurrent users${NC}"
        read -p "Continue? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            python -m locust -f "$SCRIPT_DIR/load_test.py" \
                --host="$HOST" \
                --headless \
                --users 100 \
                --spawn-rate 20 \
                --run-time 2m
        else
            echo "Cancelled."
            exit 0
        fi
        ;;

    simple)
        echo -e "${GREEN}Running SIMPLE benchmark (10 users, 30 seconds)${NC}"
        python "$SCRIPT_DIR/load_test.py" \
            --simple \
            --host="$HOST" \
            --users 10 \
            --duration 30
        ;;

    web)
        echo -e "${GREEN}Starting Locust WEB UI${NC}"
        echo -e "${BLUE}Open http://localhost:8089 in your browser${NC}"
        echo -e "${BLUE}Target host: $HOST${NC}"
        echo ""
        python -m locust -f "$SCRIPT_DIR/load_test.py" --host="$HOST"
        ;;

    "")
        echo -e "${RED}Error: No scenario specified${NC}"
        echo ""
        usage
        ;;

    *)
        echo -e "${RED}Error: Unknown scenario '$SCENARIO'${NC}"
        echo ""
        usage
        ;;
esac

echo ""
echo -e "${GREEN}✅ Load test complete${NC}"
echo -e "${BLUE}Check load_test_report_*.txt for detailed results${NC}"
