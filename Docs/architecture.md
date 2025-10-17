# Architecture Overview

This document describes the internal architecture of the DynamicPinning iOS SDK.

## 📐 High-Level Design

The SDK follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────┐
│                  Public API Layer                   │
│              (DynamicPinning class)                 │
└─────────────────┬───────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────┐
│              Delegation Layer                       │
│          (PinningDelegate class)                    │
└─┬──────────────┬──────────────┬─────────────────────┘
  │              │              │
  │ Cache        │ Network      │ Crypto
  │              │              │
┌─▼────────┐ ┌──▼────────┐ ┌───▼──────────┐
│ Keychain │ │  Network  │ │    Crypto    │
│ Service  │ │  Service  │ │   Service    │
└──────────┘ └───────────┘ └──────────────┘
```

## 🏗️ Component Breakdown

### 1. DynamicPinning (Public API)

**Responsibility**: Provide simple, static API for SDK usage

**Key Methods**:
- `initialize(publicKey:serviceURL:)` - Configure the SDK
- `session()` - Return configured URLSession
- `resetForTesting()` - Debug-only state reset

**Design Decisions**:
- **Static API**: Simplifies integration (no instance management)
- **Thread-Safe**: Uses `DispatchQueue` with barrier for configuration access
- **Fail-Fast**: `preconditionFailure` in DEBUG, log warnings in RELEASE

### 2. PinningDelegate (Orchestration)

**Responsibility**: Intercept TLS challenges and orchestrate validation

**Key Methods**:
- `urlSession(_:didReceive:completionHandler:)` - Handle authentication challenges
- `validateServerTrust(_:forHost:completion:)` - Perform pinning validation
- `matchesDomain(_:pattern:)` - Wildcard domain matching

**Flow**:
```swift
1. Intercept TLS challenge
2. Check cache for fingerprint
3. If not cached:
   a. Fetch from service
   b. Verify signature
   c. Check domain match
   d. Cache if valid
4. Hash server's public key
5. Compare with cached fingerprint
6. Accept or reject connection
```

**Design Decisions**:
- **Async Validation**: Uses background queue to avoid blocking
- **Fail-Closed**: Any error results in `.cancelAuthenticationChallenge`
- **No Retries**: Single attempt per request (service should be reliable)

### 3. KeychainService (Secure Storage)

**Responsibility**: Securely store and retrieve fingerprints

**Data Model**:
```swift
struct CachedFingerprint {
    let domain: String
    let fingerprint: String
    let expiresAt: Date
}
```

**Key Operations**:
- `saveFingerprint(_:forDomain:expiresAt:)` - Store with expiration
- `loadFingerprint(forDomain:)` - Retrieve if not expired
- `deleteFingerprint(forDomain:)` - Remove from Keychain
- `clearAll()` - Delete all cached fingerprints

**Keychain Attributes**:
- `kSecClass`: `kSecClassGenericPassword`
- `kSecAttrService`: `"com.dynapins.sdk.fingerprints"`
- `kSecAttrAccount`: domain name (unique key)
- `kSecAttrAccessible`: `kSecAttrAccessibleAfterFirstUnlock`

**Design Decisions**:
- **Per-Domain Storage**: Each domain is a separate Keychain item
- **JSON Encoding**: Uses `JSONEncoder` with ISO8601 dates
- **Auto-Expiration**: Expired items are deleted on read
- **Overwrite on Save**: Existing items are replaced atomically

### 4. CryptoService (Cryptographic Operations)

**Responsibility**: Signature verification and hashing

**Key Operations**:
- `verifySignature(message:signature:publicKey:)` - Ed25519 verification
- `hashPublicKey(fromServerTrust:)` - Extract and hash certificate key
- `sha256Hash(of:)` - Generic SHA-256 hashing

**Cryptographic Primitives**:
- **Ed25519**: Via `CryptoKit.Curve25519.Signing`
- **SHA-256**: Via `CryptoKit.SHA256`
- **Key Extraction**: Via `Security.SecCertificateCopyKey`

**Design Decisions**:
- **No External Crypto**: Apple's CryptoKit is sufficient and trusted
- **Hex Output**: Hashes are lowercase hex strings for consistency
- **Error Propagation**: Throws `CryptoError` for clear failure reasons

### 5. NetworkService (HTTP Communication)

**Responsibility**: Fetch signed fingerprints from service

**Response Model**:
```swift
struct FingerprintResponse {
    let domain: String
    let fingerprint: String
    let signature: String
    let ttl: Int
}
```

**Key Operations**:
- `fetchFingerprint(completion:)` - Async fetch
- `fetchFingerprintSync()` - Blocking fetch (used during TLS challenge)

**Design Decisions**:
- **Separate URLSession**: Uses default session to avoid circular pinning
- **10s Timeout**: Fast failure for unavailable service
- **Synchronous Mode**: TLS challenges require blocking call
- **No Retries**: Service should be reliable; retries add latency

## 🔄 Validation Flow (Detailed)

### Happy Path

```
1. App makes HTTPS request using DynamicPinning.session()
2. Server presents certificate
3. PinningDelegate.urlSession(_:didReceive:) called
4. Check cache:
   - KeychainService.loadFingerprint(forDomain:)
   - If found and not expired → skip to step 10
5. Fetch fingerprint:
   - NetworkService.fetchFingerprintSync()
   - Parse JSON response
6. Verify signature:
   - CryptoService.verifySignature(message:signature:publicKey:)
   - If invalid → FAIL (step 14)
7. Check domain match:
   - matchesDomain(host, pattern: response.domain)
   - If mismatch → FAIL (step 14)
8. Cache fingerprint:
   - Calculate expiresAt = now + TTL
   - KeychainService.saveFingerprint(_:forDomain:expiresAt:)
9. Update cachedFingerprint variable
10. Hash server's certificate:
    - CryptoService.hashPublicKey(fromServerTrust:)
11. Compare hashes:
    - serverKeyHash == cachedFingerprint.fingerprint
12. If match:
    - completionHandler(.useCredential, credential)
    - ✅ Connection proceeds
13. If mismatch → FAIL (step 14)
14. FAIL:
    - completionHandler(.cancelAuthenticationChallenge, nil)
    - ❌ Connection terminated
```

### Error Scenarios

| Error Type | Step | Action |
|-----------|------|--------|
| Keychain read error | 4 | Fail immediately |
| Network fetch fails | 5 | Fail immediately |
| Signature invalid | 6 | Fail immediately |
| Domain mismatch | 7 | Fail immediately |
| Keychain save error | 8 | Continue with validation (no cache) |
| Hash extraction fails | 10 | Fail immediately |
| Hash mismatch | 11 | Fail immediately |

All errors are logged to console for debugging.

## 🔒 Security Considerations

### Fail-Closed Design

The SDK never "falls back" to default validation. Any error in the validation flow results in connection termination:

```swift
// Good: Explicit handling
guard condition else {
    completion(false)  // Fail closed
    return
}

// Bad: Default success
if condition {
    completion(false)
} else {
    completion(true)  // Dangerous!
}
```

### Signature Verification

The signature verification flow ensures:
1. **Authenticity**: Only fingerprints signed by your private key are accepted
2. **Integrity**: Any tampering invalidates the signature
3. **Freshness**: Combined with TTL, prevents replay attacks

### Keychain Security

Fingerprints are stored with `kSecAttrAccessibleAfterFirstUnlock`:
- **Encrypted at rest** by iOS Keychain
- **Accessible after first unlock** (survives background app launch)
- **Not accessible before first unlock** (protects against cold boot attacks)
- **Per-app sandboxing** (not accessible to other apps)

### No Certificate Pinning of Dynapins Service

The service URL (`/cert-fingerprint`) uses a **separate URLSession** without pinning:
- **Why**: Avoids circular dependency (can't pin the service that provides pins)
- **Safe**: Signature verification ensures authenticity regardless of transport security
- **Best Practice**: Use HTTPS + valid certificate for service URL

## 🧵 Thread Safety

### Configuration Access

```swift
// Reader/Writer pattern with barriers
private static let queue = DispatchQueue(
    label: "com.dynapins.sdk.configuration",
    attributes: .concurrent
)

// Write (exclusive)
queue.sync(flags: .barrier) {
    _configuration = newConfig
}

// Read (concurrent)
queue.sync {
    return _configuration
}
```

### Validation Queue

```swift
private let validationQueue = DispatchQueue(
    label: "com.dynapins.sdk.validation",
    qos: .userInitiated
)
```

All validation work happens on this serial queue to:
- Prevent race conditions
- Serialize Keychain access
- Avoid blocking main thread

## 📊 Performance Optimizations

### Caching Strategy

- **Cache Key**: Domain name (exact match only)
- **TTL**: Configurable via service response
- **Expiration**: Lazy deletion on read (no background timer)

### Network Optimization

- **Single Request**: One fetch per domain per TTL period
- **Synchronous Fetch**: Uses semaphore to avoid callback complexity
- **10s Timeout**: Fast failure for unreachable service

### Memory Management

- **No Static State**: Only configuration is cached
- **Weak Delegates**: PinningDelegate uses `[weak self]` in closures
- **Immediate Cleanup**: No persistent background tasks

## 🏗️ Extensibility

### Adding Observability (Phase 7)

The architecture supports optional observability:

```swift
// In DynamicPinning
static var observabilityHandler: ((PinningEvent) -> Void)?

// In PinningDelegate
func emitEvent(_ event: PinningEvent) {
    DynamicPinning.observabilityHandler?(event)
}
```

Events could include:
- `success(domain:)`
- `failure(domain:, reason:)`
- `cacheHit(domain:)`
- `cacheMiss(domain:)`

### Future Enhancements

Potential additions without breaking changes:
- **Custom Cache TTL Override**: Allow app to specify minimum/maximum TTL
- **Metrics Collection**: Expose cache hit rate, validation times
- **Multiple Service URLs**: Fallback to secondary service
- **Background Refresh**: Proactively refresh expiring fingerprints

## 🧪 Testing Strategy

### Unit Tests

- **InitializationTests**: Configuration management, thread safety
- **KeychainServiceTests**: CRUD operations, expiration, isolation
- **CryptoServiceTests**: Hashing, signature verification
- **NetworkServiceTests**: JSON decoding, error handling

### Integration Tests

- **PinningIntegrationTests**: End-to-end validation flow
- Requires: Test server with valid certificate and signed fingerprint

### Test Helpers

```swift
#if DEBUG
static func resetForTesting() {
    // Reset internal state between tests
}
#endif
```

## 📚 Code Organization

```
Sources/DynamicPinning/
├── DynamicPinning.swift      # Public API
├── Configuration.swift        # Config model
├── PinningDelegate.swift      # TLS challenge handler
├── KeychainService.swift      # Secure storage
├── CryptoService.swift        # Crypto operations
└── NetworkService.swift       # HTTP client

Tests/DynamicPinningTests/
├── InitializationTests.swift
├── KeychainServiceTests.swift
├── CryptoServiceTests.swift
├── NetworkServiceTests.swift
└── PinningIntegrationTests.swift
```

## 🔍 Debugging

### Logging

All failures are logged via `NSLog`:

```swift
NSLog("[DynamicPinning] Signature verification failed for domain: \(host)")
NSLog("[DynamicPinning] Keychain error: \(error)")
NSLog("[DynamicPinning] Fingerprint mismatch for \(host)")
```

### Debugging Tips

1. **Enable Network Logging**: Use Charles/Proxyman to verify service responses
2. **Keychain Inspection**: Use `security` command-line tool on macOS
3. **Certificate Analysis**: Export server certificate and verify hash manually
4. **Test Service**: Use `curl` to verify service endpoint returns valid JSON

## 🎯 Design Principles

1. **Simplicity**: Minimal public API surface
2. **Security**: Fail-closed by default
3. **Reliability**: No external dependencies
4. **Performance**: Cache-first strategy
5. **Debuggability**: Clear error messages
6. **Testability**: Clean interfaces, dependency injection
7. **Maintainability**: Small, focused classes

---

**Last Updated**: 2025-10-17

