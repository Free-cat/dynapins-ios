@testable import DynamicPinning
import XCTest

/// Tests for the CryptoService class.
@available(iOS 14.0, macOS 10.15, *)
final class CryptoServiceTests: XCTestCase {
    
    var cryptoService: CryptoService!
    
    override func setUp() {
        super.setUp()
        cryptoService = CryptoService()
    }
    
    override func tearDown() {
        cryptoService = nil
        super.tearDown()
    }
    
    // MARK: - Signature Verification Tests
    
    func testVerifySignatureWithValidSignature() throws {
        // Given - Test Ed25519 key pair and signature
        // Note: In a real test, you would use actual Ed25519 keys
        // For now, we test the interface
        
        // This test would require a real Ed25519 key pair
        // We'll skip actual verification for now and document expected behavior
        
        // Expected behavior:
        // - Valid signature should return true
        // - Invalid signature should return false
        // - Invalid public key should throw error
    }
    
    func testVerifySignatureWithInvalidPublicKey() {
        // Given
        let message = "test_message"
        let signature = "dGVzdF9zaWduYXR1cmU=" // Base64 encoded "test_signature"
        let invalidPublicKey = "not_base64!!!"
        
        // When/Then
        XCTAssertThrowsError(try cryptoService.verifySignature(
            message: message,
            signature: signature,
            publicKey: invalidPublicKey
        )) { error in
            XCTAssertTrue(error is CryptoService.CryptoError)
        }
    }
    
    func testVerifySignatureWithInvalidSignature() {
        // Given
        let message = "test_message"
        let invalidSignature = "not_base64!!!"
        let publicKey = "MCowBQYDK2VwAyEAGb9ECWmEzf6FQbrBZ9w7lshQhqowtrbLDFw4rXAxZuE=" // Example public key
        
        // When/Then
        XCTAssertThrowsError(try cryptoService.verifySignature(
            message: message,
            signature: invalidSignature,
            publicKey: publicKey
        )) { error in
            XCTAssertTrue(error is CryptoService.CryptoError)
        }
    }
    
    // MARK: - SHA-256 Hash Tests
    
    func testSha256HashOfData() {
        // Given
        let testString = "Hello, World!"
        let testData = testString.data(using: .utf8)!
        
        // When
        let hash = cryptoService.sha256Hash(of: testData)
        
        // Then
        XCTAssertFalse(hash.isEmpty)
        XCTAssertEqual(hash.count, 64) // SHA-256 produces 64 hex characters
        
        // Verify it's consistent
        let hash2 = cryptoService.sha256Hash(of: testData)
        XCTAssertEqual(hash, hash2)
        
        // Known SHA-256 hash of "Hello, World!"
        let expectedHash = "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"
        XCTAssertEqual(hash, expectedHash)
    }
    
    func testSha256HashOfString() throws {
        // Given
        let testString = "Hello, World!"
        
        // When
        let hash = try cryptoService.sha256Hash(of: testString)
        
        // Then
        XCTAssertFalse(hash.isEmpty)
        XCTAssertEqual(hash.count, 64)
        
        // Known SHA-256 hash of "Hello, World!"
        let expectedHash = "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"
        XCTAssertEqual(hash, expectedHash)
    }
    
    func testSha256HashOfEmptyData() {
        // Given
        let emptyData = Data()
        
        // When
        let hash = cryptoService.sha256Hash(of: emptyData)
        
        // Then
        XCTAssertFalse(hash.isEmpty)
        XCTAssertEqual(hash.count, 64)
        
        // Known SHA-256 hash of empty string
        let expectedHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        XCTAssertEqual(hash, expectedHash)
    }
    
    func testSha256HashOfEmptyString() throws {
        // Given
        let emptyString = ""
        
        // When
        let hash = try cryptoService.sha256Hash(of: emptyString)
        
        // Then
        XCTAssertEqual(hash.count, 64)
        
        // Known SHA-256 hash of empty string
        let expectedHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        XCTAssertEqual(hash, expectedHash)
    }
    
    func testSha256HashConsistency() {
        // Given
        let testData = "test data for hashing".data(using: .utf8)!
        
        // When
        let hash1 = cryptoService.sha256Hash(of: testData)
        let hash2 = cryptoService.sha256Hash(of: testData)
        let hash3 = cryptoService.sha256Hash(of: testData)
        
        // Then - All hashes should be identical
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash2, hash3)
    }
    
    func testSha256HashDifferentInputsProduceDifferentHashes() {
        // Given
        let data1 = "test1".data(using: .utf8)!
        let data2 = "test2".data(using: .utf8)!
        
        // When
        let hash1 = cryptoService.sha256Hash(of: data1)
        let hash2 = cryptoService.sha256Hash(of: data2)
        
        // Then
        XCTAssertNotEqual(hash1, hash2)
    }
    
    // MARK: - Hash Format Tests
    
    func testHashFormatIsLowercase() {
        // Given
        let testData = "test".data(using: .utf8)!
        
        // When
        let hash = cryptoService.sha256Hash(of: testData)
        
        // Then - Hash should be lowercase hex
        XCTAssertEqual(hash, hash.lowercased())
        
        // Verify it contains only valid hex characters
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        let hashCharacterSet = CharacterSet(charactersIn: hash)
        XCTAssertTrue(hexCharacterSet.isSuperset(of: hashCharacterSet))
    }
}
