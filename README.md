# Dynapins iOS SDK

> Lightweight, dependency-free iOS SDK for dynamic TLS certificate pinning with automatic fingerprint management.

[![Build Status](https://github.com/Free-cat/dynapins-ios/workflows/CI/badge.svg)](https://github.com/Free-cat/dynapins-ios/actions)
[![Swift Version](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%2014.0+-lightgrey.svg)](https://www.apple.com/ios/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)

## 🚀 Features

- **🔒 Secure by Default**: All connections fail-closed on validation errors
- **⚡️ Zero Dependencies**: Self-contained with only Apple frameworks
- **🎯 Drop-in Integration**: < 30 minutes to add to existing apps
- **🔄 Automatic Updates**: Fetches and caches fingerprints dynamically
- **✍️ Cryptographic Verification**: Ed25519 signature validation
- **🔐 Secure Storage**: Fingerprints cached in iOS Keychain
- **🌐 Wildcard Support**: Matches patterns like `*.example.com`
- **📱 iOS 14.0+**: Modern Swift Package Manager distribution

## 📦 Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Free-cat/dynapins-ios.git", from: "1.0.0")
]
```

Or in Xcode:
1. File → Add Packages
2. Enter the repository URL
3. Select version and add to your target

## 🎯 Quick Start

### 1. Initialize the SDK

In your `AppDelegate` or app initialization code:

```swift
import DynamicPinning

// Initialize once at app launch
DynamicPinning.initialize(
    publicKey: "MCowBQYDK2VwAyEA...", // Your Ed25519 public key (Base64)
    serviceURL: URL(string: "https://your-server.com/v1/pins?domain=api.example.com")!
)
```

### 2. Use the Preconfigured URLSession

```swift
// Get a URLSession with automatic pinning
let session = DynamicPinning.session()

// Make requests - pinning happens automatically
let task = session.dataTask(with: URL(string: "https://api.example.com/data")!) { data, response, error in
    if let error = error {
        // Connection failed (could be pinning failure)
        print("Request failed: \(error)")
        return
    }
    
    // Connection succeeded and certificate was validated!
    if let data = data {
        // Process your data
    }
}

task.resume()
```

That's it! 🎉 Your app now uses dynamic certificate pinning.

## 📖 How It Works

1. **Initialization**: You provide an Ed25519 public key and a Dynapins service URL
2. **First Request**: SDK fetches a signed fingerprint from your service
3. **Verification**: Signature is verified using the embedded public key
4. **Validation**: Server's certificate is hashed and compared to the fingerprint
5. **Caching**: Valid fingerprints are cached in Keychain with TTL
6. **Subsequent Requests**: Cached fingerprints are used until they expire

```
┌─────────────┐
│   Your App  │
└──────┬──────┘
       │ 1. Initialize
       ▼
┌─────────────────┐      2. Fetch Fingerprint     ┌──────────────────┐
│ DynamicPinning  │ ──────────────────────────────▶│ Dynapins Service │
│      SDK        │                                 └──────────────────┘
└─────────────────┘                                          │
       │                                                     │
       │ 3. Verify Signature (Ed25519)                      │
       │◀────────────────────────────────────────────────────┘
       │
       │ 4. TLS Handshake
       ▼
┌─────────────────┐
│  Your Backend   │
│   (api.com)     │
└─────────────────┘
       │
       │ 5. Hash & Compare Certificate
       ▼
    ✅ Success or ❌ Fail
```

## 🔐 Security Guarantees

- **Fail-Closed**: All errors (network, signature, hash mismatch) result in connection termination
- **No Downgrades**: The SDK never falls back to default certificate validation
- **Signature Required**: Fingerprints must be cryptographically signed by your public key
- **Secure Storage**: Cached fingerprints are stored in iOS Keychain with encryption
- **No Sensitive Data**: SDK never logs or transmits PII or certificate material

## 🎛️ Advanced Usage

### Multiple Domains

The SDK supports wildcard patterns from the service:

```json
{
  "domain": "*.example.com",
  "fingerprint": "a1b2c3...",
  "signature": "...",
  "ttl": 86400
}
```

This will match:
- `api.example.com` ✅
- `cdn.example.com` ✅
- `example.com` ❌ (wildcard requires subdomain)

### Error Handling

```swift
let session = DynamicPinning.session()

let task = session.dataTask(with: url) { data, response, error in
    if let error = error as? URLError {
        switch error.code {
        case .serverCertificateUntrusted:
            // Pinning validation failed
            print("Certificate pinning failed")
        case .cannotConnectToHost:
            // Network issue
            print("Network error")
        default:
            print("Other error: \(error)")
        }
    }
}
```

### Using with Async/Await

```swift
let session = DynamicPinning.session()

do {
    let (data, response) = try await session.data(from: url)
    // Process data
} catch {
    // Handle error
}
```

## 🛠️ Configuration

### Required

- **publicKey**: Ed25519 public key (Base64-encoded, raw format)
- **serviceURL**: URL to your Dynapins service endpoint

### Service Response Format

Your Dynapins server must return JSON in this format:

```json
{
  "domain": "*.example.com",
  "fingerprint": "a1b2c3d4e5f6...",
  "signature": "dGVzdF9zaWduYXR1cmU=",
  "ttl": 86400
}
```

Where:
- `domain`: Domain pattern (exact or wildcard like `*.example.com`)
- `fingerprint`: SHA-256 hash of the certificate's public key (hex)
- `signature`: Ed25519 signature of the fingerprint (Base64)
- `ttl`: Time-to-live in seconds

### Running the Dynapins Server

The easiest way to run the backend is using Docker:

```bash
# Generate Ed25519 key pair
openssl genpkey -algorithm Ed25519 -out private_key.pem
openssl pkey -in private_key.pem -pubout -out public_key.pem

# Run the server
docker run -p 8080:8080 \
  -e ALLOWED_DOMAINS="example.com,*.example.com" \
  -e PRIVATE_KEY_PEM="$(cat private_key.pem)" \
  freecats/dynapins-server:latest
```

See the [Dynapins Server documentation](https://github.com/Free-cat/dynapins-server) for more details.

## 🧪 Testing

### Unit Tests

Run the unit test suite:

```bash
swift test
```

### Integration Tests (E2E)

Run end-to-end tests against a live backend:

```bash
# 1. Start the test server
./Scripts/setup-test-env.sh

# 2. Export test variables
source <(./Scripts/export-test-vars.sh)

# 3. Run integration tests
./Scripts/run-integration-tests.sh
```

See [Integration Testing Guide](./Docs/integration-testing.md) for detailed instructions.

## 📊 Performance

- **First Request**: < 50ms overhead (includes network fetch + verification)
- **Cached Requests**: < 1ms overhead (Keychain lookup + hash comparison)
- **Binary Size**: < 100KB added to your app

## 🚨 Important Notes

### Multiple Initialization

⚠️ **DEBUG builds**: Calling `initialize()` multiple times will crash with `preconditionFailure`  
ℹ️ **RELEASE builds**: Subsequent calls are ignored with a warning log

### Thread Safety

All SDK methods are thread-safe and can be called from any queue.

### Testing Your Integration

1. Ensure your Dynapins service is running and accessible
2. Make a test request to a domain covered by your fingerprint
3. Check logs for any warnings or errors
4. Verify the connection succeeds

## 🔗 Related Projects

- **[Dynapins Server](https://github.com/Free-cat/dynapins-server)** - Go backend for serving signed fingerprints
  - Docker image: [`freecats/dynapins-server`](https://hub.docker.com/r/freecats/dynapins-server)
- **[Dynapins Android](https://github.com/Free-cat/dynapins-android)** - Android SDK (coming soon)

## 📚 Additional Documentation

- [Architecture Overview](./Docs/architecture.md) - How the SDK works internally
- [Integration Testing Guide](./Docs/integration-testing.md) - Running e2e tests
- [Dynapins Server Setup](https://github.com/Free-cat/dynapins-server#readme) - Backend deployment guide

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

## 🙋 Support

- Report issues: [GitHub Issues](https://github.com/Free-cat/dynapins-ios/issues)
- Questions: Open a [GitHub Discussion](https://github.com/Free-cat/dynapins-ios/discussions)

## 📄 License

MIT License - Copyright (c) 2025 Artem Melnikov

See [LICENSE](./LICENSE) for full details.

---

**Built with ❤️ by [Free-cat](https://github.com/Free-cat) for iOS developers who care about security**
