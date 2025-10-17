import Foundation
import CryptoKit
import Security

/// Service for cryptographic operations including signature verification and hashing.
@available(iOS 14.0, macOS 10.15, *)
internal final class CryptoService {
    
    /// Errors that can occur during cryptographic operations
    enum CryptoError: Error {
        case invalidPublicKey
        case invalidSignature
        case signatureVerificationFailed
        case unableToExtractPublicKey
        case hashingFailed
    }
    
    /// Represents the signable payload structure matching the Go server's SignablePayload
    /// The order of fields MUST match the Go struct field order for signature verification
    private struct SignablePayload: Encodable {
        let domain: String
        let pins: [String]
        let created: String
        let expires: String
        let ttl_seconds: Int
        let keyId: String
        let alg: String
        
        private enum CodingKeys: String, CodingKey {
            case domain
            case pins
            case created
            case expires
            case ttl_seconds
            case keyId
            case alg
        }
    }
    
    /// Extracts the raw Ed25519 public key from SPKI (SubjectPublicKeyInfo) format.
    ///
    /// SPKI format includes a DER-encoded header before the raw key.
    /// For Ed25519, the SPKI structure is:
    /// - SEQUENCE (0x30)
    ///   - SEQUENCE (algorithm identifier)
    ///   - BIT STRING (0x03) containing the raw 32-byte public key
    ///
    /// - Parameter spkiData: The SPKI-encoded public key data
    /// - Returns: The raw 32-byte public key
    /// - Throws: `CryptoError.invalidPublicKey` if extraction fails
    private func extractRawPublicKey(from spkiData: Data) throws -> Data {
        // For Ed25519, SPKI format is typically 44 bytes:
        // 12 bytes header + 32 bytes raw key
        // The raw key is the last 32 bytes
        guard spkiData.count >= 32 else {
            throw CryptoError.invalidPublicKey
        }
        
        // Extract the last 32 bytes (the raw Ed25519 public key)
        let rawKey = spkiData.suffix(32)
        return rawKey
    }
    
    /// Verifies an Ed25519 signature for a network service response payload.
    ///
    /// - Parameters:
    ///   - response: The fingerprint response containing the payload and signature
    ///   - publicKey: The Ed25519 public key as a Base64-encoded string (SPKI format)
    /// - Returns: `true` if the signature is valid, `false` otherwise
    /// - Throws: `CryptoError` if the operation fails
    func verifySignatureForPayload(response: NetworkService.FingerprintResponse, publicKey: String) throws -> Bool {
        // IMPORTANT: We must construct JSON manually to match Go's json.Marshal output
        // Go preserves struct field order, but Swift's JSONEncoder sorts keys alphabetically
        // The exact byte-for-byte match is required for Ed25519 signature verification
        
        // Escape JSON strings
        func escapeJSON(_ str: String) -> String {
            var escaped = str
            escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
            escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
            escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
            escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
            escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
            return escaped
        }
        
        // Build JSON manually in the exact order as Go struct
        var jsonString = "{"
        jsonString += "\"domain\":\"\(escapeJSON(response.domain))\","
        
        // Pins array
        jsonString += "\"pins\":["
        let pinsJSON = response.pins.map { "\"\(escapeJSON($0))\"" }.joined(separator: ",")
        jsonString += pinsJSON
        jsonString += "],"
        
        jsonString += "\"created\":\"\(escapeJSON(response.created ?? ""))\","
        jsonString += "\"expires\":\"\(escapeJSON(response.expires ?? ""))\","
        jsonString += "\"ttl_seconds\":\(response.ttlSeconds),"
        jsonString += "\"keyId\":\"\(escapeJSON(response.keyId ?? ""))\","
        jsonString += "\"alg\":\"\(escapeJSON(response.alg ?? "Ed25519"))\""
        jsonString += "}"
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw CryptoError.signatureVerificationFailed
        }
        
        // Decode the public key from Base64
        guard let publicKeyData = Data(base64Encoded: publicKey) else {
            throw CryptoError.invalidPublicKey
        }
        
        // Extract raw key from SPKI format
        let rawPublicKey = try extractRawPublicKey(from: publicKeyData)
        
        // Create a Curve25519 public key from raw representation
        guard let verifyingKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey) else {
            throw CryptoError.invalidPublicKey
        }
        
        // Decode the signature from Base64
        guard let signatureData = Data(base64Encoded: response.signature) else {
            throw CryptoError.invalidSignature
        }
        
        // Verify the signature
        let isValid = verifyingKey.isValidSignature(signatureData, for: jsonData)
        
        return isValid
    }
    
    /// Verifies an Ed25519 signature for the given message.
    ///
    /// - Parameters:
    ///   - message: The message that was signed
    ///   - signature: The Ed25519 signature as a Base64-encoded string
    ///   - publicKey: The Ed25519 public key as a Base64-encoded string (SPKI format)
    /// - Returns: `true` if the signature is valid, `false` otherwise
    /// - Throws: `CryptoError` if the operation fails
    func verifySignature(message: String, signature: String, publicKey: String) throws -> Bool {
        // Decode the public key from Base64
        guard let publicKeyData = Data(base64Encoded: publicKey) else {
            throw CryptoError.invalidPublicKey
        }
        
        // Extract raw key from SPKI format
        let rawPublicKey = try extractRawPublicKey(from: publicKeyData)
        
        // Create a Curve25519 public key from raw representation
        guard let verifyingKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey) else {
            throw CryptoError.invalidPublicKey
        }
        
        // Decode the signature from Base64
        guard let signatureData = Data(base64Encoded: signature) else {
            throw CryptoError.invalidSignature
        }
        
        // Convert message to data
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.signatureVerificationFailed
        }
        
        // Verify the signature
        let isValid = verifyingKey.isValidSignature(signatureData, for: messageData)
        
        return isValid
    }
    
    /// Computes the SHA-256 hash of a certificate's public key in SPKI (SubjectPublicKeyInfo) format.
    ///
    /// This matches the server's implementation which hashes the DER-encoded SPKI.
    /// SPKI format includes the algorithm identifier and the public key, which is the
    /// standard format for certificate pinning.
    ///
    /// - Parameter serverTrust: The server trust object containing the certificate
    /// - Returns: The SHA-256 hash as a hex-encoded string
    /// - Throws: `CryptoError` if unable to extract or hash the public key
    func hashPublicKey(fromServerTrust serverTrust: SecTrust) throws -> String {
        // Get the certificate chain
        guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            throw CryptoError.unableToExtractPublicKey
        }
        
        // Extract the public key from the certificate
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            throw CryptoError.unableToExtractPublicKey
        }
        
        // Get the SPKI (SubjectPublicKeyInfo) representation in DER format
        // This is the standard format that includes the algorithm identifier
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA, // Will be determined automatically
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        
        // Copy external representation with SPKI format
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw CryptoError.unableToExtractPublicKey
        }
        
        // For proper SPKI hashing, we need to construct the full SPKI structure
        // However, SecKeyCopyExternalRepresentation returns different formats:
        // - For RSA: PKCS#1 format (raw key without algorithm identifier)
        // - For EC: X9.63 format (raw key)
        // We need to convert to SPKI format by getting the certificate data directly
        
        // Get certificate data
        let certificateData = SecCertificateCopyData(certificate) as Data
        
        // Parse certificate to extract SPKI
        // For simplicity and correctness, we'll hash the public key in SPKI format
        // by extracting it from the certificate's DER encoding
        guard let spkiData = extractSPKIFromCertificate(certificateData) else {
            throw CryptoError.unableToExtractPublicKey
        }
        
        // Compute SHA-256 hash of SPKI
        let hash = SHA256.hash(data: spkiData)
        
        // Convert to hex string
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        
        return hashString
    }
    
    /// Extracts the SPKI (SubjectPublicKeyInfo) from a DER-encoded certificate.
    ///
    /// This is a simplified DER parser that extracts the SPKI structure from an X.509 certificate.
    /// The SPKI is located in the TBSCertificate -> SubjectPublicKeyInfo field.
    ///
    /// - Parameter certificateData: The DER-encoded certificate data
    /// - Returns: The SPKI data, or nil if extraction fails
    private func extractSPKIFromCertificate(_ certificateData: Data) -> Data? {
        // X.509 Certificate structure (simplified):
        // Certificate ::= SEQUENCE {
        //     tbsCertificate       TBSCertificate,
        //     ...
        // }
        // TBSCertificate ::= SEQUENCE {
        //     version         [0]  EXPLICIT Version DEFAULT v1,
        //     serialNumber         CertificateSerialNumber,
        //     signature            AlgorithmIdentifier,
        //     issuer               Name,
        //     validity             Validity,
        //     subject              Name,
        //     subjectPublicKeyInfo SubjectPublicKeyInfo,  <-- We want this
        //     ...
        // }
        
        let data = certificateData
        var index = 0
        
        // Helper to read a DER length
        func readLength() -> Int? {
            guard index < data.count else { return nil }
            let firstByte = data[index]
            index += 1
            
            if firstByte & 0x80 == 0 {
                // Short form
                return Int(firstByte)
            } else {
                // Long form
                let numBytes = Int(firstByte & 0x7F)
                guard index + numBytes <= data.count else { return nil }
                
                var length = 0
                for _ in 0..<numBytes {
                    length = (length << 8) | Int(data[index])
                    index += 1
                }
                return length
            }
        }
        
        // Skip outer SEQUENCE (Certificate)
        guard index < data.count, data[index] == 0x30 else { return nil } // SEQUENCE tag
        index += 1
        guard let _ = readLength() else { return nil }
        
        // Skip TBSCertificate SEQUENCE tag
        guard index < data.count, data[index] == 0x30 else { return nil }
        index += 1
        guard let _ = readLength() else { return nil }
        
        // Skip version (EXPLICIT [0])
        if index < data.count && data[index] == 0xA0 {
            index += 1
            guard let versionLength = readLength() else { return nil }
            index += versionLength
        }
        
        // Skip serialNumber
        guard index < data.count, data[index] == 0x02 else { return nil } // INTEGER tag
        index += 1
        guard let serialLength = readLength() else { return nil }
        index += serialLength
        
        // Skip signature AlgorithmIdentifier (SEQUENCE)
        guard index < data.count, data[index] == 0x30 else { return nil }
        index += 1
        guard let sigAlgLength = readLength() else { return nil }
        index += sigAlgLength
        
        // Skip issuer (SEQUENCE)
        guard index < data.count, data[index] == 0x30 else { return nil }
        index += 1
        guard let issuerLength = readLength() else { return nil }
        index += issuerLength
        
        // Skip validity (SEQUENCE)
        guard index < data.count, data[index] == 0x30 else { return nil }
        index += 1
        guard let validityLength = readLength() else { return nil }
        index += validityLength
        
        // Skip subject (SEQUENCE)
        guard index < data.count, data[index] == 0x30 else { return nil }
        index += 1
        guard let subjectLength = readLength() else { return nil }
        index += subjectLength
        
        // Now we're at subjectPublicKeyInfo (SEQUENCE)
        guard index < data.count, data[index] == 0x30 else { return nil }
        let spkiStart = index
        index += 1
        guard let spkiLength = readLength() else { return nil }
        
        // Extract SPKI (tag + length + content)
        let totalSPKILength = index - spkiStart + spkiLength
        guard spkiStart + totalSPKILength <= data.count else { return nil }
        
        return data.subdata(in: spkiStart..<(spkiStart + totalSPKILength))
    }
    
    /// Computes the SHA-256 hash of the given data.
    ///
    /// - Parameter data: The data to hash
    /// - Returns: The SHA-256 hash as a hex-encoded string
    func sha256Hash(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Computes the SHA-256 hash of the given string.
    ///
    /// - Parameter string: The string to hash
    /// - Returns: The SHA-256 hash as a hex-encoded string
    /// - Throws: `CryptoError` if the string cannot be converted to data
    func sha256Hash(of string: String) throws -> String {
        guard let data = string.data(using: .utf8) else {
            throw CryptoError.hashingFailed
        }
        return sha256Hash(of: data)
    }
}

