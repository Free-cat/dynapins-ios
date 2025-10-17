# Changelog

All notable changes to the DynamicPinning iOS SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of DynamicPinning iOS SDK
- Core certificate pinning functionality
- Ed25519 signature verification
- SHA-256 certificate hashing
- iOS Keychain caching with TTL support
- Wildcard domain matching (*.example.com)
- Thread-safe initialization
- Observability hooks for monitoring pinning events
- Comprehensive unit test suite
- SwiftLint configuration
- CI/CD workflows (GitHub Actions)
- XCFramework build support

### Security
- Fail-closed validation (all errors terminate connections)
- No external dependencies (only Apple frameworks)
- Secure Keychain storage for cached fingerprints
- Cryptographic signature verification for all fingerprints

## [1.0.0] - TBD

### Added
- Initial public release
- Full documentation and examples
- SPM distribution support

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
3. Create a git tag: `git tag v1.0.0`
4. Push tag: `git push origin v1.0.0`
5. GitHub Actions will automatically:
   - Build XCFramework
   - Create GitHub Release
   - Publish artifacts

## Support Policy

- **Current version**: Full support with security updates and bug fixes
- **Previous minor version**: Security updates only for 6 months
- **Older versions**: No support (upgrade recommended)

---

**Questions or Issues?** Please file an issue on [GitHub](https://github.com/your-org/dynapins-ios/issues).

