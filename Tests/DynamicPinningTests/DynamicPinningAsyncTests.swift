@testable import DynamicPinning
import XCTest

/// Tests for DynamicPinning async API (initialize and refreshPins with completion handlers).
@available(iOS 14.0, macOS 10.15, *)
final class DynamicPinningAsyncTests: XCTestCase {
    
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
    
    // MARK: - Initialize with Completion Tests
    
    func testInitializeCallsCompletionHandler() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        let expectation = self.expectation(description: "Completion called")
        
        var completionCalled = false
        var successCount: Int?
        var failureCount: Int?
        
        // When
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        ) { success, failures in
            completionCalled = true
            successCount = success
            failureCount = failures
            expectation.fulfill()
        }
        
        // Then
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertTrue(completionCalled, "Completion handler should be called")
        XCTAssertNotNil(successCount, "Success count should be provided")
        XCTAssertNotNil(failureCount, "Failure count should be provided")
        
        // With invalid URL/key, we expect failures
        // (Since we're using fake URL and key, network will fail)
        XCTAssertEqual(successCount, 0, "Should have 0 successes with fake service")
        XCTAssertEqual(failureCount, 1, "Should have 1 failure (1 domain)")
    }
    
    func testInitializeWithMultipleDomains() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        let domains = ["api.example.com", "cdn.example.com", "auth.example.com"]
        
        // When - Initialize with multiple domains (network will fail, but that's OK)
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: domains
        )
        
        // Then - Verify initialization completed
        let config = DynamicPinning.configuration
        XCTAssertNotNil(config, "Configuration should be set after initialization")
        XCTAssertEqual(config?.domains.count, 3, "Should have 3 domains configured")
        
        // Give time for background pin fetching to attempt
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    func testInitializeWithoutCompletion() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        // When - Initialize without completion handler (should not crash)
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"],
            completion: nil
        )
        
        // Then - Configuration should be set immediately
        let config = DynamicPinning.configuration
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.signingPublicKey, publicKey)
        XCTAssertEqual(config?.domains, ["example.com"])
        
        // Give some time for background pin fetch to attempt
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    func testInitializeSetsDelegateImmediately() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        // NOTE: This test verifies that session() is available immediately,
        // even before the async pin fetch completes. The actual HTTP request
        // will fail (404) but that's expected - we're testing the initialization flow.
        
        // When
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        )
        
        // Then - session() should work immediately (even before pin fetch completes)
        let session = DynamicPinning.session()
        XCTAssertNotNil(session, "Should be able to create session before pin fetch completes")
        
        // Wait briefly for any background tasks
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    // MARK: - RefreshPins with Completion Tests
    
    func testRefreshPinsCallsCompletionHandler() {
        // Given - SDK must be initialized first
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        // Initialize without waiting for completion
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        )
        
        // Wait briefly for initialization
        Thread.sleep(forTimeInterval: 0.5)
        
        // When - Refresh pins
        let refreshExpectation = self.expectation(description: "Refresh completes")
        var refreshSuccessCount: Int?
        var refreshFailureCount: Int?
        
        DynamicPinning.refreshPins { success, failures in
            refreshSuccessCount = success
            refreshFailureCount = failures
            refreshExpectation.fulfill()
        }
        
        // Then - Wait with longer timeout for network operations
        wait(for: [refreshExpectation], timeout: 2.0)
        
        XCTAssertNotNil(refreshSuccessCount, "Refresh should provide success count")
        XCTAssertNotNil(refreshFailureCount, "Refresh should provide failure count")
        XCTAssertEqual(refreshSuccessCount! + refreshFailureCount!, 1, "Should process 1 domain")
    }
    
    func testRefreshPinsWithoutInitialization() {
        // Given - SDK NOT initialized
        
        // When - Attempt to refresh pins
        let expectation = self.expectation(description: "Completion called")
        var successCount: Int?
        var failureCount: Int?
        
        DynamicPinning.refreshPins { success, failures in
            successCount = success
            failureCount = failures
            expectation.fulfill()
        }
        
        // Then - Should return 0/0 immediately
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(successCount, 0, "Should return 0 successes when not initialized")
        XCTAssertEqual(failureCount, 0, "Should return 0 failures when not initialized")
    }
    
    func testRefreshPinsWithoutCompletion() {
        // Given - SDK initialized (network will fail, but that's OK)
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        )
        
        // Wait briefly for initialization
        Thread.sleep(forTimeInterval: 0.3)
        
        // When - Refresh without completion handler (should not crash)
        DynamicPinning.refreshPins(completion: nil)
        
        // Then - Give time for refresh to attempt
        Thread.sleep(forTimeInterval: 0.3)
    }
    
    // MARK: - Concurrent Operations Tests
    
    func testConcurrentInitializeCallsAreHandled() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        // When - First initialize (network will fail, but that's OK)
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        )
        
        // Wait briefly for initialization
        Thread.sleep(forTimeInterval: 0.2)
        
        // Try to initialize again immediately (should be rejected in DEBUG, ignored in RELEASE)
        #if !DEBUG
        DynamicPinning.initialize(
            signingPublicKey: "another_key",
            pinningServiceURL: serviceURL,
            domains: ["other.com"]
        )
        
        // Verify first configuration is still active
        let config = DynamicPinning.configuration
        XCTAssertEqual(config?.domains.first, "example.com", "First configuration should remain")
        #else
        // In DEBUG, second init would crash, so we just verify first init worked
        let config = DynamicPinning.configuration
        XCTAssertNotNil(config, "Configuration should be set after first init")
        #endif
        
        Thread.sleep(forTimeInterval: 0.2)
    }
    
    func testConcurrentRefreshPinsCalls() {
        // Given - SDK initialized
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        // Initialize (network will fail, but that's OK - we're testing thread safety)
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        )
        
        // Wait for initialization
        Thread.sleep(forTimeInterval: 0.5)
        
        // When - Multiple concurrent refresh calls (testing thread safety, not network success)
        // We're not waiting for completions as the test is about thread safety
        for _ in 0..<3 {
            DispatchQueue.global(qos: .utility).async {
                DynamicPinning.refreshPins { _, _ in
                    // Completion handler should be called even if network fails
                }
            }
        }
        
        // Then - Give time for concurrent operations to execute (testing no crashes)
        Thread.sleep(forTimeInterval: 2.0)
        
        // If we got here without crashing, test passed
        XCTAssertTrue(true, "Concurrent refresh calls completed without crashing")
    }
    
    // MARK: - Thread Safety Tests
    
    func testInitializeIsThreadSafe() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        let expectation = self.expectation(description: "Thread safety test")
        expectation.expectedFulfillmentCount = 10
        
        // When - Initialize once (network call will fail with 404, but that's OK)
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        )
        
        // Wait briefly for initialization to set up configuration
        Thread.sleep(forTimeInterval: 0.1)
        
        // Multiple threads reading configuration
        for _ in 0..<10 {
            DispatchQueue.global().async {
                let config = DynamicPinning.configuration
                XCTAssertNotNil(config, "Configuration should be accessible from any thread")
                expectation.fulfill()
            }
        }
        
        // Then
        wait(for: [expectation], timeout: 2.0)
    }
}
