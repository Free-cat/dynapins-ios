# Dynapins iOS

iOS SDK for dynamic SSL/TLS certificate pinning with URLSession integration.

## 🚧 Coming Soon

This project is under development.

## 📋 Planned Features

- **URLSession Integration**
  - Custom URLSessionDelegate
  - Automatic certificate validation
  - Transparent proxy support
  
- **Certificate Validation**
  - Public key pinning
  - Certificate fingerprint verification
  - Ed25519 signature validation
  
- **Caching & Performance**
  - Local certificate cache
  - Automatic updates from server
  - Offline support
  
- **Easy Integration**
  - Swift Package Manager
  - CocoaPods support
  - Minimal configuration

## 🎯 Planned API

```swift
import Dynapins

// Initialize
let dynapins = Dynapins(
    serverURL: "https://api.example.com",
    publicKey: "your-ed25519-public-key"
)

// Configure URLSession
let session = dynapins.createURLSession()

// Make requests - pinning is automatic
let task = session.dataTask(with: url) { data, response, error in
    // Handle response
}
task.resume()

// Or use with custom URLSession
let config = URLSessionConfiguration.default
dynapins.configure(session: config)
```

### Advanced Usage

```swift
// Manual certificate validation
dynapins.validateCertificate(
    domain: "secure.example.com"
) { result in
    switch result {
    case .success(let certificate):
        print("Certificate valid: \(certificate)")
    case .failure(let error):
        print("Validation failed: \(error)")
    }
}

// Check cache status
if let cached = dynapins.getCachedCertificate(for: "example.com") {
    print("Using cached certificate")
}

// Force refresh
dynapins.refreshCertificates { result in
    print("Certificates updated")
}
```

## 🔧 Requirements

- iOS 13.0+
- Swift 5.5+
- Xcode 13.0+

## 📦 Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/freecats/dynapins-ios.git", from: "1.0.0")
]
```

### CocoaPods

```ruby
pod 'Dynapins', '~> 1.0'
```

## 🔗 Related Projects

- [Dynapins Server](../dynapins-server) - Backend HTTP API
- [Dynapins Android](../dynapins-android) - Android SDK

## 📞 Contributing

Interested in contributing? Check out our [contribution guidelines](../dynapins-server/CONTRIBUTING.md).

## 📄 License

MIT License - see [LICENSE](../dynapins-server/LICENSE) for details.
