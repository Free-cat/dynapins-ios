import Foundation

/// Events emitted during certificate pinning validation.
///
/// Use these events with `DynamicPinning.setObservabilityHandler` to monitor
/// pinning behavior and integrate with your logging or telemetry systems.
public enum PinningEvent {
    /// Certificate validation succeeded for the specified domain.
    case success(domain: String)
    
    /// Certificate validation failed for the specified domain with the given reason.
    case failure(domain: String, reason: PinningFailureReason)
    
    /// A cached fingerprint was used for validation (no network request needed).
    case cacheHit(domain: String)
    
    /// No cached fingerprint was found; fetching from service.
    case cacheMiss(domain: String)
}

/// Reasons why certificate pinning validation might fail.
///
/// These enum cases provide structured failure information without exposing
/// sensitive data like certificate material or PII.
public enum PinningFailureReason {
    /// No cached fingerprint was available and the service fetch failed.
    case noCachedFingerprint
    
    /// The network request to fetch the fingerprint from the service failed.
    case fingerprintFetchFailed
    
    /// The signature verification of the fetched fingerprint failed.
    case signatureVerificationFailed
    
    /// The server's certificate hash did not match the expected fingerprint.
    case hashMismatch
    
    /// An error occurred while accessing the iOS Keychain.
    case keychainError
    
    /// The domain did not match the pattern in the fingerprint response.
    case wildcardMismatch
    
    /// Failed to extract or hash the server's public key from the certificate.
    case certificateProcessingFailed
}

