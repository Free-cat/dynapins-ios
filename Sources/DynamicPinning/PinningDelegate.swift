import Foundation
import Security

/// URLSession delegate that handles TLS authentication challenges for dynamic certificate pinning.
@available(iOS 14.0, macOS 10.15, *)
internal final class PinningDelegate: NSObject, URLSessionDelegate {
    
    private let configuration: Configuration
    private let keychainService: KeychainService
    private let cryptoService: CryptoService
    private let networkService: NetworkService
    
    /// Queue for serializing validation operations
    private let validationQueue = DispatchQueue(label: "com.dynapins.sdk.validation", qos: .userInitiated)
    
    /// Creates a new pinning delegate with the specified configuration.
    ///
    /// - Parameter configuration: The SDK configuration containing the public key and service URL
    init(configuration: Configuration) {
        self.configuration = configuration
        self.keychainService = KeychainService()
        self.cryptoService = CryptoService()
        self.networkService = NetworkService(serviceURL: configuration.serviceURL)
        super.init()
    }
    
    /// Handles authentication challenges for URLSession requests.
    ///
    /// This method intercepts TLS challenges to perform certificate pinning validation.
    ///
    /// - Parameters:
    ///   - session: The session containing the task that requested authentication
    ///   - challenge: The authentication challenge
    ///   - completionHandler: A completion handler that your delegate method must call
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle server trust authentication challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            // Not a server trust challenge, use default handling
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        // Get the host being connected to
        let host = challenge.protectionSpace.host
        
        // Perform pinning validation
        validateServerTrust(serverTrust, forHost: host) { isValid in
            if isValid {
                // Certificate is valid, proceed with the connection
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                // Certificate validation failed, cancel the connection
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
    
    /// Emits an observability event if a handler is registered.
    private func emitEvent(_ event: PinningEvent) {
        DynamicPinning.observabilityHandler?(event)
    }
    
    /// Validates the server trust against the pinned fingerprint.
    ///
    /// - Parameters:
    ///   - serverTrust: The server trust to validate
    ///   - host: The hostname being connected to
    ///   - completion: Completion handler called with the validation result
    private func validateServerTrust(
        _ serverTrust: SecTrust,
        forHost host: String,
        completion: @escaping (Bool) -> Void
    ) {
        validationQueue.async { [weak self] in
            guard let self = self else {
                completion(false)
                return
            }
            
            guard let fingerprint = self.obtainFingerprint(forHost: host) else {
                completion(false)
                return
            }
            
            self.performPinValidation(serverTrust: serverTrust, host: host, fingerprint: fingerprint, completion: completion)
        }
    }
    
    /// Obtains a fingerprint for the given host, either from cache or by fetching from the network.
    private func obtainFingerprint(forHost host: String) -> CachedFingerprint? {
        // Try to load from cache
        do {
            if let cached = try keychainService.loadFingerprint(forDomain: host) {
                emitEvent(.cacheHit(domain: host))
                return cached
            }
        } catch {
            NSLog("[DynamicPinning] Keychain error: \(error)")
            emitEvent(.failure(domain: host, reason: .keychainError))
            return nil
        }
        
        // Cache miss - fetch from network
        emitEvent(.cacheMiss(domain: host))
        return fetchAndCacheFingerprint(forHost: host)
    }
    
    /// Fetches a fingerprint from the network, verifies it, and caches it.
    private func fetchAndCacheFingerprint(forHost host: String) -> CachedFingerprint? {
        do {
            let response = try networkService.fetchFingerprintSync()
            
            guard try cryptoService.verifySignatureForPayload(response: response, publicKey: configuration.publicKey) else {
                NSLog("[DynamicPinning] Signature verification failed for domain: \(host)")
                emitEvent(.failure(domain: host, reason: .signatureVerificationFailed))
                return nil
            }
            
            guard matchesDomain(host, pattern: response.domain) else {
                NSLog("[DynamicPinning] Domain mismatch: \(host) does not match \(response.domain)")
                emitEvent(.failure(domain: host, reason: .wildcardMismatch))
                return nil
            }
            
            return cacheFingerprint(response: response, forHost: host)
        } catch {
            NSLog("[DynamicPinning] Failed to fetch or verify fingerprint: \(error)")
            emitEvent(.failure(domain: host, reason: .fingerprintFetchFailed))
            return nil
        }
    }
    
    /// Caches a fingerprint response and returns it as a CachedFingerprint.
    private func cacheFingerprint(response: NetworkService.FingerprintResponse, forHost host: String) -> CachedFingerprint? {
        let expiresAt = Date().addingTimeInterval(TimeInterval(response.ttl))
        
        do {
            try keychainService.saveFingerprint(response.fingerprint, forDomain: host, expiresAt: expiresAt)
            return CachedFingerprint(domain: response.domain, fingerprint: response.fingerprint, expiresAt: expiresAt)
        } catch {
            NSLog("[DynamicPinning] Failed to cache fingerprint: \(error)")
            emitEvent(.failure(domain: host, reason: .keychainError))
            return nil
        }
    }
    
    /// Performs the actual pin validation by comparing server certificate hash with expected fingerprint.
    private func performPinValidation(
        serverTrust: SecTrust,
        host: String,
        fingerprint: CachedFingerprint,
        completion: @escaping (Bool) -> Void
    ) {
        do {
            let serverKeyHash = try cryptoService.hashPublicKey(fromServerTrust: serverTrust)
            let isValid = serverKeyHash.lowercased() == fingerprint.fingerprint.lowercased()
            
            if isValid {
                emitEvent(.success(domain: host))
            } else {
                NSLog("[DynamicPinning] Fingerprint mismatch for \(host)")
                emitEvent(.failure(domain: host, reason: .hashMismatch))
            }
            
            completion(isValid)
        } catch {
            NSLog("[DynamicPinning] Failed to hash server public key: \(error)")
            emitEvent(.failure(domain: host, reason: .certificateProcessingFailed))
            completion(false)
        }
    }
    
    /// Checks if a hostname matches a domain pattern (supports wildcards).
    ///
    /// - Parameters:
    ///   - hostname: The hostname to check (e.g., "api.example.com")
    ///   - pattern: The domain pattern (e.g., "*.example.com" or "api.example.com")
    /// - Returns: `true` if the hostname matches the pattern
    private func matchesDomain(_ hostname: String, pattern: String) -> Bool {
        // Exact match
        if hostname == pattern {
            return true
        }
        
        // Wildcard match (e.g., *.example.com)
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(2)) // Remove "*."
            
            // Check if hostname ends with the suffix
            if hostname.hasSuffix(suffix) {
                // Ensure it's a proper subdomain match (not just a substring match)
                let prefixLength = hostname.count - suffix.count
                if prefixLength > 0 {
                    let prefix = hostname.prefix(prefixLength)
                    // The character before the suffix should be a dot
                    return prefix.hasSuffix(".")
                }
            }
        }
        
        return false
    }
}
