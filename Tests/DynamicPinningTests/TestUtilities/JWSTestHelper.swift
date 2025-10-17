import CryptoKit
import Foundation
import JOSESwift

@testable import DynamicPinning

/// Test helper for generating real ES256-signed JWS tokens for testing.
///
/// This helper generates a P-256 key pair and signs payloads using ES256,
/// producing valid JWS tokens that can be verified by CryptoService.
@available(iOS 14.0, macOS 10.15, *)
final class JWSTestHelper {
    
    /// A test key pair for signing JWS tokens
    struct TestKeyPair {
        let privateKey: P256.Signing.PrivateKey
        let publicKey: P256.Signing.PublicKey
        
        /// Base64-encoded public key in SPKI format (compatible with CryptoService)
        var publicKeyBase64: String {
            return publicKey.derRepresentation.base64EncodedString()
        }
    }
    
    /// Generate a new ES256 key pair for testing
    static func generateKeyPair() -> TestKeyPair {
        let privateKey = P256.Signing.PrivateKey()
        return TestKeyPair(
            privateKey: privateKey,
            publicKey: privateKey.publicKey
        )
    }
    
    /// Sign a JWS payload with the given private key
    ///
    /// - Parameters:
    ///   - payload: The payload to sign (will be JSON-encoded)
    ///   - privateKey: The P-256 private key to sign with
    ///   - kid: Optional key ID to include in the header
    /// - Returns: A compact JWS string (header.payload.signature)
    static func signJWS(
        payload: [String: Any],
        privateKey: P256.Signing.PrivateKey,
        kid: String? = nil
    ) throws -> String {
        // Encode payload to JSON
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let jwsPayload = Payload(payloadData)
        
        // Create header
        var header = JWSHeader(algorithm: .ES256)
        if let kid = kid {
            header.kid = kid
        }
        
        // Convert P256.Signing.PrivateKey to SecKey for JOSESwift
        let secKey = try convertPrivateKeyToSecKey(privateKey)
        
        // Create signer
        guard let signer = Signer(signingAlgorithm: .ES256, key: secKey) else {
            throw JWSError.signerCreationFailed
        }
        
        // Sign
        let jws = try JWS(header: header, payload: jwsPayload, signer: signer)
        return jws.compactSerializedString
    }
    
    /// Create a valid fingerprint payload for testing
    ///
    /// - Parameters:
    ///   - domain: The domain for the fingerprint
    ///   - pins: Array of pin hashes
    ///   - iat: Issued at timestamp (defaults to now)
    ///   - exp: Expiration timestamp (defaults to now + 1 hour)
    ///   - ttlSeconds: TTL in seconds (defaults to 3600)
    /// - Returns: A dictionary suitable for JWS payload
    static func createFingerprintPayload(
        domain: String,
        pins: [String],
        iat: Int? = nil,
        exp: Int? = nil,
        ttlSeconds: Int = 3600
    ) -> [String: Any] {
        let now = Int(Date().timeIntervalSince1970)
        return [
            "domain": domain,
            "pins": pins,
            "iat": iat ?? now,
            "exp": exp ?? (now + 3600),
            "ttl_seconds": ttlSeconds
        ]
    }
    
    /// Create a signed JWS token with fingerprint data
    ///
    /// - Parameters:
    ///   - domain: The domain for the fingerprint
    ///   - pins: Array of pin hashes
    ///   - privateKey: The private key to sign with
    ///   - iat: Issued at timestamp (defaults to now)
    ///   - exp: Expiration timestamp (defaults to now + 1 hour)
    ///   - kid: Optional key ID
    /// - Returns: A valid signed JWS token
    static func createSignedFingerprint(
        domain: String,
        pins: [String],
        privateKey: P256.Signing.PrivateKey,
        iat: Int? = nil,
        exp: Int? = nil,
        kid: String? = nil
    ) throws -> String {
        let payload = createFingerprintPayload(
            domain: domain,
            pins: pins,
            iat: iat,
            exp: exp
        )
        return try signJWS(payload: payload, privateKey: privateKey, kid: kid)
    }
    
    /// Convert P256.Signing.PrivateKey to SecKey for JOSESwift
    private static func convertPrivateKeyToSecKey(_ privateKey: P256.Signing.PrivateKey) throws -> SecKey {
        // Use x963 representation (uncompressed point)
        let x963Data = privateKey.x963Representation
        
        var error: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]
        
        guard let secKey = SecKeyCreateWithData(x963Data as CFData, attributes as CFDictionary, &error) else {
            if let error = error?.takeRetainedValue() {
                throw JWSError.keyConversionFailed(error as Error)
            }
            throw JWSError.keyConversionFailed(nil)
        }
        
        return secKey
    }
    
    enum JWSError: Error {
        case signerCreationFailed
        case keyConversionFailed(Error?)
    }
}

/// Fixed clock for deterministic timestamp testing
@available(iOS 14.0, macOS 10.15, *)
final class FixedClock {
    private let fixedTime: Int
    
    init(timestamp: Int) {
        self.fixedTime = timestamp
    }
    
    /// Returns the fixed timestamp
    func now() -> Int {
        return fixedTime
    }
    
    /// Create a fixed clock at the current time
    static func atCurrentTime() -> FixedClock {
        return FixedClock(timestamp: Int(Date().timeIntervalSince1970))
    }
    
    /// Create a fixed clock at a specific date
    static func at(year: Int, month: Int, day: Int, hour: Int = 12) -> FixedClock {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.timeZone = TimeZone(identifier: "UTC")
        
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components) ?? Date()
        return FixedClock(timestamp: Int(date.timeIntervalSince1970))
    }
}
