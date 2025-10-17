#!/bin/bash

# Setup script for integration testing environment
# This script starts the Dynapins server and configures test environment

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🚀 Setting up Dynapins iOS Integration Test Environment"
echo "======================================================="
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose is not installed. Please install docker-compose first."
    exit 1
fi

# Start the Dynapins server
echo "📦 Starting Dynapins server..."
docker-compose -f docker-compose.test.yml up -d

# Wait for service to be healthy
echo "⏳ Waiting for server to be ready..."
for i in {1..30}; do
    if docker-compose -f docker-compose.test.yml ps | grep -q "healthy"; then
        echo -e "${GREEN}✓ Server is ready!${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Server failed to start within timeout"
        docker-compose -f docker-compose.test.yml logs
        exit 1
    fi
    sleep 1
done

# Test server availability
echo "🔍 Testing server availability..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/v1/pins?domain=example.com" || echo "000")

if [ "$RESPONSE" = "200" ]; then
    echo -e "${GREEN}✓ Server is responding correctly${NC}"
else
    echo "❌ Server returned status: $RESPONSE"
    docker-compose -f docker-compose.test.yml logs
    exit 1
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "📝 Test environment variables:"
echo "================================"
echo 'export TEST_SERVICE_URL="http://localhost:8080/v1/pins?domain="'
echo 'export TEST_PUBLIC_KEY="MCowBQYDK2VwAyEAJQR7u1MBm3cWcF3e4xGXqF9HN/ZgYjX1cVEkR8Wfkw0="'
echo 'export TEST_DOMAIN="example.com"'
echo ""
echo "📋 To set these automatically, run:"
echo "  source <(./Scripts/export-test-vars.sh)"
echo ""
echo "🧪 To run tests:"
echo "  ./Scripts/run-integration-tests.sh"
echo ""
echo "🛑 To stop the server:"
echo "  docker-compose -f docker-compose.test.yml down"
echo ""

