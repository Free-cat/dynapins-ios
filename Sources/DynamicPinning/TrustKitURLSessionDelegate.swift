import Foundation
import TrustKit

/// URLSession delegate that enforces TrustKit-based SSL pinning.
///
/// This delegate explicitly validates server certificates using TrustKit's pinning validator
/// and implements a fail-closed policy for configured domains.
@available(iOS 14.0, macOS 10.15, *)
final class TrustKitURLSessionDelegate: NSObject, URLSessionDelegate {
    
    /// The set of domains that require pinning enforcement (fail-closed)
    private var configuredDomains: Set<String>
    private let queue = DispatchQueue(label: "com.dynapins.delegate", attributes: .concurrent)
    
    /// Creates a new delegate instance
    /// - Parameter configuredDomains: Domains that must have valid pins (fail-closed)
    init(configuredDomains: [String]) {
        self.configuredDomains = Set(configuredDomains.map { $0.lowercased() })
        super.init()
    }
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle server trust authentication challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let host = challenge.protectionSpace.host.lowercased()
        
        // Get TrustKit's pinning validator
        let trustKit = TrustKit.sharedInstance()
        let validator = trustKit.pinningValidator
        
        // Evaluate trust using TrustKit
        let decision = validator.evaluateTrust(serverTrust, forHostname: host)
        
        switch decision {
        case .shouldAllowConnection:
            NSLog("[DynamicPinning] ✅ SSL validation passed for: \(host)")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            
        case .shouldBlockConnection:
            NSLog("[DynamicPinning] ❌ SSL validation failed (pin mismatch) for: \(host)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            
        case .domainNotPinned:
            // Fail-closed for configured domains, allow others
            if isDomainConfigured(host) {
                NSLog("[DynamicPinning] ❌ SSL validation failed (no pins configured yet) for: \(host)")
                completionHandler(.cancelAuthenticationChallenge, nil)
            } else {
                NSLog("[DynamicPinning] ⚠️ Domain not configured for pinning, allowing: \(host)")
                completionHandler(.performDefaultHandling, nil)
            }
            
        @unknown default:
            NSLog("[DynamicPinning] ⚠️ Unknown TrustKit decision for: \(host), failing challenge")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    
    /// Checks if a domain is in the configured domains list
    /// Handles both exact matches and wildcard patterns (*.example.com)
    private func isDomainConfigured(_ host: String) -> Bool {
        return queue.sync {
            // Check exact match
            if configuredDomains.contains(host) {
                return true
            }
            
            // Check wildcard match (*.example.com matches api.example.com)
            for configuredDomain in configuredDomains where configuredDomain.hasPrefix("*.") {
                let suffix = String(configuredDomain.dropFirst(2)) // Remove "*."
                if host.hasSuffix(suffix) {
                    return true
                }
            }
            
            return false
        }
    }
    
    /// Updates the set of configured domains (thread-safe)
    func updateConfiguredDomains(_ domains: [String]) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.configuredDomains.removeAll()
            self.configuredDomains.formUnion(domains.map { $0.lowercased() })
        }
    }
}
