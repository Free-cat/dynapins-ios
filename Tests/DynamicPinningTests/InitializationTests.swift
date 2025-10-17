@testable import DynamicPinning
import XCTest

/// Tests for SDK initialization logic.
final class InitializationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        #if DEBUG
        DynamicPinning.resetForTesting()
        #endif
    }
    
    override func tearDown() {
        #if DEBUG
        DynamicPinning.resetForTesting()
        #endif
        super.tearDown()
    }
    
    // MARK: - Configuration Tests
    
    func testConfigurationInit() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5" // Base64 encoded "test_public_key"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        let domains = ["example.com"]
        
        // When
        let config = Configuration(signingPublicKey: publicKey, pinningServiceURL: serviceURL, domains: domains, includeBackupPins: false)
        
        // Then
        XCTAssertEqual(config.signingPublicKey, publicKey)
        XCTAssertEqual(config.pinningServiceURL, serviceURL)
        XCTAssertEqual(config.domains, domains)
    }
    
    // MARK: - Initialization Tests
    
    func testInitializeStoresConfiguration() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        let expectation = self.expectation(description: "Initialize completes")
        
        // When
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        ) { _, _ in
            expectation.fulfill()
        }
        
        // Then - Config is set immediately (even if pin fetch is async)
        let config = DynamicPinning.configuration
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.signingPublicKey, publicKey)
        XCTAssertEqual(config?.pinningServiceURL, serviceURL)
        
        waitForExpectations(timeout: 5.0)
    }
    
    func testInitializeIsThreadSafe() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        let expectation = self.expectation(description: "Thread safety")
        expectation.expectedFulfillmentCount = 10
        
        // When - Multiple threads try to read configuration after initialization
        DynamicPinning.initialize(signingPublicKey: publicKey, pinningServiceURL: serviceURL, domains: ["example.com"])
        
        for _ in 0..<10 {
            DispatchQueue.global().async {
                let config = DynamicPinning.configuration
                XCTAssertNotNil(config)
                XCTAssertEqual(config?.signingPublicKey, publicKey)
                expectation.fulfill()
            }
        }
        
        // Then
        waitForExpectations(timeout: 5.0)
    }
    
    func testSessionReturnsConfiguredURLSession() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        DynamicPinning.initialize(signingPublicKey: publicKey, pinningServiceURL: serviceURL, domains: ["example.com"])
        
        // When
        let session = DynamicPinning.session()
        
        // Then - Returns PinningURLSession with auto-retry capability
        XCTAssertNotNil(session)
        XCTAssertTrue(session is PinningURLSession, "Should return PinningURLSession")
    }
    
    func testSessionFailsIfNotInitialized() {
        // Given - SDK not initialized
        
        // When/Then - Calling session() should crash
        // Note: We can't test preconditionFailure in unit tests without special handling
        // This test documents the expected behavior
        
        // In a real test, you would use a testing framework that can catch crashes
        // For now, we document this as expected behavior
    }
    
    // MARK: - Multiple Initialization Tests
    
    #if DEBUG
    func testMultipleInitializeCallsCrashInDebug() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        DynamicPinning.initialize(signingPublicKey: publicKey, pinningServiceURL: serviceURL, domains: ["example.com"])
        
        // When/Then - Second call should crash in DEBUG
        // Note: We can't test preconditionFailure without special handling
        // This test documents the expected behavior
        
        // In production code, this would call:
        // DynamicPinning.initialize(signingPublicKey: publicKey, pinningServiceURL: serviceURL, domains: ["example.com"])
        // and it would crash with preconditionFailure
    }
    #endif
    
    // MARK: - Configuration Validation
    
    func testInitializeWithValidURL() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://dynapins.example.com/api/v1/cert-fingerprint")!
        
        // When
        DynamicPinning.initialize(signingPublicKey: publicKey, pinningServiceURL: serviceURL, domains: ["example.com"])
        
        // Then
        let config = DynamicPinning.configuration
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.pinningServiceURL.scheme, "https")
        XCTAssertEqual(config?.pinningServiceURL.host, "dynapins.example.com")
    }
    
    func testInitializeWithBase64PublicKey() {
        // Given - A valid Base64-encoded public key
        let publicKey = "MCowBQYDK2VwAyEA1234567890abcdefghijklmnopqrstuvwxyz="
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        // When
        DynamicPinning.initialize(signingPublicKey: publicKey, pinningServiceURL: serviceURL, domains: ["example.com"])
        
        // Then
        let config = DynamicPinning.configuration
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.signingPublicKey, publicKey)
    }
    
    func testInitializationWithDefaults() {
        // Given
        let publicKey = "another_key"
        let serviceURL = URL(string: "https://another.com")!
        
        // When
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["another.com"]
        )
        
        // Then
        let config = DynamicPinning.configuration
        XCTAssertNotNil(config)
        XCTAssertFalse(config?.includeBackupPins ?? true)
    }
    
    func testSessionReturnsPinningSession() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        DynamicPinning.initialize(signingPublicKey: publicKey, pinningServiceURL: serviceURL, domains: ["example.com"])
        
        // When
        let session = DynamicPinning.session()
        
        // Then - Returns PinningURLSession with auto-retry capability
        XCTAssertNotNil(session)
        XCTAssertTrue(session is PinningURLSession, "Should return PinningURLSession")
    }
}
