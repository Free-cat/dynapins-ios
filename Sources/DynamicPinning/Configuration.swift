import Foundation

/// Configuration for the DynamicPinning SDK.
///
/// This struct holds the public key used for signature verification and the service URL
/// for fetching certificate fingerprints.
public struct Configuration {
    /// The Ed25519 public key encoded as a Base64 string.
    /// This key is used to verify the signature of fetched fingerprints.
    public let publicKey: String
    
    /// The URL of the Dynapins service that provides signed certificate fingerprints.
    public let serviceURL: URL
    
    /// Creates a new configuration instance.
    ///
    /// - Parameters:
    ///   - publicKey: Ed25519 public key as a Base64-encoded string
    ///   - serviceURL: URL of the fingerprint service
    public init(publicKey: String, serviceURL: URL) {
        self.publicKey = publicKey
        self.serviceURL = serviceURL
    }
}

