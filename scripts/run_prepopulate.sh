#!/bin/bash
# Simple wrapper to run prepopulate_local.py inside Docker with proper env vars

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Running Local Question Pre-population${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Load API keys from .env.secrets
if [ ! -f "src/.env.secrets" ]; then
    echo "Error: src/.env.secrets not found!"
    echo "Please ensure API keys are configured."
    exit 1
fi

# Extract API keys
GROQ_KEY=$(grep GROQ_API_KEY src/.env.secrets | cut -d'=' -f2)
OPENAI_KEY=$(grep OPENAI_API_KEY src/.env.secrets | cut -d'=' -f2 | tr -d '"')

# Copy script to container
echo "📋 Copying script to Docker container..."
docker exec -i dogetionary-app-1 bash -c 'cat > /app/prepopulate_local.py' < scripts/prepopulate_local.py

# Run the script
echo -e "${GREEN}🚀 Starting pre-population...${NC}"
echo ""

docker exec dogetionary-app-1 bash -c "
export GROQ_API_KEY='$GROQ_KEY' && \
export OPENAI_API_KEY='$OPENAI_KEY' && \
python3 /app/prepopulate_local.py $*
"
