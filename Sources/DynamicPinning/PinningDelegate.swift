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
            
            // Step 1: Check for cached fingerprint
            var cachedFingerprint: CachedFingerprint?
            
            do {
                cachedFingerprint = try self.keychainService.loadFingerprint(forDomain: host)
            } catch {
                // Keychain error, fail closed
                NSLog("[DynamicPinning] Keychain error: \(error)")
                self.emitEvent(.failure(domain: host, reason: .keychainError))
                completion(false)
                return
            }
            
            // Step 2: If not cached, fetch from service
            if cachedFingerprint == nil {
                self.emitEvent(.cacheMiss(domain: host))
                
                do {
                    let response = try self.networkService.fetchFingerprintSync()
                    
                    // Step 3: Verify signature
                    // The signature covers the entire payload, not just the fingerprint
                    let isSignatureValid = try self.cryptoService.verifySignatureForPayload(
                        response: response,
                        publicKey: self.configuration.publicKey
                    )
                    
                    guard isSignatureValid else {
                        NSLog("[DynamicPinning] Signature verification failed for domain: \(host)")
                        self.emitEvent(.failure(domain: host, reason: .signatureVerificationFailed))
                        completion(false)
                        return
                    }
                    
                    // Step 4: Check wildcard domain matching
                    guard self.matchesDomain(host, pattern: response.domain) else {
                        NSLog("[DynamicPinning] Domain mismatch: \(host) does not match \(response.domain)")
                        self.emitEvent(.failure(domain: host, reason: .wildcardMismatch))
                        completion(false)
                        return
                    }
                    
                    // Step 5: Cache the verified fingerprint
                    let expiresAt = Date().addingTimeInterval(TimeInterval(response.ttl))
                    try self.keychainService.saveFingerprint(
                        response.fingerprint,
                        forDomain: host,
                        expiresAt: expiresAt
                    )
                    
                    cachedFingerprint = CachedFingerprint(
                        domain: response.domain,
                        fingerprint: response.fingerprint,
                        expiresAt: expiresAt
                    )
                } catch {
                    NSLog("[DynamicPinning] Failed to fetch or verify fingerprint: \(error)")
                    self.emitEvent(.failure(domain: host, reason: .fingerprintFetchFailed))
                    completion(false)
                    return
                }
            } else {
                self.emitEvent(.cacheHit(domain: host))
            }
            
            // Step 6: Extract and hash server's public key
            guard let fingerprint = cachedFingerprint else {
                completion(false)
                return
            }
            
            let serverKeyHash: String
            do {
                serverKeyHash = try self.cryptoService.hashPublicKey(fromServerTrust: serverTrust)
            } catch {
                NSLog("[DynamicPinning] Failed to hash server public key: \(error)")
                self.emitEvent(.failure(domain: host, reason: .certificateProcessingFailed))
                completion(false)
                return
            }
            
            // Step 7: Compare hash with cached fingerprint
            let isValid = serverKeyHash.lowercased() == fingerprint.fingerprint.lowercased()
            
            if isValid {
                self.emitEvent(.success(domain: host))
            } else {
                NSLog("[DynamicPinning] Fingerprint mismatch for \(host)")
                self.emitEvent(.failure(domain: host, reason: .hashMismatch))
            }
            
            completion(isValid)
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
