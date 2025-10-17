#!/bin/bash

# Export test environment variables
# Usage: source <(./Scripts/export-test-vars.sh)

export TEST_SERVICE_URL="http://localhost:8080/v1/pins?domain="
export TEST_PUBLIC_KEY="MCowBQYDK2VwAyEA9gocJEBHG+vcm2OH42ZEy8XiYarSBJ3ZBTA5Ni7J+Ac="
export TEST_DOMAIN="example.com"

echo "✓ Test environment variables exported"
echo "  TEST_SERVICE_URL=$TEST_SERVICE_URL"
echo "  TEST_DOMAIN=$TEST_DOMAIN"
echo "  TEST_PUBLIC_KEY=${TEST_PUBLIC_KEY:0:20}..."

