import Foundation
import Security

/// Service for securely storing and retrieving certificate fingerprints from the iOS Keychain.
internal final class KeychainService {
    
    /// Errors that can occur during Keychain operations
    enum KeychainError: Error {
        case unableToSave
        case unableToLoad
        case unableToDelete
        case itemNotFound
        case unexpectedData
        case keychainUnavailable
    }
    
    /// The service identifier used for Keychain items
    private let serviceIdentifier = "com.dynapins.sdk.fingerprints"
    
    /// Saves a fingerprint to the Keychain with an expiration date.
    ///
    /// - Parameters:
    ///   - fingerprint: The certificate fingerprint hash to store
    ///   - domain: The domain pattern (e.g., "*.example.com") this fingerprint applies to
    ///   - expiresAt: The expiration date for this fingerprint
    /// - Throws: `KeychainError` if the operation fails
    func saveFingerprint(_ fingerprint: String, forDomain domain: String, expiresAt: Date) throws {
        // Create the data structure to store
        let fingerprintData = CachedFingerprint(
            domain: domain,
            fingerprint: fingerprint,
            expiresAt: expiresAt
        )
        
        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(fingerprintData) else {
            throw KeychainError.unableToSave
        }
        
        // Create the Keychain query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: domain,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // First, try to delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add the new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave
        }
    }
    
    /// Retrieves a cached fingerprint for the specified domain if it exists and hasn't expired.
    ///
    /// - Parameter domain: The domain pattern to look up
    /// - Returns: The cached fingerprint if found and not expired, nil otherwise
    /// - Throws: `KeychainError` if the Keychain is unavailable or data is corrupted
    func loadFingerprint(forDomain domain: String) throws -> CachedFingerprint? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: domain,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.unableToLoad
        }
        
        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }
        
        // Decode the cached fingerprint
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cachedFingerprint = try? decoder.decode(CachedFingerprint.self, from: data) else {
            throw KeychainError.unexpectedData
        }
        
        // Check if the fingerprint has expired
        if cachedFingerprint.expiresAt < Date() {
            // Expired, delete it and return nil
            try? deleteFingerprint(forDomain: domain)
            return nil
        }
        
        return cachedFingerprint
    }
    
    /// Deletes a cached fingerprint from the Keychain.
    ///
    /// - Parameter domain: The domain pattern to delete
    /// - Throws: `KeychainError` if the operation fails
    func deleteFingerprint(forDomain domain: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: domain
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // Consider success even if item was not found
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }
    
    /// Clears all cached fingerprints from the Keychain.
    ///
    /// This is useful for testing or resetting the cache.
    ///
    /// - Throws: `KeychainError` if the operation fails
    func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // Consider success even if no items were found
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }
}

/// Represents a cached certificate fingerprint with its metadata.
struct CachedFingerprint: Codable {
    /// The domain pattern this fingerprint applies to (e.g., "*.example.com")
    let domain: String
    
    /// The SHA-256 hash of the certificate's public key (hex-encoded)
    let fingerprint: String
    
    /// The expiration date after which this fingerprint should not be used
    let expiresAt: Date
}
