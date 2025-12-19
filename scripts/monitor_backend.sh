#!/bin/bash
#
# Monitor Backend API Logs in Real-Time
# ======================================
#
# This script follows backend logs and filters for actual API requests
# (excludes Prometheus metrics scraping)
#
# Usage:
#   ./monitor_backend.sh
#

set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Backend API Request Monitor${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}Monitoring backend logs (excluding /metrics)${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

cd /Users/biubiu/projects/dogetionary

# Follow logs and filter out Prometheus metrics requests
docker-compose logs -f app 2>&1 | grep --line-buffered -v "metrics_endpoint" | grep --line-buffered -E "(REQUEST|RESPONSE|ERROR|WARNING)"
