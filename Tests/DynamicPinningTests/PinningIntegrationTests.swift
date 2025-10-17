@testable import DynamicPinning
import XCTest

/// End-to-end integration tests for the complete pinning flow.
///
/// These tests require a running Dynapins backend server.
/// Set the following environment variables to run these tests:
/// - TEST_SERVICE_URL: URL of the Dynapins service (e.g., http://localhost:8080/v1/pins?domain=)
/// - TEST_PUBLIC_KEY: Base64-encoded Ed25519 public key
/// - TEST_DOMAIN: Domain to test (must be allowed in server's ALLOWED_DOMAINS)
///
/// Example:
/// ```bash
/// export TEST_SERVICE_URL="http://localhost:8080/v1/pins?domain="
/// export TEST_PUBLIC_KEY="MCowBQYDK2VwAyEA..."
/// export TEST_DOMAIN="example.com"
/// swift test --filter PinningIntegrationTests
/// ```
@available(iOS 14.0, macOS 10.15, *)
final class PinningIntegrationTests: XCTestCase {
    
    var serviceURL: URL?
    var publicKey: String?
    var testDomain: String?
    var shouldSkipTests: Bool = false
    
    override func setUp() {
        super.setUp()
        
        #if DEBUG
        DynamicPinning.resetForTesting()
        #endif
        
        // Load configuration from environment variables
        guard let urlString = ProcessInfo.processInfo.environment["TEST_SERVICE_URL"],
              let key = ProcessInfo.processInfo.environment["TEST_PUBLIC_KEY"],
              let domain = ProcessInfo.processInfo.environment["TEST_DOMAIN"] else {
            print("⚠️ Skipping integration tests - environment variables not set")
            print("Set TEST_SERVICE_URL, TEST_PUBLIC_KEY, and TEST_DOMAIN to run these tests")
            shouldSkipTests = true
            return
        }
        
        guard let url = URL(string: urlString + domain) else {
            print("⚠️ Invalid TEST_SERVICE_URL")
            shouldSkipTests = true
            return
        }
        
        serviceURL = url
        publicKey = key
        testDomain = domain
        shouldSkipTests = false
    }
    
    override func tearDown() {
        #if DEBUG
        DynamicPinning.resetForTesting()
        #endif
        
        // Clean up Keychain
        if let domain = testDomain {
            let keychainService = KeychainService()
            try? keychainService.deleteFingerprint(forDomain: domain)
        }
        
        super.tearDown()
    }
    
    // MARK: - Basic Integration Tests
    
    func testEndToEndPinningFlow() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let serviceURL = serviceURL,
              let publicKey = publicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Step 1: Initialize SDK
        DynamicPinning.initialize(publicKey: publicKey, serviceURL: serviceURL)
        
        // Step 2: Create session
        let session = DynamicPinning.session()
        XCTAssertNotNil(session)
        
        // Step 3: Make HTTPS request to test domain
        let requestURL = URL(string: "https://\(testDomain)")!
        let expectation = self.expectation(description: "Request completed")
        
        var requestSuccess = false
        var requestError: Error?
        
        let task = session.dataTask(with: requestURL) { _, _, error in
            requestError = error
            requestSuccess = (error == nil)
            expectation.fulfill()
        }
        
        task.resume()
        
        waitForExpectations(timeout: 30.0) { error in
            if let error = error {
                XCTFail("Timeout: \(error)")
            }
        }
        
        // Verify the request succeeded (pinning validated)
        if let error = requestError {
            XCTFail("Request failed: \(error.localizedDescription)")
        }
        
        XCTAssertTrue(requestSuccess, "Request should succeed with valid pinning")
    }
    
    func testCachingBehavior() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let serviceURL = serviceURL,
              let publicKey = publicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Initialize SDK
        DynamicPinning.initialize(publicKey: publicKey, serviceURL: serviceURL)
        
        var cacheHitCount = 0
        var cacheMissCount = 0
        
        // Set up observability to track cache hits/misses
        DynamicPinning.setObservabilityHandler { event in
            switch event {
            case .cacheHit:
                cacheHitCount += 1
            case .cacheMiss:
                cacheMissCount += 1
            default:
                break
            }
        }
        
        // First request should miss cache
        let session1 = DynamicPinning.session()
        let requestURL = URL(string: "https://\(testDomain)")!
        let expectation1 = self.expectation(description: "First request")
        
        session1.dataTask(with: requestURL) { _, _, error in
            XCTAssertNil(error, "First request should succeed")
            // Give time for observability events to be processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation1.fulfill()
            }
        }.resume()
        
        wait(for: [expectation1], timeout: 30.0)
        
        // Second request should hit cache
        let session2 = DynamicPinning.session()
        let expectation2 = self.expectation(description: "Second request")
        
        session2.dataTask(with: requestURL) { _, _, error in
            XCTAssertNil(error, "Second request should succeed")
            // Give time for observability events to be processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation2.fulfill()
            }
        }.resume()
        
        wait(for: [expectation2], timeout: 30.0)
        
        // Verify cache behavior
        XCTAssertGreaterThan(cacheMissCount, 0, "Should have cache miss on first request")
        XCTAssertGreaterThan(cacheHitCount, 0, "Should have cache hit on second request")
    }
    
    func testObservabilityEvents() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let serviceURL = serviceURL,
              let publicKey = publicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Initialize SDK
        DynamicPinning.initialize(publicKey: publicKey, serviceURL: serviceURL)
        
        var events: [PinningEvent] = []
        let eventsQueue = DispatchQueue(label: "test.events")
        
        // Set up observability handler
        DynamicPinning.setObservabilityHandler { event in
            eventsQueue.sync {
                events.append(event)
            }
        }
        
        // Make request
        let session = DynamicPinning.session()
        let requestURL = URL(string: "https://\(testDomain)")!
        let expectation = self.expectation(description: "Request completed")
        
        session.dataTask(with: requestURL) { _, _, _ in
            // Give time for observability events to be processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation.fulfill()
            }
        }.resume()
        
        wait(for: [expectation], timeout: 30.0)
        
        // Verify events were emitted
        eventsQueue.sync {
            XCTAssertFalse(events.isEmpty, "Should have emitted events")
            
            // Should have either cache hit/miss
            let hasCacheEvent = events.contains { event in
                if case .cacheHit = event { return true }
                if case .cacheMiss = event { return true }
                return false
            }
            XCTAssertTrue(hasCacheEvent, "Should have cache event")
            
            // Should have success event (assuming valid certificate)
            let hasSuccess = events.contains { event in
                if case .success = event { return true }
                return false
            }
            XCTAssertTrue(hasSuccess, "Should have success event for valid certificate")
        }
    }
    
    // MARK: - Failure Scenarios
    
    func testInvalidDomainFails() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let serviceURL = serviceURL,
              let publicKey = publicKey else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Initialize SDK
        DynamicPinning.initialize(publicKey: publicKey, serviceURL: serviceURL)
        
        // Try to connect to a domain not allowed by the server
        let session = DynamicPinning.session()
        let invalidURL = URL(string: "https://invalid-domain-not-allowed.com")!
        let expectation = self.expectation(description: "Request should fail")
        
        var didFail = false
        
        session.dataTask(with: invalidURL) { _, _, error in
            didFail = (error != nil)
            expectation.fulfill()
        }.resume()
        
        wait(for: [expectation], timeout: 30.0)
        
        XCTAssertTrue(didFail, "Request to invalid domain should fail")
    }
    
    func testInvalidPublicKeyFails() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let serviceURL = serviceURL,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Use an invalid public key
        let invalidKey = "dGVzdF9pbnZhbGlkX2tleQ==" // Not a valid Ed25519 key
        
        DynamicPinning.initialize(publicKey: invalidKey, serviceURL: serviceURL)
        
        var failureReason: PinningFailureReason?
        
        // Set up observability to capture failure
        DynamicPinning.setObservabilityHandler { event in
            if case .failure(_, let reason) = event {
                failureReason = reason
            }
        }
        
        let session = DynamicPinning.session()
        let requestURL = URL(string: "https://\(testDomain)")!
        let expectation = self.expectation(description: "Request should fail")
        
        var didFail = false
        
        session.dataTask(with: requestURL) { _, _, error in
            didFail = (error != nil)
            // Give time for observability events to be processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation.fulfill()
            }
        }.resume()
        
        wait(for: [expectation], timeout: 30.0)
        
        XCTAssertTrue(didFail, "Request with invalid public key should fail")
        XCTAssertNotNil(failureReason, "Should capture failure reason")
    }
    
    // MARK: - Performance Tests
    
    func testPinningPerformance() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let serviceURL = serviceURL,
              let publicKey = publicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Initialize and warm up cache
        DynamicPinning.initialize(publicKey: publicKey, serviceURL: serviceURL)
        let session = DynamicPinning.session()
        let requestURL = URL(string: "https://\(testDomain)")!
        
        // Warm up
        let warmupExpectation = expectation(description: "Warmup")
        session.dataTask(with: requestURL) { _, _, _ in
            warmupExpectation.fulfill()
        }.resume()
        wait(for: [warmupExpectation], timeout: 30.0)
        
        // Measure cached request performance
        measure {
            let expectation = self.expectation(description: "Performance test")
            
            session.dataTask(with: requestURL) { _, _, _ in
                expectation.fulfill()
            }.resume()
            
            wait(for: [expectation], timeout: 10.0)
        }
    }
    
    // MARK: - Concurrent Requests
    
    func testConcurrentRequests() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let serviceURL = serviceURL,
              let publicKey = publicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        DynamicPinning.initialize(publicKey: publicKey, serviceURL: serviceURL)
        let session = DynamicPinning.session()
        let requestURL = URL(string: "https://\(testDomain)")!
        
        let concurrentCount = 10
        let expectations = (0..<concurrentCount).map { i in
            self.expectation(description: "Request \(i)")
        }
        
        var successCount = 0
        let successQueue = DispatchQueue(label: "test.success")
        
        // Launch concurrent requests
        for i in 0..<concurrentCount {
            session.dataTask(with: requestURL) { _, _, error in
                if error == nil {
                    successQueue.sync {
                        successCount += 1
                    }
                }
                expectations[i].fulfill()
            }.resume()
        }
        
        wait(for: expectations, timeout: 60.0)
        
        // All requests should succeed
        XCTAssertEqual(successCount, concurrentCount, "All concurrent requests should succeed")
    }
    
    // MARK: - Helper Tests
    
    func testServiceAvailability() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let serviceURL = serviceURL else {
            XCTFail("Service URL not configured")
            return
        }
        
        // Test that we can reach the service
        let expectation = self.expectation(description: "Service check")
        
        var isAvailable = false
        
        let task = URLSession.shared.dataTask(with: serviceURL) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                isAvailable = (httpResponse.statusCode == 200)
            }
            expectation.fulfill()
        }
        
        task.resume()
        wait(for: [expectation], timeout: 10.0)
        
        XCTAssertTrue(isAvailable, "Dynapins service should be available at \(serviceURL)")
    }
}

// MARK: - Test Utilities

@available(iOS 14.0, macOS 10.15, *)
extension PinningIntegrationTests {
    
    /// Helper to print test configuration
    func printTestConfiguration() {
        print("=== Integration Test Configuration ===")
        print("Service URL: \(serviceURL?.absoluteString ?? "NOT SET")")
        print("Test Domain: \(testDomain ?? "NOT SET")")
        print("Public Key: \(publicKey?.prefix(20) ?? "NOT SET")...")
        print("=====================================")
    }
}
