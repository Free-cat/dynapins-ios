# Dynapins iOS SDK

<p align="center">
  <strong>Dynamic TLS certificate pinning for iOS with automatic pin management</strong>
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift Version"></a>
  <a href="https://www.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-14.0+-lightgrey.svg" alt="Platform"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://swift.org/package-manager/"><img src="https://img.shields.io/badge/SPM-compatible-brightgreen.svg" alt="SPM"></a>
</p>

---

## Features

- ✅ **Dynamic Pin Management** - Fetches and updates pins from your backend
- 🔒 **Fail-Closed Security** - All SSL errors block the connection for configured domains
- 🔐 **JWS Verification** - Cryptographically verifies pins using ES256 signatures
- 🔄 **Auto-Retry** - Automatically refreshes pins and retries on SSL failures
- 🎯 **Simple Integration** - 3-line setup, works with standard URLSession
- 🌐 **Wildcard Support** - Supports patterns like `*.example.com`
- 🚀 **Async/Await Ready** - Full Swift concurrency support

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Free-cat/dynapins-ios.git", from: "0.2.0")
]
```

Or in **Xcode**:
1. **File → Add Packages**
2. Enter: `https://github.com/Free-cat/dynapins-ios`
3. Select version and add to target

### CocoaPods

```ruby
pod 'dynapins-ios', '~> 0.2.0'
```

## Quick Start

### 1. Initialize the SDK

In your `AppDelegate` or app initialization:

```swift
import DynamicPinning

DynamicPinning.initialize(
    signingPublicKey: "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...", // Your ES256 public key
    pinningServiceURL: URL(string: "https://pins.example.com/v1/pins")!,
    domains: ["api.example.com", "*.cdn.example.com"]
) { successCount, failureCount in
    print("✅ Pinning configured for \(successCount) domains")
}
```

### 2. Use the Session

```swift
let session = DynamicPinning.session()

// All requests automatically use certificate pinning
session.dataTask(with: URL(string: "https://api.example.com/data")!) { data, response, error in
    if let error = error {
        print("Error: \(error)")
        return
    }
    // Handle response
}.resume()
```

### 3. Async/Await

```swift
let session = DynamicPinning.session()
let (data, response) = try await session.data(from: URL(string: "https://api.example.com")!)
```

That's it! 🎉

## How It Works

```
┌─────────────┐
│   iOS App   │  1. Initialize with ES256 public key + domains
└──────┬──────┘
       │
       ▼
┌─────────────────┐      2. Fetch JWS       ┌──────────────────┐
│ DynamicPinning  │ ─────────────────────▶  │ Dynapins Server  │
│      SDK        │                         └──────────────────┘
└─────────────────┘                                   │
       │  3. Verify JWS signature (ES256)             │
       │◀─────────────────────────────────────────────┘
       │  4. Configure TrustKit with validated pins
       ▼
┌─────────────────┐
│  HTTPS Request  │ ── 5. TLS Handshake + Pin Validation ──▶ ✅ or ❌
└─────────────────┘
       │
       │  On SSL failure:
       ▼
    🔄 Auto-refresh pins and retry once
```

**Key Points:**
- SDK fetches JWS-signed pins from your backend
- Verifies JWS signature using embedded ES256 public key  
- Configures TrustKit for SSL validation
- Automatically retries on SSL failure (refreshes pins once per request)

## Backend Setup

You need to run the [Dynapins Server](https://github.com/Free-cat/dynapins-server) to serve signed pins.

### Quick Start with Docker

```bash
# 1. Generate ES256 keypair
openssl ecparam -genkey -name prime256v1 -out private_key.pem
openssl pkcs8 -topk8 -nocrypt -in private_key.pem -out private_key_pkcs8.pem

# 2. Extract public key (use this in iOS app)
openssl ec -in private_key.pem -pubout | grep -v "BEGIN\|END" | tr -d '\n' > public_key.txt
cat public_key.txt

# 3. Run server
docker run -p 8080:8080 \
  -e ALLOWED_DOMAINS="api.example.com,*.example.com" \
  -e PRIVATE_KEY_PEM="$(cat private_key_pkcs8.pem)" \
  freecats/dynapins-server:latest
```

See [Dynapins Server docs](https://github.com/Free-cat/dynapins-server) for production deployment.

## Advanced Usage

### Manual Pin Refresh

```swift
DynamicPinning.refreshPins { successCount, failureCount in
    print("Refreshed \(successCount) domains")
}
```

### Error Handling

```swift
session.dataTask(with: url) { data, response, error in
    if let error = error as NSError? {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            print("❌ SSL pinning validation failed")
        } else {
            print("❌ Other error: \(error)")
        }
    }
}
```

### Configure Multiple Domains

```swift
DynamicPinning.initialize(
    signingPublicKey: publicKey,
    pinningServiceURL: serviceURL,
    domains: [
        "api.example.com",      // Exact match
        "*.cdn.example.com",    // Wildcard: matches api.cdn.example.com, img.cdn.example.com
        "*.internal.example.com"
    ]
) { successCount, failureCount in
    print("✅ Success: \(successCount), ❌ Failed: \(failureCount)")
}
```

### Include Backup Pins

```swift
DynamicPinning.initialize(
    signingPublicKey: publicKey,
    pinningServiceURL: serviceURL,
    domains: domains,
    includeBackupPins: true  // Include backup pins for certificate rotation
) { successCount, failureCount in
    // Handle result
}
```

## Testing

### Run Tests Locally

```bash
# Unit tests only (fast, ~6 seconds)
make test

# Integration tests (requires running server)
make test-integration

# All tests (unit + integration)
make test-all
```

### E2E Testing with Docker

```bash
# Build local server + run integration tests
make e2e-build

# Or pull from Docker Hub + run tests
make e2e-pull

# Stop containers
make e2e-down

# Show all commands
make help
```

### Manual Integration Test

```bash
# 1. Start server
docker run -p 8080:8080 \
  -e ALLOWED_DOMAINS="api.example.com" \
  -e PRIVATE_KEY_PEM="$(cat private_key.pem)" \
  freecats/dynapins-server:latest

# 2. Set environment variables
export TEST_SERVICE_URL="http://localhost:8080/v1/pins"
export TEST_PUBLIC_KEY="<your-public-key>"
export TEST_DOMAIN="api.example.com"

# 3. Run integration tests
swift test --filter PinningIntegrationTests
```

## Security

### What's Protected

- **JWS Signature Verification**: All pins must be signed with your ES256 private key
- **Domain Validation**: Payload domain must match the requested domain
- **Fail-Closed Policy**: SSL errors for configured domains always block the connection
- **No Downgrades**: Uses explicit URLSessionDelegate (TrustKit swizzling disabled)
- **Wildcard Matching**: Secure wildcard support with proper validation

### Security Model

```
✅ Good: Request to configured domain with valid pin → Connection allowed
❌ Fail: Request to configured domain with invalid pin → Connection blocked
⚠️  Warn: Request to non-configured domain → Standard iOS validation (no pinning)
```

### Cryptography

- **Algorithm**: ES256 (ECDSA with P-256 and SHA-256)
- **Signature Library**: JOSESwift
- **SSL Pinning**: TrustKit
- **Key Format**: SPKI (SubjectPublicKeyInfo) in Base64

## Requirements

- **iOS**: 14.0+
- **macOS**: 10.15+
- **Swift**: 5.9+
- **Xcode**: 15.0+

## Dependencies

This SDK uses battle-tested open-source libraries:

- [**TrustKit**](https://github.com/datatheorem/TrustKit) - SSL certificate pinning (by Data Theorem)
- [**JOSESwift**](https://github.com/airsidemobile/JOSESwift) - JWS signature verification

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  DynamicPinning                      │
│  ┌────────────────────────────────────────────────┐ │
│  │  DynamicPinning.swift (Public API)             │ │
│  └────────────────────────────────────────────────┘ │
│         │                            │               │
│         ▼                            ▼               │
│  ┌──────────────┐           ┌───────────────┐      │
│  │ NetworkService│          │ CryptoService │      │
│  │ (Fetch pins) │          │ (Verify JWS)  │      │
│  └──────────────┘           └───────────────┘      │
│         │                            │               │
│         └────────────┬───────────────┘               │
│                      ▼                               │
│            ┌──────────────────┐                     │
│            │ TrustKitManager  │                     │
│            │ (Configure pins) │                     │
│            └──────────────────┘                     │
│                      │                               │
└──────────────────────┼───────────────────────────────┘
                       ▼
              ┌─────────────────┐
              │ TrustKit (SSL)  │
              └─────────────────┘
                       │
                       ▼
              ┌─────────────────┐
              │  URLSession     │
              └─────────────────┘
```

## FAQ

**Q: Do I need to modify my networking code?**  
A: No. Just replace `URLSession.shared` with `DynamicPinning.session()`.

**Q: What happens if the backend is down?**  
A: Cached pins are used. If no cache exists, connection fails (fail-closed).

**Q: Can I pin multiple domains?**  
A: Yes, pass an array of domains to `initialize()`.

**Q: Does it work with Alamofire/Moya/other networking libraries?**  
A: Yes, if they use URLSession internally. Pass `DynamicPinning.session()` to them.

**Q: How often are pins refreshed?**  
A: On first access and when SSL validation fails. You can also call `refreshPins()` manually.

**Q: What about certificate rotation?**  
A: Enable `includeBackupPins: true` to fetch backup pins for seamless rotation.

## Troubleshooting

### SSL Pinning Fails

```
❌ [DynamicPinning] TrustKit validation failed for: api.example.com
```

**Solutions:**
1. Check that domain is in `ALLOWED_DOMAINS` on server
2. Verify `signingPublicKey` matches server's private key
3. Ensure server is reachable from the device
4. Check logs for JWS verification errors

### Initialization Issues

```
⚠️ [DynamicPinning] Failed to verify pins for example.com: invalidPublicKey
```

**Solutions:**
1. Verify public key format (Base64, no headers/footers)
2. Check that key is ES256 (not Ed25519 or RSA)
3. Ensure server is returning valid JWS tokens

### Enable Debug Logging

Set a symbolic breakpoint on `NSLog` with condition:
```
(BOOL)[$arg1 containsString:@"[DynamicPinning]"]
```

Or check Console.app for logs starting with `[DynamicPinning]`.

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Quick Contribution Guide:**
1. Fork the repo
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make changes and add tests
4. Run tests: `make test`
5. Commit: `git commit -m "feat: add something"`
6. Push and open a Pull Request

## Support

- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/Free-cat/dynapins-ios/issues)
- 💬 **Questions**: [GitHub Discussions](https://github.com/Free-cat/dynapins-ios/discussions)
- 📧 **Security Issues**: security@example.com (private disclosure)

## Related Projects

- [**Dynapins Server**](https://github.com/Free-cat/dynapins-server) - Go backend for serving signed pins
- [**Dynapins Android**](https://github.com/Free-cat/dynapins-android) - Android SDK (coming soon)

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Built with these excellent open-source libraries:
- [TrustKit](https://github.com/datatheorem/TrustKit) by Data Theorem
- [JOSESwift](https://github.com/airsidemobile/JOSESwift) by Airside Mobile

---

<p align="center">
  <strong>Made with ❤️ for secure iOS apps</strong>
</p>

<p align="center">
  <a href="https://github.com/Free-cat">GitHub</a> •
  <a href="https://github.com/Free-cat/dynapins-ios/issues">Issues</a> •
  <a href="https://github.com/Free-cat/dynapins-ios/discussions">Discussions</a>
</p>
