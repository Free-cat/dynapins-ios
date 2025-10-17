import CryptoKit
import Foundation
import JOSESwift
import Security

/// Service for cryptographic operations including JWT verification and hashing.
@available(iOS 14.0, macOS 10.15, *)
internal final class CryptoService {
    
    /// Clock function for getting current timestamp (injectable for testing)
    private let currentTimestamp: () -> Int
    
    /// Initialize with default clock (current time)
    init() {
        self.currentTimestamp = { Int(Date().timeIntervalSince1970) }
    }
    
    /// Initialize with custom clock for testing
    init(currentTimestamp: @escaping () -> Int) {
        self.currentTimestamp = currentTimestamp
    }
    
    /// Errors that can occur during cryptographic operations
    enum CryptoError: Error {
        case invalidPublicKey
        case invalidSignature
        case signatureVerificationFailed
        case invalidJWSFormat
        case tokenExpired
        case invalidTimestamp
        case invalidAlgorithm
        case missingClaims
        case domainMismatch(expected: String, actual: String)
    }
    
    /// Represents the JWS payload structure from the backend
    struct JWSPayload: Codable {
        let domain: String
        let pins: [String]
        let iat: Int
        let exp: Int
        let ttlSeconds: Int
        
        private enum CodingKeys: String, CodingKey {
            case domain, pins, iat, exp
            case ttlSeconds = "ttl_seconds"
        }
    }
    
    /// Verifies a JWS token and returns the decoded payload.
    ///
    /// This function:
    /// - Parses the JWS compact serialization format
    /// - Validates the signature using the provided ECDSA P-256 public key with ES256
    /// - Validates the expiration (exp) claim
    /// - Validates the issued at (iat) claim with ±5 minute clock skew tolerance
    /// - Verifies the algorithm is ES256
    /// - Validates that the payload domain matches the expected domain
    ///
    /// - Parameters:
    ///   - jwsString: The JWS token in compact serialization format
    ///   - publicKey: The ECDSA P-256 public key as a Base64-encoded string (SPKI format)
    ///   - expectedDomain: The domain we requested pins for (optional, but recommended for security)
    /// - Returns: The decoded and validated payload
    /// - Throws: `CryptoError` if verification fails
    func verifyJWS(jwsString: String, publicKey: String, expectedDomain: String? = nil) throws -> JWSPayload {
        let jws = try parseJWS(jwsString)
        let verifier = try createVerifier(from: publicKey)
        let payload = try verifySignature(jws: jws, verifier: verifier)
        let decodedPayload = try decodePayload(payload)
        try validateTimestamps(decodedPayload)
        try validateDomain(decodedPayload, expectedDomain: expectedDomain)
        return decodedPayload
    }
    
    // MARK: - Private Helper Methods
    
    private func parseJWS(_ jwsString: String) throws -> JWS {
        guard let jws = try? JWS(compactSerialization: jwsString) else {
            throw CryptoError.invalidJWSFormat
        }
        
        // Extract and log kid for observability (for future key rotation support)
        if let kid = jws.header.kid {
            NSLog("[DynamicPinning] JWS token kid: \(kid)")
        }
        
        // Verify algorithm is ES256
        guard jws.header.algorithm == .ES256 else {
            NSLog("[DynamicPinning] Expected ES256, got: \(jws.header.algorithm?.rawValue ?? "unknown")")
            throw CryptoError.invalidAlgorithm
        }
        
        return jws
    }
    
    private func createVerifier(from publicKey: String) throws -> Verifier {
        // Decode the ECDSA P-256 public key from Base64 (SPKI format)
        guard let publicKeyData = Data(base64Encoded: publicKey) else {
            NSLog("[DynamicPinning] Failed to decode public key from Base64")
            throw CryptoError.invalidPublicKey
        }
        
        // Create P256.Signing.PublicKey from DER (SPKI) representation using CryptoKit
        let p256Key: P256.Signing.PublicKey
        do {
            p256Key = try P256.Signing.PublicKey(derRepresentation: publicKeyData)
        } catch {
            NSLog("[DynamicPinning] Failed to create P256 key from DER: \(error)")
            throw CryptoError.invalidPublicKey
        }
        
        // Convert to SecKey using x963 representation for JOSESwift
        let x963Data = p256Key.x963Representation
        var secError: Unmanaged<CFError>?
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256
        ]
        
        guard let secKey = SecKeyCreateWithData(x963Data as CFData, attributes as CFDictionary, &secError) else {
            if let error = secError?.takeRetainedValue() {
                NSLog("[DynamicPinning] Failed to create SecKey from x963: \(error)")
            }
            throw CryptoError.invalidPublicKey
        }
        
        // Create EC public key verifier using JOSESwift
        guard let verifier = Verifier(verifyingAlgorithm: .ES256, key: secKey) else {
            NSLog("[DynamicPinning] Failed to create Verifier for ES256")
            throw CryptoError.invalidPublicKey
        }
        
        return verifier
    }
    
    private func verifySignature(jws: JWS, verifier: Verifier) throws -> Payload {
        do {
            return try jws.validate(using: verifier).payload
        } catch {
            NSLog("[DynamicPinning] JWS signature verification failed: \(error)")
            throw CryptoError.signatureVerificationFailed
        }
    }
    
    private func decodePayload(_ payload: Payload) throws -> JWSPayload {
        let payloadData = payload.data()
        let decoder = JSONDecoder()
        
        do {
            return try decoder.decode(JWSPayload.self, from: payloadData)
        } catch {
            NSLog("[DynamicPinning] Failed to decode JWS payload: \(error)")
            throw CryptoError.missingClaims
        }
    }
    
    private func validateTimestamps(_ payload: JWSPayload) throws {
        let now = currentTimestamp()
        let clockSkewTolerance = 300 // 5 minutes
        
        // Check if token is not expired
        guard payload.exp > now else {
            NSLog("[DynamicPinning] Token expired: exp=\(payload.exp), now=\(now)")
            throw CryptoError.tokenExpired
        }
        
        // Check if iat is not too far in the future (with clock skew tolerance)
        guard payload.iat <= now + clockSkewTolerance else {
            NSLog("[DynamicPinning] Token iat too far in future: iat=\(payload.iat), now=\(now)")
            throw CryptoError.invalidTimestamp
        }
    }
    
    private func validateDomain(_ payload: JWSPayload, expectedDomain: String?) throws {
        guard let expectedDomain = expectedDomain else { return }
        
        let normalizedExpected = expectedDomain.lowercased()
        let normalizedActual = payload.domain.lowercased()
        
        // Check exact match or wildcard match
        let isMatch = normalizedExpected == normalizedActual ||
                      (normalizedActual.hasPrefix("*.") && 
                       normalizedExpected.hasSuffix(String(normalizedActual.dropFirst(2))))
        
        guard isMatch else {
            NSLog("[DynamicPinning] Domain mismatch: expected=\(expectedDomain), actual=\(payload.domain)")
            throw CryptoError.domainMismatch(expected: expectedDomain, actual: payload.domain)
        }
    }
    
}
