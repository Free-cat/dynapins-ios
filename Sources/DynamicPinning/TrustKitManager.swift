import Foundation
import TrustKit

/// Manages TrustKit configuration for dynamic SSL pinning
/// Integrates with our JWS-based pin distribution system
class TrustKitManager {
    
    static let shared = TrustKitManager()
    
    private var currentConfiguration: [String: Any]?
    private var isInitialized = false
    private let queue = DispatchQueue(label: "com.dynapins.trustkit", attributes: .concurrent)
    
    private init() {}
    
    /// Initialize TrustKit - does nothing now, will be initialized when first pins are set
    func initialize() {
        // TrustKit will be initialized lazily when first pins are added
        // This is because TrustKit doesn't allow empty pinned domains
        NSLog("[DynamicPinning] TrustKit manager ready (lazy initialization)")
    }
    
    /// Update TrustKit configuration with new pins for a domain
    /// - Parameters:
    ///   - domain: The domain to pin
    ///   - pins: Array of base64-encoded SHA256 SPKI hashes
    func updatePins(forDomain domain: String, pins: [String]) {
        guard !pins.isEmpty else {
            NSLog("[DynamicPinning] No pins provided for domain: \(domain)")
            return
        }
        
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            // TrustKit configuration for this domain
            // We use includeSubdomains: false to be explicit about what we're pinning
            let domainConfig: [String: Any] = [
                kTSKPublicKeyHashes: pins,
                kTSKIncludeSubdomains: false,
                kTSKEnforcePinning: true,
                kTSKReportUris: [] as [String]  // No reporting for now
            ]
            
            // Get current pinned domains
            var pinnedDomains = self.currentConfiguration?[kTSKPinnedDomains] as? [String: Any] ?? [:]
            
            // Update domain configuration
            pinnedDomains[domain] = domainConfig
            
            // Update TrustKit configuration
            // Note: We explicitly disable swizzling and use our own URLSessionDelegate
            let newConfig: [String: Any] = [
                kTSKSwizzleNetworkDelegates: false,
                kTSKPinnedDomains: pinnedDomains
            ]
            
            self.currentConfiguration = newConfig
            
            // Initialize TrustKit if this is the first time
            if !self.isInitialized {
                TrustKit.initSharedInstance(withConfiguration: newConfig)
                self.isInitialized = true
                NSLog("[DynamicPinning] TrustKit initialized with \(pins.count) pins for domain: \(domain)")
            } else {
                // Note: TrustKit doesn't support runtime configuration updates
                // We need to reinitialize it (this is a limitation of TrustKit)
                TrustKit.initSharedInstance(withConfiguration: newConfig)
                NSLog("[DynamicPinning] TrustKit updated with \(pins.count) pins for domain: \(domain)")
            }
            
            NSLog("[DynamicPinning]   First pin: \(pins[0])")
            if pins.count > 1 {
                NSLog("[DynamicPinning]   Backup pins: \(pins.count - 1)")
            }
        }
    }
    
    /// Get TrustKit instance for manual URL session validation
    var trustKit: TrustKit? {
        return TrustKit.sharedInstance()
    }
    
    /// Validates a server trust using TrustKit
    /// - Parameters:
    ///   - serverTrust: The server trust to validate
    ///   - domain: The domain being validated
    /// - Returns: True if the trust is valid according to TrustKit's pinning policy
    func validateServerTrust(_ serverTrust: SecTrust, forDomain domain: String) -> Bool {
        let trustKit = TrustKit.sharedInstance()
        
        // Use TrustKit's pinning validator
        let validator = trustKit.pinningValidator
        let decision = validator.evaluateTrust(serverTrust, forHostname: domain)
        
        switch decision {
        case .shouldAllowConnection:
            NSLog("[DynamicPinning] ✅ TrustKit validation passed for: \(domain)")
            return true
        case .shouldBlockConnection:
            NSLog("[DynamicPinning] ❌ TrustKit validation failed for: \(domain)")
            return false
        case .domainNotPinned:
            NSLog("[DynamicPinning] ⚠️ Domain not pinned: \(domain), allowing connection")
            return true  // Allow connections to domains that are not pinned
        @unknown default:
            NSLog("[DynamicPinning] ⚠️ Unknown TrustKit decision for: \(domain)")
            return false
        }
    }
}
