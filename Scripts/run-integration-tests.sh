#!/bin/bash

# Script to run integration tests for Dynapins iOS SDK
# This script sets up the environment and runs e2e tests against a live backend

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🧪 Dynapins iOS - Integration Tests"
echo "===================================="
echo ""

# Check if environment variables are set
if [ -z "$TEST_SERVICE_URL" ]; then
    echo -e "${RED}❌ TEST_SERVICE_URL not set${NC}"
    echo "Example: export TEST_SERVICE_URL='http://localhost:8080/v1/pins?domain='"
    exit 1
fi

if [ -z "$TEST_PUBLIC_KEY" ]; then
    echo -e "${RED}❌ TEST_PUBLIC_KEY not set${NC}"
    echo "Example: export TEST_PUBLIC_KEY='MCowBQYDK2VwAyEA...'"
    exit 1
fi

if [ -z "$TEST_DOMAIN" ]; then
    echo -e "${RED}❌ TEST_DOMAIN not set${NC}"
    echo "Example: export TEST_DOMAIN='example.com'"
    exit 1
fi

echo -e "${GREEN}✓ Configuration loaded${NC}"
echo "  Service URL: $TEST_SERVICE_URL"
echo "  Test Domain: $TEST_DOMAIN"
echo "  Public Key: ${TEST_PUBLIC_KEY:0:20}..."
echo ""

# Check if service is reachable
echo "🔍 Checking service availability..."
if curl -s -o /dev/null -w "%{http_code}" "$TEST_SERVICE_URL$TEST_DOMAIN" | grep -q "200"; then
    echo -e "${GREEN}✓ Service is reachable${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: Service may not be reachable${NC}"
    echo "  Make sure your Dynapins server is running:"
    echo "  docker run -p 8080:8080 -e ALLOWED_DOMAINS=\"$TEST_DOMAIN\" freecats/dynapins-server:latest"
fi
echo ""

# Run the tests
echo "🏃 Running integration tests..."
echo ""

swift test --filter PinningIntegrationTests --enable-test-discovery

EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✅ All integration tests passed!${NC}"
else
    echo -e "${RED}❌ Integration tests failed${NC}"
fi

exit $EXIT_CODE

