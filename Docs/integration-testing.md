# Integration Testing Guide

This guide explains how to run end-to-end (e2e) integration tests for the Dynapins iOS SDK against a live backend server.

## 📋 Prerequisites

### 1. Dynapins Server

You need a running Dynapins server. The easiest way is using Docker:

```bash
# Generate Ed25519 key pair
openssl genpkey -algorithm Ed25519 -out private_key.pem
openssl pkey -in private_key.pem -pubout -out public_key.pem

# Run the server
docker run -d -p 8080:8080 \
  -e ALLOWED_DOMAINS="example.com,*.example.com" \
  -e PRIVATE_KEY_PEM="$(cat private_key.pem)" \
  --name dynapins-server \
  freecats/dynapins-server:latest
```

Verify the server is running:

```bash
curl "http://localhost:8080/v1/pins?domain=example.com"
```

### 2. Test Domain

You need a domain with a valid TLS certificate that:
- Is allowed in the server's `ALLOWED_DOMAINS` configuration
- Has a publicly accessible HTTPS endpoint
- Uses a valid, non-expired certificate

Common options:
- Use a real domain you control (e.g., `api.example.com`)
- Use a public test domain (e.g., `example.com`, `httpbin.org`)

### 3. Public Key

Extract the public key from your private key in the correct format:

```bash
# Extract public key
openssl pkey -in private_key.pem -pubout -out public_key.pem

# Convert to Base64 (for use in tests)
# On macOS:
PUBLIC_KEY=$(openssl pkey -in private_key.pem -pubout -outform DER | tail -c 32 | base64)

# On Linux:
PUBLIC_KEY=$(openssl pkey -in private_key.pem -pubout -outform DER | tail -c 32 | base64 -w 0)

echo $PUBLIC_KEY
```

## 🚀 Running Integration Tests

### Method 1: Using the Helper Script (Recommended)

```bash
# Set environment variables
export TEST_SERVICE_URL="http://localhost:8080/v1/pins?domain="
export TEST_PUBLIC_KEY="MCowBQYDK2VwAyEA..."  # Your Base64-encoded public key
export TEST_DOMAIN="example.com"

# Run the tests
./Scripts/run-integration-tests.sh
```

### Method 2: Running Directly with Swift

```bash
# Set environment variables
export TEST_SERVICE_URL="http://localhost:8080/v1/pins?domain="
export TEST_PUBLIC_KEY="MCowBQYDK2VwAyEA..."
export TEST_DOMAIN="example.com"

# Run all integration tests
swift test --filter PinningIntegrationTests

# Run a specific test
swift test --filter PinningIntegrationTests.testEndToEndPinningFlow
```

### Method 3: Using Xcode

1. Open the package in Xcode
2. Edit the test scheme (Product → Scheme → Edit Scheme)
3. Go to Test → Arguments → Environment Variables
4. Add:
   - `TEST_SERVICE_URL` = `http://localhost:8080/v1/pins?domain=`
   - `TEST_PUBLIC_KEY` = Your Base64 public key
   - `TEST_DOMAIN` = `example.com`
5. Run tests (⌘U)

## 🧪 Available Tests

### Basic Integration Tests

#### `testEndToEndPinningFlow`
Tests the complete flow from SDK initialization to successful HTTPS request with certificate pinning.

**What it tests:**
- SDK initialization
- Session creation
- HTTPS request with pinning validation
- Success for valid certificates

**Expected outcome:** ✅ Request succeeds

---

#### `testCachingBehavior`
Verifies that fingerprints are cached and reused correctly.

**What it tests:**
- First request fetches from service (cache miss)
- Second request uses cached fingerprint (cache hit)
- Observability events are emitted correctly

**Expected outcome:** ✅ Cache miss on first request, cache hit on second

---

#### `testObservabilityEvents`
Validates that observability hooks work correctly.

**What it tests:**
- Event handler receives events
- Cache events are emitted
- Success events are emitted for valid certificates

**Expected outcome:** ✅ All expected events are emitted

### Failure Scenario Tests

#### `testInvalidDomainFails`
Verifies that requests to non-allowed domains fail.

**What it tests:**
- Request to domain not in server's `ALLOWED_DOMAINS`
- Connection is rejected

**Expected outcome:** ✅ Request fails with error

---

#### `testInvalidPublicKeyFails`
Tests that invalid public keys cause validation to fail.

**What it tests:**
- Signature verification with wrong public key
- Failure reason is captured via observability

**Expected outcome:** ✅ Request fails with signature verification error

### Performance Tests

#### `testPinningPerformance`
Measures the performance overhead of certificate pinning with cached fingerprints.

**What it tests:**
- Response time for requests with cached fingerprints
- Performance overhead is minimal

**Expected outcome:** ✅ < 10ms overhead per request

---

#### `testConcurrentRequests`
Tests behavior under concurrent load.

**What it tests:**
- Multiple simultaneous requests
- Thread safety
- All requests succeed

**Expected outcome:** ✅ All 10 concurrent requests succeed

### Utility Tests

#### `testServiceAvailability`
Checks that the backend service is reachable.

**What it tests:**
- HTTP 200 response from service
- Service is accessible

**Expected outcome:** ✅ Service returns 200 OK

## 🔧 Troubleshooting

### Test Skipped: Environment Not Configured

**Symptom:**
```
⚠️ Skipping integration tests - environment variables not set
```

**Solution:**
Set all three required environment variables:
```bash
export TEST_SERVICE_URL="http://localhost:8080/v1/pins?domain="
export TEST_PUBLIC_KEY="MCowBQYDK2VwAyEA..."
export TEST_DOMAIN="example.com"
```

### Service Unavailable

**Symptom:**
```
❌ Dynapins service should be available at http://localhost:8080/...
```

**Solution:**
1. Check if Docker container is running:
   ```bash
   docker ps | grep dynapins-server
   ```

2. Check server logs:
   ```bash
   docker logs dynapins-server
   ```

3. Restart the server:
   ```bash
   docker restart dynapins-server
   ```

### Signature Verification Failed

**Symptom:**
```
❌ Request failed with signature verification error
```

**Solution:**
1. Verify your public key matches the private key used by the server:
   ```bash
   # Compare fingerprints
   openssl pkey -in private_key.pem -pubout | openssl pkey -pubin -outform DER | sha256sum
   ```

2. Ensure the public key is properly Base64-encoded:
   ```bash
   openssl pkey -in private_key.pem -pubout -outform DER | tail -c 32 | base64
   ```

### Domain Not Allowed

**Symptom:**
```
❌ Request failed: Domain mismatch
```

**Solution:**
1. Check server's `ALLOWED_DOMAINS` configuration:
   ```bash
   docker inspect dynapins-server | grep ALLOWED_DOMAINS
   ```

2. Ensure your test domain is included:
   ```bash
   docker run -e ALLOWED_DOMAINS="example.com,*.example.com" ...
   ```

### Certificate Issues

**Symptom:**
```
❌ Fingerprint mismatch
```

**Solution:**
1. Verify the domain has a valid certificate:
   ```bash
   openssl s_client -connect example.com:443 -servername example.com < /dev/null
   ```

2. Check if the certificate has changed recently
3. Clear the Keychain cache and re-run tests

## 📊 Interpreting Results

### Successful Test Run

```
✅ testEndToEndPinningFlow - 2.5s
✅ testCachingBehavior - 3.1s
✅ testObservabilityEvents - 2.8s
✅ testInvalidDomainFails - 1.2s
✅ testInvalidPublicKeyFails - 1.5s
✅ testPinningPerformance - 0.8s
✅ testConcurrentRequests - 4.2s
✅ testServiceAvailability - 0.3s

Test Suite 'PinningIntegrationTests' passed at ...
  Executed 8 tests, with 0 failures in 16.4 seconds
```

### Key Metrics to Monitor

- **Success Rate**: All tests should pass (100%)
- **Performance**: Cached requests should be < 10ms
- **Cache Behavior**: Second request should hit cache
- **Failure Handling**: Invalid scenarios should fail gracefully

## 🎯 Continuous Integration

### GitHub Actions Example

Add to `.github/workflows/integration-tests.yml`:

```yaml
name: Integration Tests

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  integration-tests:
    runs-on: macos-14
    
    services:
      dynapins-server:
        image: freecats/dynapins-server:latest
        ports:
          - 8080:8080
        env:
          ALLOWED_DOMAINS: "example.com"
          PRIVATE_KEY_PEM: ${{ secrets.TEST_PRIVATE_KEY }}
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Run Integration Tests
      env:
        TEST_SERVICE_URL: "http://localhost:8080/v1/pins?domain="
        TEST_PUBLIC_KEY: ${{ secrets.TEST_PUBLIC_KEY }}
        TEST_DOMAIN: "example.com"
      run: |
        swift test --filter PinningIntegrationTests
```

## 🔐 Security Notes

- **Private Keys**: Never commit private keys to version control
- **Test Domains**: Use test/staging domains, not production
- **Secrets**: Store keys in CI/CD secrets or environment variables
- **Cleanup**: Clear cached data after tests

## 📚 Additional Resources

- [Dynapins Server Documentation](https://github.com/Free-cat/dynapins-server)
- [SDK Architecture](./architecture.md)
- [Contributing Guide](../CONTRIBUTING.md)

---

**Questions?** Open an issue on [GitHub](https://github.com/Free-cat/dynapins-ios/issues)

