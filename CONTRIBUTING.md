# Contributing to Dynapins iOS SDK

First off, thanks for taking the time to contribute! 🎉👍

The following is a set of guidelines for contributing to Dynapins iOS SDK. These are mostly guidelines, not rules. Use your best judgment, and feel free to propose changes to this document in a pull request.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Commit Messages](#commit-messages)
- [Testing](#testing)

## Code of Conduct

This project and everyone participating in it is governed by respect and professionalism. Be kind and constructive.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues as you might find that you don't need to create one. When you are creating a bug report, please include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Provide specific examples** (code snippets, URLs, etc.)
- **Describe the behavior you observed and what you expected**
- **Include iOS version, SDK version, Xcode version**
- **Include logs** (sanitize sensitive data)

**Example Bug Report:**

```markdown
### Bug: SSL pinning fails for wildcard domains

**Environment:**
- iOS: 16.0
- SDK: 0.3.0
- Xcode: 15.0

**Steps to Reproduce:**
1. Initialize SDK with `*.example.com`
2. Make request to `api.example.com`
3. Request fails with NSURLErrorCancelled

**Expected Behavior:**
Request should succeed as `api.example.com` matches `*.example.com`

**Actual Behavior:**
Request fails with SSL pinning error

**Logs:**
```
[DynamicPinning] ❌ TrustKit validation failed for: api.example.com
```
```

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. Provide the following:

- **Use a clear and descriptive title**
- **Provide a detailed description of the enhancement**
- **Explain why this enhancement would be useful**
- **Provide code examples** if applicable

### Pull Requests

- Fill in the required template
- Follow the [coding standards](#coding-standards)
- Include tests for new features
- Update documentation as needed
- End all files with a newline

## Development Setup

### Prerequisites

- Xcode 15.0+
- Swift 5.9+
- macOS 14.0+

### Setup

```bash
# 1. Fork and clone
git clone https://github.com/Free-cat/dynapins-ios.git
cd dynapins-ios

# 2. Install dependencies (optional, for prettier test output)
brew install xcbeautify

# 3. Open in Xcode
open Package.swift

# 4. Build
swift build

# 5. Run tests
make test
```

### Project Structure

```
dynapins-ios/
├── Sources/
│   └── DynamicPinning/
│       ├── DynamicPinning.swift        # Public API
│       ├── NetworkService.swift        # Pin fetching
│       ├── CryptoService.swift         # JWS verification
│       ├── TrustKitManager.swift       # TrustKit config
│       ├── TrustKitURLSessionDelegate.swift  # SSL validation
│       └── PinningURLSession.swift     # Retry logic
├── Tests/
│   └── DynamicPinningTests/
│       ├── *Tests.swift                # Unit tests
│       └── TestUtilities/              # Test helpers
├── Makefile                            # Build & test commands
└── docker-compose.e2e.yml              # E2E test environment
```

## Pull Request Process

1. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/my-feature
   # or
   git checkout -b fix/my-bugfix
   ```

2. **Make your changes**:
   - Write clear, concise code
   - Add tests for new features
   - Update documentation

3. **Test your changes**:
   ```bash
   make test              # Unit tests
   make test-all          # All tests
   make e2e-build         # Full E2E
   ```

4. **Commit your changes**:
   ```bash
   git commit -m "feat: add automatic pin refresh"
   ```

5. **Push to your fork**:
   ```bash
   git push origin feature/my-feature
   ```

6. **Open a Pull Request**:
   - Use a clear title
   - Describe what and why
   - Link related issues
   - Add screenshots/videos if relevant

7. **Code Review**:
   - Address review comments
   - Keep PR focused (one feature/fix per PR)
   - Squash commits if requested

## Coding Standards

### Swift Style Guide

Follow Apple's [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/):

- Use `camelCase` for variables and functions
- Use `PascalCase` for types
- Use descriptive names (`fetchPins` not `get`)
- Prefer `let` over `var`
- Use `guard` for early exits
- Avoid force unwrapping (`!`) unless absolutely necessary

### Code Examples

**Good:**

```swift
func fetchPins(for domain: String, completion: @escaping (Result<[String], Error>) -> Void) {
    guard !domain.isEmpty else {
        completion(.failure(NetworkError.invalidDomain))
        return
    }
    
    // Implementation
}
```

**Bad:**

```swift
func get(d: String, c: @escaping (Result<[String], Error>) -> Void) {
    // No validation
    // Short variable names
}
```

### Documentation

- Add documentation comments for public APIs
- Use `///` for single-line docs
- Use `/** ... */` for multi-line docs
- Include examples for complex APIs

```swift
/// Initializes the SDK with the signing public key and domains.
///
/// - Parameters:
///   - signingPublicKey: ES256 public key in Base64 format
///   - pinningServiceURL: URL to fetch pins from
///   - domains: List of domains to pin
///   - completion: Called when initialization completes
public static func initialize(
    signingPublicKey: String,
    pinningServiceURL: URL,
    domains: [String],
    completion: @escaping (Int, Int) -> Void
) {
    // Implementation
}
```

### Logging

Use `NSLog` with `[DynamicPinning]` prefix:

```swift
NSLog("[DynamicPinning] ✅ Configured pinning for: \(domain)")
NSLog("[DynamicPinning] ❌ Failed to verify JWS: \(error)")
NSLog("[DynamicPinning] 🔄 Retrying request with fresh pins...")
```

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style (formatting, no logic change)
- `refactor`: Code refactoring
- `test`: Adding/updating tests
- `chore`: Build process, tooling

### Examples

```
feat: add automatic pin refresh on SSL failure

Implements retry logic that automatically refreshes pins when
an SSL validation error occurs. Limited to one retry per request
to prevent infinite loops.

Closes #42
```

```
fix: race condition in TrustKitManager

Thread-safe access to currentConfiguration using dispatch queue
with barrier flags.
```

```
docs: add troubleshooting section to README

Includes common SSL pinning errors and solutions.
```

### Scope (Optional)

- `crypto`: CryptoService
- `network`: NetworkService
- `trustkit`: TrustKit integration
- `retry`: Retry logic
- `tests`: Test-related changes

## Testing

### Writing Tests

- Write tests for all new features
- Aim for high code coverage (>80%)
- Use descriptive test names
- Test happy path and edge cases

**Test Naming:**

```swift
func testFetchPinsSuccess() { }
func testFetchPinsWithInvalidURL() { }
func testFetchPinsNetworkError() { }
```

### Test Structure

```swift
func testFeatureName() {
    // Given
    let input = "test"
    
    // When
    let result = feature(input)
    
    // Then
    XCTAssertEqual(result, expectedOutput)
}
```

### Running Tests

```bash
# Unit tests only
make test

# Integration tests
make test-integration

# All tests
make test-all

# E2E with Docker
make e2e-build

# Specific test class
swift test --filter CryptoServiceTests

# Specific test method
swift test --filter CryptoServiceTests/testVerifyValidJWS
```

### Test Utilities

Use provided test helpers:

```swift
// Generate real JWS tokens
let keyPair = JWSTestHelper.generateKeyPair()
let jws = try JWSTestHelper.createSignedFingerprint(
    domain: "example.com",
    pins: ["pin1", "pin2"],
    privateKey: keyPair.privateKey
)

// Fixed time for deterministic tests
let clock = FixedClock.at(year: 2024, month: 1, day: 15)
let service = CryptoService(currentTimestamp: clock.now)
```

## Questions?

Feel free to open a [Discussion](https://github.com/Free-cat/dynapins-ios/discussions) if you have questions!

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing! 🙏
