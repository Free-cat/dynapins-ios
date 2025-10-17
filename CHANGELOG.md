# Changelog

All notable changes to the DynamicPinning iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Add support for certificate transparency logs
- Implement pin rotation strategies
- Add performance metrics collection
- Support for custom validation policies

## [0.2.0] - 2024-10-17

### Added
- ✨ **Async Initialization**: Non-blocking SDK setup with completion handlers
- 🔄 **Automatic Pin Refresh**: Smart retry logic with fresh pins on SSL failures
- 🛡️ **Fail-Closed Security**: Strict policy for configured domains without pins
- 🎯 **Explicit URLSessionDelegate**: Custom delegate for precise SSL validation control
- 🌐 **Wildcard Domain Support**: Matches patterns like `*.example.com`
- 🔐 **Domain Validation**: JWS payload domain verification with wildcard matching
- ⚡ **Thread-Safe Operations**: Concurrent pin fetching with proper synchronization
- 🧪 **Comprehensive Testing**: Unit tests, integration tests, and E2E testing suite
- 🐳 **Docker E2E Environment**: Complete testing setup with Dynapins server
- 📦 **CocoaPods Support**: Full podspec configuration for easy integration

### Changed
- 🔄 **Breaking**: `initialize()` now requires completion handler (async)
- 🔄 **Breaking**: `refreshPins()` now requires completion handler (async)
- 🔄 **Breaking**: `SmartURLSession` renamed to `PinningURLSession`
- 🏗️ **Architecture**: Replaced TrustKit swizzling with explicit URLSessionDelegate
- 🔒 **Security**: Enhanced JWS verification with domain validation
- 📱 **Platform**: Minimum iOS 14.0, macOS 11.0 required
- ⚡ **Performance**: Improved concurrent pin fetching with DispatchGroup

### Fixed
- 🐛 **SSL Validation**: Fixed pinning not being enforced due to swizzling issues
- 🐛 **Memory Leaks**: Resolved TrustKit configuration update memory issues
- 🐛 **Race Conditions**: Fixed concurrent pin fetching synchronization
- 🐛 **Domain Matching**: Corrected subdomain SSL validation logic
- 🐛 **Error Handling**: Improved SSL error detection and retry logic

### Security
- 🔒 **JWS Verification**: Added domain validation to prevent cross-domain attacks
- 🔒 **Certificate Validation**: Enhanced chain validation with proper error handling
- 🔒 **Key Security**: Improved secure key storage and validation
- 🔒 **Timing Attacks**: Fixed potential timing vulnerabilities in crypto operations

## [0.0.1] - 2024-10-17

### Added
- Initial release of DynamicPinning iOS SDK
- Core certificate pinning functionality
- ECDSA P-256 signature verification
- SHA-256 certificate hashing
- Thread-safe initialization
- Comprehensive unit test suite
- SwiftLint configuration
- CI/CD workflows (GitHub Actions)
- Full documentation and examples
- SPM distribution support

### Security
- Fail-closed validation (all errors terminate connections)
- Secure key storage and validation
- Cryptographic signature verification for all fingerprints

---

## Versioning Policy

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** version for incompatible API changes
- **MINOR** version for new functionality in a backwards-compatible manner
- **PATCH** version for backwards-compatible bug fixes

### What constitutes a breaking change?

- Removing or renaming public APIs
- Changing method signatures in public APIs
- Changing the behavior of existing APIs in a way that breaks existing integrations
- Increasing minimum iOS version requirement

### What does NOT constitute a breaking change?

- Adding new public APIs
- Deprecating (but not removing) existing APIs
- Internal implementation changes
- Bug fixes that restore documented behavior
- Performance improvements
- Documentation updates

## Release Process

1. Update version in `Package.swift`
2. Update this CHANGELOG.md
3. Create a git tag: `git tag v0.0.1`
4. Push tag: `git push origin v0.0.1`
5. GitHub Actions will automatically:
   - Build XCFramework
   - Create GitHub Release
   - Publish artifacts

## Support Policy

- **Current version**: Full support with security updates and bug fixes
- **Previous minor version**: Security updates only for 6 months
- **Older versions**: No support (upgrade recommended)

---

**Questions or Issues?** Please file an issue on [GitHub](https://github.com/Free-cat/dynapins-ios/issues).

