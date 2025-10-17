import Foundation

/// The main entry point for the DynamicPinning SDK.
///
/// This class provides the public API for initializing the SDK and creating
/// preconfigured URLSession instances with automatic certificate pinning.
public final class DynamicPinning {
    
    // MARK: - Shared State
    
    /// Thread-safe queue for accessing shared state
    private static let queue = DispatchQueue(label: "com.dynapins.sdk.configuration", attributes: .concurrent)
    
    /// Shared configuration instance (thread-safe)
    private static var _configuration: Configuration?
    
    /// Indicates whether the SDK has been initialized
    private static var isInitialized: Bool {
        return queue.sync { _configuration != nil }
    }
    
    /// Retrieves the current configuration (thread-safe)
    internal static var configuration: Configuration? {
        return queue.sync { _configuration }
    }
    
    /// Optional observability handler for monitoring pinning events
    private static var _observabilityHandler: ((PinningEvent) -> Void)?
    
    /// Retrieves the current observability handler (thread-safe)
    internal static var observabilityHandler: ((PinningEvent) -> Void)? {
        return queue.sync { _observabilityHandler }
    }
    
    // MARK: - Public API
    
    /// Initializes the DynamicPinning SDK with the required configuration.
    ///
    /// This method must be called once before using any other SDK features.
    /// Calling this method multiple times will result in a crash in DEBUG builds
    /// and a warning log in RELEASE builds.
    ///
    /// - Parameters:
    ///   - publicKey: The Ed25519 public key as a Base64-encoded string
    ///   - serviceURL: The URL of the Dynapins fingerprint service
    ///
    /// - Warning: This method must be called exactly once. Multiple calls will cause
    ///            a crash in DEBUG mode or be ignored with a warning in RELEASE mode.
    public static func initialize(publicKey: String, serviceURL: URL) {
        queue.sync(flags: .barrier) {
            #if DEBUG
            // In DEBUG builds, crash if already initialized
            if _configuration != nil {
                preconditionFailure("DynamicPinning.initialize() called more than once. The SDK can only be initialized once per app lifecycle.")
            }
            #else
            // In RELEASE builds, log and ignore
            if _configuration != nil {
                NSLog("[DynamicPinning] WARNING: initialize() called more than once. Ignoring subsequent call.")
                return
            }
            #endif
            
            _configuration = Configuration(publicKey: publicKey, serviceURL: serviceURL)
        }
    }
    
    /// Returns a preconfigured URLSession instance with automatic certificate pinning.
    ///
    /// The returned session intercepts TLS authentication challenges to perform
    /// dynamic certificate pinning based on fingerprints fetched from the configured service.
    ///
    /// - Returns: A configured URLSession instance
    ///
    /// - Precondition: The SDK must be initialized before calling this method.
    ///                 Call `initialize(publicKey:serviceURL:)` first.
    @available(iOS 14.0, macOS 10.15, *)
    public static func session() -> URLSession {
        guard let config = configuration else {
            preconditionFailure("DynamicPinning.session() called before initialize(). You must call initialize(publicKey:serviceURL:) first.")
        }
        
        let delegate = PinningDelegate(configuration: config)
        let sessionConfig = URLSessionConfiguration.default
        
        return URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
    }
    
    /// Sets an optional observability handler to monitor pinning events.
    ///
    /// Use this to integrate with your logging or telemetry systems. The handler
    /// is called on a background queue, so dispatch to main queue if needed for UI updates.
    ///
    /// - Parameter handler: Closure called with pinning events, or `nil` to disable
    ///
    /// # Example
    ///
    /// ```swift
    /// DynamicPinning.setObservabilityHandler { event in
    ///     switch event {
    ///     case .success(let domain):
    ///         print("✅ Pinning succeeded for \(domain)")
    ///     case .failure(let domain, let reason):
    ///         print("❌ Pinning failed for \(domain): \(reason)")
    ///     case .cacheHit(let domain):
    ///         print("💾 Using cached fingerprint for \(domain)")
    ///     case .cacheMiss(let domain):
    ///         print("🌐 Fetching fingerprint for \(domain)")
    ///     }
    /// }
    /// ```
    public static func setObservabilityHandler(_ handler: ((PinningEvent) -> Void)?) {
        queue.sync(flags: .barrier) {
            _observabilityHandler = handler
        }
    }
    
    // Prevent instantiation
    private init() {}
    
    // MARK: - Testing Support
    
    #if DEBUG
    /// Resets the SDK state for testing purposes only.
    ///
    /// - Warning: This method is only available in DEBUG builds and should only be used in tests.
    internal static func resetForTesting() {
        queue.sync(flags: .barrier) {
            _configuration = nil
        }
    }
    #endif
}

