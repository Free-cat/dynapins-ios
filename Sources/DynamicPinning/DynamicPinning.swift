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
    
    /// Shared URLSession delegate instance (thread-safe)
    private static var _sessionDelegate: TrustKitURLSessionDelegate?
    
    /// Indicates whether the SDK has been initialized
    private static var isInitialized: Bool {
        return queue.sync { _configuration != nil }
    }
    
    /// Retrieves the current configuration (thread-safe)
    internal static var configuration: Configuration? {
        return queue.sync { _configuration }
    }
    
    /// Retrieves the session delegate (thread-safe)
    private static var sessionDelegate: TrustKitURLSessionDelegate? {
        return queue.sync { _sessionDelegate }
    }
    
    // MARK: - Public API
    
    /// Initializes the DynamicPinning SDK with the required configuration.
    ///
    /// This method must be called once before using any other SDK features.
    /// It will fetch pins for all specified domains asynchronously and configure TrustKit for SSL pinning.
    ///
    /// **Important**: This method is asynchronous and will not block the calling thread.
    /// Use the completion handler to know when initialization is complete.
    ///
    /// Calling this method multiple times will result in a crash in DEBUG builds
    /// and a warning log in RELEASE builds.
    ///
    /// - Parameters:
    ///   - signingPublicKey: The ECDSA P-256 public key as a Base64-encoded string (SPKI format) used to verify JWS tokens
    ///   - pinningServiceURL: The URL of the Dynapins fingerprint service
    ///   - domains: Array of domains to pin (e.g., ["api.example.com", "cdn.example.com"])
    ///   - includeBackupPins: If `true`, the SDK will request both primary and backup (intermediate) pins from the server. Defaults to `false`.
    ///   - completion: Optional completion handler called when initialization finishes (success count, failure count)
    ///
    /// - Warning: This method must be called exactly once. Multiple calls will cause
    ///            a crash in DEBUG mode or be ignored with a warning in RELEASE mode.
    @available(iOS 14.0, macOS 10.15, *)
    public static func initialize(
        signingPublicKey: String,
        pinningServiceURL: URL,
        domains: [String],
        includeBackupPins: Bool = false,
        completion: ((Int, Int) -> Void)? = nil
    ) {
        // Check and set configuration
        var shouldProceed = false
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
                completion?(0, 0)
                return
            }
            #endif
            
            _configuration = Configuration(
                signingPublicKey: signingPublicKey,
                pinningServiceURL: pinningServiceURL,
                domains: domains,
                includeBackupPins: includeBackupPins
            )
            
            // Create delegate with configured domains
            _sessionDelegate = TrustKitURLSessionDelegate(configuredDomains: domains)
            
            shouldProceed = true
        }
        
        guard shouldProceed else { return }
        
        // Initialize TrustKit and fetch pins asynchronously
        TrustKitManager.shared.initialize()
        
        DispatchQueue.global(qos: .userInitiated).async {
            fetchPinsForAllDomains(completion: completion)
        }
    }
    
    /// Refreshes pins for all configured domains.
    ///
    /// This method fetches fresh pins from the server and updates TrustKit configuration.
    /// Use this when you need to handle certificate rotation without restarting the app.
    ///
    /// **Important**: This allows the app to adapt to certificate changes dynamically,
    /// which is the core purpose of this SDK. This method is asynchronous.
    ///
    /// **Thread Safety**: This method is thread-safe and non-blocking.
    ///
    /// # Example
    ///
    /// ```swift
    /// // Refresh pins when app becomes active
    /// NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification) {
    ///     DynamicPinning.refreshPins { success, failures in
    ///         print("Refreshed: \(success) succeeded, \(failures) failed")
    ///     }
    /// }
    /// ```
    @available(iOS 14.0, macOS 10.15, *)
    public static func refreshPins(completion: ((Int, Int) -> Void)? = nil) {
        guard isInitialized else {
            NSLog("[DynamicPinning] Cannot refresh pins - SDK not initialized")
            completion?(0, 0)
            return
        }
        
        DispatchQueue.global(qos: .utility).async {
            fetchPinsForAllDomains(completion: completion)
        }
    }
    
    /// Fetches pins for all configured domains and updates TrustKit.
    /// This is called during initialization and manual refresh.
    @available(iOS 14.0, macOS 10.15, *)
    private static func fetchPinsForAllDomains(completion: ((Int, Int) -> Void)? = nil) {
        guard let config = configuration else {
            NSLog("[DynamicPinning] Cannot fetch pins - SDK not initialized")
            completion?(0, 0)
            return
        }

        NSLog("[DynamicPinning] Fetching pins for \(config.domains.count) domain(s)...")

        let networkService = NetworkService(serviceURL: config.pinningServiceURL)
        let cryptoService = CryptoService()
        
        var successCount = 0
        var failureCount = 0
        let group = DispatchGroup()

        for domain in config.domains {
            group.enter()
            
            networkService.fetchFingerprint(forDomain: domain, includeBackupPins: config.includeBackupPins) { result in
                defer { group.leave() }
                
                switch result {
                case .success(let jwsToken):
                    do {
                        // Verify JWS and extract payload with domain validation
                        let payload = try cryptoService.verifyJWS(
                            jwsString: jwsToken,
                            publicKey: config.signingPublicKey,
                            expectedDomain: domain
                        )

                        // Update TrustKit with pins for this domain
                        TrustKitManager.shared.updatePins(forDomain: domain, pins: payload.pins)
                        
                        successCount += 1
                        NSLog("[DynamicPinning] ✅ Configured pinning for: \(domain)")
                    } catch {
                        failureCount += 1
                        NSLog("[DynamicPinning] ⚠️ Failed to verify pins for \(domain): \(error)")
                    }
                    
                case .failure(let error):
                    failureCount += 1
                    NSLog("[DynamicPinning] ⚠️ Failed to fetch pins for \(domain): \(error)")
                }
            }
        }
        
        group.notify(queue: .main) {
            NSLog("[DynamicPinning] Pin refresh complete: \(successCount) succeeded, \(failureCount) failed")
            completion?(successCount, failureCount)
        }
    }
    
    /// Returns a URLSession with automatic pin refresh on SSL errors.
    ///
    /// This session automatically handles certificate rotation by:
    /// 1. Using TrustKit to validate SSL certificates against configured pins
    /// 2. Detecting SSL validation failures (e.g., when certificates are rotated)
    /// 3. Fetching fresh pins from the server and retrying
    ///
    /// This enables **zero-downtime certificate rotation** without app restart.
    ///
    /// - Returns: A PinningURLSession configured with TrustKit-based SSL pinning
    ///
    /// - Precondition: The SDK must be initialized before calling this method.
    ///                 Call `initialize(publicKey:serviceURL:domains:)` first.
    @available(iOS 14.0, macOS 10.15, *)
    public static func session() -> PinningURLSession {
        guard let delegate = sessionDelegate else {
            preconditionFailure("DynamicPinning.session() called before initialize(). You must call initialize(publicKey:serviceURL:domains:) first.")
        }
        
        // Create URLSession with our TrustKit delegate for explicit SSL validation
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        
        let urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        // Return session that auto-retries with fresh pins on SSL errors
        return PinningURLSession(session: urlSession)
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
            _sessionDelegate = nil
        }
    }
    #endif
}
