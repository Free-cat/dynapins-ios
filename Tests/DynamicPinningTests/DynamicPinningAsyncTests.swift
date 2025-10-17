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
        let expectation = self.expectation(description: "Completion called")
        
        var successCount: Int?
        var failureCount: Int?
        
        // When
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: domains
        ) { success, failures in
            successCount = success
            failureCount = failures
            expectation.fulfill()
        }
        
        // Then
        wait(for: [expectation], timeout: 10.0)
        
        XCTAssertNotNil(successCount)
        XCTAssertNotNil(failureCount)
        
        // All 3 domains should fail with fake service
        XCTAssertEqual(successCount! + failureCount!, 3, "Total should equal number of domains")
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
        let expectation = self.expectation(description: "Completion called")
        
        // When
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        ) { _, _ in
            expectation.fulfill()
        }
        
        // Then - session() should work immediately (even before pin fetch completes)
        let session = DynamicPinning.session()
        XCTAssertNotNil(session, "Should be able to create session before pin fetch completes")
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - RefreshPins with Completion Tests
    
    func testRefreshPinsCallsCompletionHandler() {
        // Given - SDK must be initialized first
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        let initExpectation = self.expectation(description: "Init completes")
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        ) { _, _ in
            initExpectation.fulfill()
        }
        
        wait(for: [initExpectation], timeout: 5.0)
        
        // When - Refresh pins
        let refreshExpectation = self.expectation(description: "Refresh completes")
        var refreshSuccessCount: Int?
        var refreshFailureCount: Int?
        
        DynamicPinning.refreshPins { success, failures in
            refreshSuccessCount = success
            refreshFailureCount = failures
            refreshExpectation.fulfill()
        }
        
        // Then
        wait(for: [refreshExpectation], timeout: 5.0)
        
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
        // Given - SDK initialized
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        let initExpectation = self.expectation(description: "Init completes")
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        ) { _, _ in
            initExpectation.fulfill()
        }
        
        wait(for: [initExpectation], timeout: 5.0)
        
        // When - Refresh without completion handler (should not crash)
        DynamicPinning.refreshPins(completion: nil)
        
        // Then - Give time for refresh to attempt
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    // MARK: - Concurrent Operations Tests
    
    func testConcurrentInitializeCallsAreHandled() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        // When - First initialize (should succeed)
        let firstExpectation = self.expectation(description: "First init")
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        ) { _, _ in
            firstExpectation.fulfill()
        }
        
        // Try to initialize again immediately (should be rejected in DEBUG, ignored in RELEASE)
        #if !DEBUG
        let secondExpectation = self.expectation(description: "Second init ignored")
        DynamicPinning.initialize(
            signingPublicKey: "another_key",
            pinningServiceURL: serviceURL,
            domains: ["other.com"]
        ) { success, failures in
            // In RELEASE mode, second call should be ignored
            XCTAssertEqual(success, 0, "Second init should be ignored")
            XCTAssertEqual(failures, 0, "Second init should be ignored")
            secondExpectation.fulfill()
        }
        
        wait(for: [firstExpectation, secondExpectation], timeout: 5.0)
        #else
        wait(for: [firstExpectation], timeout: 5.0)
        #endif
    }
    
    func testConcurrentRefreshPinsCalls() {
        // Given - SDK initialized
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        
        let initExpectation = self.expectation(description: "Init completes")
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com", "api.example.com"]
        ) { _, _ in
            initExpectation.fulfill()
        }
        
        wait(for: [initExpectation], timeout: 5.0)
        
        // When - Multiple concurrent refresh calls
        let expectations = (0..<3).map { i in
            self.expectation(description: "Refresh \(i)")
        }
        
        for i in 0..<3 {
            DispatchQueue.global(qos: .utility).async {
                DynamicPinning.refreshPins { success, failures in
                    // Each refresh should get a response
                    XCTAssertTrue(success + failures >= 0, "Should get valid counts")
                    expectations[i].fulfill()
                }
            }
        }
        
        // Then - All refreshes should complete
        wait(for: expectations, timeout: 15.0)
    }
    
    // MARK: - Thread Safety Tests
    
    func testInitializeIsThreadSafe() {
        // Given
        let publicKey = "dGVzdF9wdWJsaWNfa2V5"
        let serviceURL = URL(string: "https://example.com/cert-fingerprint")!
        let expectation = self.expectation(description: "Thread safety test")
        expectation.expectedFulfillmentCount = 10
        
        // When - Initialize once
        DynamicPinning.initialize(
            signingPublicKey: publicKey,
            pinningServiceURL: serviceURL,
            domains: ["example.com"]
        ) { _, _ in
            // No-op
        }
        
        // Multiple threads reading configuration
        for _ in 0..<10 {
            DispatchQueue.global().async {
                let config = DynamicPinning.configuration
                XCTAssertNotNil(config, "Configuration should be accessible from any thread")
                expectation.fulfill()
            }
        }
        
        // Then
        wait(for: [expectation], timeout: 5.0)
    }
}
