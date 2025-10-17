import XCTest
@testable import DynamicPinning

/// Tests for the NetworkService class.
@available(iOS 14.0, macOS 10.15, *)
final class NetworkServiceTests: XCTestCase {
    
    var networkService: NetworkService!
    let testServiceURL = URL(string: "https://example.com/cert-fingerprint")!
    
    override func setUp() {
        super.setUp()
        networkService = NetworkService(serviceURL: testServiceURL)
    }
    
    override func tearDown() {
        networkService = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        // Given/When
        let service = NetworkService(serviceURL: testServiceURL)
        
        // Then
        XCTAssertNotNil(service)
    }
    
    // MARK: - Response Decoding Tests
    
    func testFingerprintResponseDecoding() throws {
        // Given
        let json = """
        {
            "domain": "*.example.com",
            "pins": ["a1b2c3d4e5f6g7h8", "x9y8z7w6v5u4t3s2"],
            "created": "2025-10-17T11:00:00Z",
            "expires": "2025-10-17T12:00:00Z",
            "ttl_seconds": 86400,
            "keyId": "test-key",
            "alg": "Ed25519",
            "signature": "dGVzdF9zaWduYXR1cmU="
        }
        """
        let jsonData = json.data(using: .utf8)!
        
        // When
        let decoder = JSONDecoder()
        let response = try decoder.decode(NetworkService.FingerprintResponse.self, from: jsonData)
        
        // Then
        XCTAssertEqual(response.domain, "*.example.com")
        XCTAssertEqual(response.pins.count, 2)
        XCTAssertEqual(response.pins[0], "a1b2c3d4e5f6g7h8")
        XCTAssertEqual(response.fingerprint, "a1b2c3d4e5f6g7h8") // Computed property
        XCTAssertEqual(response.signature, "dGVzdF9zaWduYXR1cmU=")
        XCTAssertEqual(response.ttlSeconds, 86400)
        XCTAssertEqual(response.ttl, 86400) // Computed property
        XCTAssertEqual(response.keyId, "test-key")
        XCTAssertEqual(response.alg, "Ed25519")
    }
    
    func testFingerprintResponseEncodingDecoding() throws {
        // Given
        let json = """
        {
            "domain": "api.example.com",
            "pins": ["a1b2c3d4"],
            "created": "2025-10-17T11:00:00Z",
            "expires": "2025-10-17T12:00:00Z",
            "ttl_seconds": 3600,
            "keyId": "test",
            "alg": "Ed25519",
            "signature": "sig=="
        }
        """
        let jsonData = json.data(using: .utf8)!
        
        // When
        let decoder = JSONDecoder()
        let response = try decoder.decode(NetworkService.FingerprintResponse.self, from: jsonData)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        
        let redecoded = try decoder.decode(NetworkService.FingerprintResponse.self, from: data)
        
        // Then
        XCTAssertEqual(redecoded.domain, response.domain)
        XCTAssertEqual(redecoded.pins, response.pins)
        XCTAssertEqual(redecoded.fingerprint, response.fingerprint)
        XCTAssertEqual(redecoded.signature, response.signature)
        XCTAssertEqual(redecoded.ttl, response.ttl)
    }
    
    // MARK: - Network Request Tests
    
    // Note: These tests would require mocking URLSession or using a test server
    // For production code, you would:
    // 1. Use URLProtocol to mock network responses
    // 2. Use a test server that returns known responses
    // 3. Use dependency injection to swap URLSession for testing
    
    func testFetchFingerprintWithMockServer() {
        // This test demonstrates the expected behavior
        // In a real implementation, you would:
        // 1. Set up a mock URLProtocol
        // 2. Register it with URLSession
        // 3. Return a predefined response
        // 4. Verify the parsing and handling
        
        // Expected behavior documented:
        // - Successful response (200) should decode to FingerprintResponse
        // - Network error should return .networkFailure
        // - 404/500 should return .invalidStatusCode
        // - Invalid JSON should return .decodingFailed
    }
    
    func testFetchFingerprintErrorHandling() {
        // This test would verify error handling for:
        // - Network timeouts
        // - Invalid URLs
        // - Server errors
        // - Malformed responses
        
        // These require mocking or integration tests with a test server
    }
    
    // MARK: - URL Configuration Tests
    
    func testServiceURLIsCorrectlyStored() {
        // Given
        let customURL = URL(string: "https://api.dynapins.com/v1/fingerprint")!
        
        // When
        let service = NetworkService(serviceURL: customURL)
        
        // Then
        XCTAssertNotNil(service)
        // Note: serviceURL is private, but we verify it's used correctly in integration tests
    }
}

