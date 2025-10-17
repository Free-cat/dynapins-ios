SHELL := /bin/bash

ENV_FILE ?= .env.e2e
COMPOSE := docker compose --env-file $(ENV_FILE) -f docker-compose.e2e.yml

KEY_FILE ?= /tmp/dynapins-e2e/private_key.pem

.PHONY: help test test-unit test-integration test-all e2e-build e2e-pull e2e-down gen-key print-env wait pod-lint pod-register pod-push pod-release

help:
	@echo "Testing:"
	@echo "  make test             # Run unit tests only (fast, ~5s)"
	@echo "  make test-integration # Run E2E integration tests (requires server)"
	@echo "  make test-all         # Run all tests (unit + integration)"
	@echo ""
	@echo "E2E Environment:"
	@echo "  make e2e-build        # Build local image + run integration tests"
	@echo "  make e2e-pull         # Pull Docker Hub image + run integration tests"
	@echo "  make e2e-down         # Stop and remove E2E containers"
	@echo ""
	@echo "Utilities:"
	@echo "  make gen-key          # Generate ECDSA P-256 private key"
	@echo ""
	@echo "CocoaPods:"
	@echo "  make pod-check        # Check CocoaPods setup"
	@echo "  make pod-lint         # Validate podspec locally"
	@echo "  make pod-register     # Register with CocoaPods trunk (one-time)"
	@echo "  make pod-push         # Publish to CocoaPods"
	@echo "  make pod-release      # Full release: lint + push"

$(ENV_FILE):
	@[ -f $(ENV_FILE) ] || cp .env.e2e.example $(ENV_FILE)

# Generate ECDSA P-256 key (ES256) if not provided in env
gen-key:
	@mkdir -p $(dir $(KEY_FILE))
	@if [ ! -f $(KEY_FILE) ]; then \
		echo "Generating ECDSA P-256 (ES256) private key at $(KEY_FILE)..."; \
		openssl ecparam -genkey -name prime256v1 -out $(KEY_FILE).tmp; \
		openssl pkcs8 -topk8 -nocrypt -in $(KEY_FILE).tmp -out $(KEY_FILE); \
		rm -f $(KEY_FILE).tmp; \
		echo "Done."; \
	fi
	@echo "Export PRIVATE_KEY_PEM to .env.e2e or let Makefile load it from $(KEY_FILE)"
	@# Extract public key for TEST_PUBLIC_KEY
	@if [ -f $(KEY_FILE) ] && ! grep -q '^TEST_PUBLIC_KEY=' $(ENV_FILE) 2>/dev/null; then \
		echo "Extracting public key for tests..."; \
		PUB_KEY=$$(openssl ec -in $(KEY_FILE) -pubout 2>/dev/null | grep -v "BEGIN\|END" | tr -d '\n'); \
		echo "TEST_PUBLIC_KEY=$$PUB_KEY" >> $(ENV_FILE); \
		echo "Added TEST_PUBLIC_KEY to $(ENV_FILE)"; \
	fi

print-env: $(ENV_FILE)
	@echo "Using env file: $(ENV_FILE)"; \
	grep -E '^(DYNAPINS_IMAGE|SERVER_PORT|ALLOWED_DOMAINS|SIGNATURE_LIFETIME|LOG_LEVEL)' $(ENV_FILE) || true

# Wait for health
wait:
	@echo "Waiting for server to be healthy..."; \
	for i in {1..60}; do \
		if curl -s -o /dev/null -w '%{http_code}' http://localhost:$${SERVER_PORT:-8080}/health | grep -q 200; then \
			echo "Server is healthy"; exit 0; \
		fi; \
		sleep 1; \
	done; \
	echo "Server failed to become healthy"; exit 1

# Build locally and run
e2e-build: $(ENV_FILE) gen-key
	@PRIVATE_KEY_PEM="$$(cat $(KEY_FILE))" $(COMPOSE) --profile build up -d --build
	@$(MAKE) wait
	@$(MAKE) test-integration

# Pull from Hub and run
e2e-pull: $(ENV_FILE) gen-key
	@PRIVATE_KEY_PEM="$$(cat $(KEY_FILE))" $(COMPOSE) --profile pull up -d
	@$(MAKE) wait
	@$(MAKE) test-integration

# Stop
e2e-down:
	@$(COMPOSE) down -v

# Run unit tests only (fast, no external dependencies)
test: test-unit

test-unit:
	@if command -v xcbeautify >/dev/null 2>&1; then \
		swift test --filter DynamicPinningTests --skip PinningIntegrationTests 2>&1 | xcbeautify; \
	else \
		swift test --filter DynamicPinningTests --skip PinningIntegrationTests; \
	fi

# Run integration tests (requires running server with env vars)
test-integration:
	@set -a; source $(ENV_FILE); set +a; \
	export TEST_SERVICE_URL="http://localhost:$${SERVER_PORT:-8080}/v1/pins"; \
	if command -v xcbeautify >/dev/null 2>&1; then \
		swift test --filter PinningIntegrationTests 2>&1 | xcbeautify; \
	else \
		swift test --filter PinningIntegrationTests; \
	fi

# Run all tests (unit + integration)
test-all:
	@set -a; source $(ENV_FILE); set +a; \
	export TEST_SERVICE_URL="http://localhost:$${SERVER_PORT:-8080}/v1/pins"; \
	if command -v xcbeautify >/dev/null 2>&1; then \
		swift test 2>&1 | xcbeautify; \
	else \
		swift test; \
	fi

# CocoaPods commands
pod-check:
	@echo "🔍 Checking CocoaPods setup..."
	@if command -v pod >/dev/null 2>&1; then \
		echo "✅ CocoaPods found: $$(pod --version 2>/dev/null || echo 'version unknown')"; \
	else \
		echo "❌ CocoaPods not found. Install with: gem install cocoapods"; \
		exit 1; \
	fi

pod-lint:
	@echo "🔍 Local linting (without git tag check)..."
	@command -v pod >/dev/null 2>&1 || { echo "❌ CocoaPods not found. Install: gem install cocoapods"; exit 1; }
	@pod lib lint dynapins-ios.podspec --allow-warnings --skip-import-validation && echo "✅ Podspec is valid!"

pod-lint-remote:
	@echo "🔍 Remote linting (requires git tag v0.2.0)..."
	@command -v pod >/dev/null 2>&1 || { echo "❌ CocoaPods not found. Install: gem install cocoapods"; exit 1; }
	@pod spec lint dynapins-ios.podspec --allow-warnings

pod-register:
	@echo "📝 Registering with CocoaPods trunk..."
	@echo "This will send verification email to freecats1997@gmail.com"
	@command -v pod >/dev/null 2>&1 || { echo "❌ CocoaPods not found. Install: gem install cocoapods"; exit 1; }
	@pod trunk register freecats1997@gmail.com 'Artem Melnikov' --description='Dynamic Pinning iOS SDK'

pod-push:
	@echo "🚀 Publishing to CocoaPods..."
	@command -v pod >/dev/null 2>&1 || { echo "❌ CocoaPods not found. Install: gem install cocoapods"; exit 1; }
	@pod trunk push dynapins-ios.podspec --allow-warnings

pod-release: pod-check
	@echo "🚀 CocoaPods release..."
	@command -v pod >/dev/null 2>&1 || { echo "❌ CocoaPods not found. Install: gem install cocoapods"; exit 1; }
	@echo "🔍 Linting..."
	@pod spec lint dynapins-ios.podspec --allow-warnings
	@echo "📦 Publishing..."
	@pod trunk push dynapins-ios.podspec --allow-warnings
	@echo "✅ CocoaPods release complete!"