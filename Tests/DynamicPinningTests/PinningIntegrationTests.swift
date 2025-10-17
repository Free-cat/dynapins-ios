@testable import DynamicPinning
import XCTest

/// End-to-end integration tests for the complete pinning flow.
///
/// These tests require a running Dynapins backend server.
/// Set the following environment variables to run these tests:
/// - TEST_SERVICE_URL: URL of the Dynapins service (e.g., http://localhost:8080/v1/pins)
/// - TEST_PUBLIC_KEY: Base64-encoded ECDSA P-256 public key (SPKI format)
/// - TEST_DOMAIN: Domain to test (must be allowed in server's ALLOWED_DOMAINS)
///
/// Example:
/// ```bash
/// export TEST_SERVICE_URL="http://localhost:8080/v1/pins"
/// export TEST_PUBLIC_KEY="MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQ..."
/// export TEST_DOMAIN="api.example.com"
/// swift test --filter PinningIntegrationTests
/// ```
@available(iOS 14.0, macOS 10.15, *)
final class PinningIntegrationTests: XCTestCase {
    
    var pinningServiceURL: URL?
    var signingPublicKey: String?
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
        
        guard let url = URL(string: urlString) else {
            print("⚠️ Invalid TEST_SERVICE_URL")
            shouldSkipTests = true
            return
        }
        
        pinningServiceURL = url
        signingPublicKey = key
        testDomain = domain
        shouldSkipTests = false
    }
    
    override func tearDown() {
        #if DEBUG
        DynamicPinning.resetForTesting()
        #endif
        
        super.tearDown()
    }
    
    // MARK: - Basic Integration Tests
    
    func testEndToEndPinningFlow() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let pinningServiceURL = pinningServiceURL,
              let signingPublicKey = signingPublicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Step 1: Initialize SDK (async)
        let initExpectation = self.expectation(description: "SDK initialized")
        DynamicPinning.initialize(
            signingPublicKey: signingPublicKey,
            pinningServiceURL: pinningServiceURL,
            domains: [testDomain]
        ) { successCount, failureCount in
            NSLog("[Test] Init complete: \(successCount) succeeded, \(failureCount) failed")
            XCTAssertGreaterThan(successCount, 0, "At least one domain should fetch pins successfully")
            initExpectation.fulfill()
        }
        
        wait(for: [initExpectation], timeout: 30.0)
        
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
    
    func testRealHTTPSRequest() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let pinningServiceURL = pinningServiceURL,
              let signingPublicKey = signingPublicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Initialize SDK with TrustKit pinning (wait for completion)
        let initExpectation = self.expectation(description: "SDK initialized")
        DynamicPinning.initialize(
            signingPublicKey: signingPublicKey,
            pinningServiceURL: pinningServiceURL,
            domains: [testDomain]
        ) { successCount, _ in
            XCTAssertGreaterThan(successCount, 0, "At least one domain should fetch pins successfully")
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 30.0)
        
        // Get session - TrustKit is configured and will validate SSL
        let session = DynamicPinning.session()
        let requestURL = URL(string: "https://\(testDomain)")!
        let expectation = self.expectation(description: "HTTPS request")
        
        var requestError: Error?
        var httpStatusCode: Int?
        
        session.dataTask(with: requestURL) { _, response, error in
            requestError = error
            if let httpResponse = response as? HTTPURLResponse {
                httpStatusCode = httpResponse.statusCode
            }
            expectation.fulfill()
        }.resume()
        
        wait(for: [expectation], timeout: 30.0)
        
        // Verify request succeeded with valid SSL certificate
        XCTAssertNil(requestError, "HTTPS request should succeed with valid pinned certificate")
        XCTAssertNotNil(httpStatusCode, "Should receive HTTP response")
        
        NSLog("[Test] ✅ Real HTTPS request to \(testDomain) succeeded with TrustKit pinning")
    }
    
    func testCertificateRotationScenario() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let pinningServiceURL = pinningServiceURL,
              let signingPublicKey = signingPublicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Scenario: Simulate certificate rotation
        // 1. Initialize SDK with current pins (wait for completion)
        let initExpectation = self.expectation(description: "SDK initialized")
        DynamicPinning.initialize(
            signingPublicKey: signingPublicKey,
            pinningServiceURL: pinningServiceURL,
            domains: [testDomain]
        ) { successCount, _ in
            XCTAssertGreaterThan(successCount, 0)
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 30.0)
        
        // 2. Make first request - should succeed
        let session = DynamicPinning.session()
        let requestURL = URL(string: "https://\(testDomain)")!
        
        let firstExpectation = self.expectation(description: "First request")
        var firstSuccess = false
        
        session.dataTask(with: requestURL) { _, _, error in
            firstSuccess = (error == nil)
            firstExpectation.fulfill()
        }.resume()
        
        wait(for: [firstExpectation], timeout: 30.0)
        XCTAssertTrue(firstSuccess, "Initial request should succeed")
        
        // 3. Manually refresh pins (simulating app detecting stale pins or periodic refresh)
        NSLog("[Test] 🔄 Simulating pin refresh after certificate rotation...")
        
        let refreshExpectation = self.expectation(description: "Pin refresh")
        DynamicPinning.refreshPins { successCount, failureCount in
            NSLog("[Test] Refresh complete: \(successCount) succeeded, \(failureCount) failed")
            refreshExpectation.fulfill()
        }
        
        wait(for: [refreshExpectation], timeout: 30.0)
        
        // 4. Make another request with fresh pins - should still succeed
        let secondExpectation = self.expectation(description: "Second request after refresh")
        var secondSuccess = false
        
        session.dataTask(with: requestURL) { _, _, error in
            secondSuccess = (error == nil)
            secondExpectation.fulfill()
        }.resume()
        
        wait(for: [secondExpectation], timeout: 30.0)
        XCTAssertTrue(secondSuccess, "Request after pin refresh should succeed")
        
        NSLog("[Test] ✅ Certificate rotation scenario: pins refreshed without app restart")
    }
    
    func testBackupPinRotationScenario() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let pinningServiceURL = pinningServiceURL,
              let signingPublicKey = signingPublicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Initialize SDK with backup pins enabled (wait for completion)
        let initExpectation = self.expectation(description: "SDK initialized")
        DynamicPinning.initialize(
            signingPublicKey: signingPublicKey,
            pinningServiceURL: pinningServiceURL,
            domains: [testDomain],
            includeBackupPins: true
        ) { successCount, _ in
            XCTAssertGreaterThan(successCount, 0)
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 30.0)
        
        // Make a request - should succeed
        let session = DynamicPinning.session()
        let requestURL = URL(string: "https://\(testDomain)")!
        
        let expectation = self.expectation(description: "Request with backup pins")
        var success = false
        
        session.dataTask(with: requestURL) { _, _, error in
            success = (error == nil)
            expectation.fulfill()
        }.resume()
        
        wait(for: [expectation], timeout: 30.0)
        XCTAssertTrue(success, "Request with backup pins should succeed")
        
        NSLog("[Test] ✅ Backup pin scenario: request succeeded with primary and backup pins")
    }
    
    // MARK: - Failure Scenarios
    
    func testInvalidDomainFails() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let pinningServiceURL = pinningServiceURL,
              let signingPublicKey = signingPublicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Initialize SDK (wait for completion)
        let initExpectation = self.expectation(description: "SDK initialized")
        DynamicPinning.initialize(
            signingPublicKey: signingPublicKey,
            pinningServiceURL: pinningServiceURL,
            domains: [testDomain]
        ) { _, _ in
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 30.0)
        
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
        
        guard let pinningServiceURL = pinningServiceURL,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Use an invalid public key - SDK should fail to initialize or fetch pins
        let invalidKey = "dGVzdF9pbnZhbGlkX2tleQ==" // Not a valid ECDSA P-256 key
        
        // Initialize with invalid key - should fail to verify JWS (wait for completion)
        let initExpectation = self.expectation(description: "SDK initialized")
        DynamicPinning.initialize(
            signingPublicKey: invalidKey,
            pinningServiceURL: pinningServiceURL,
            domains: [testDomain]
        ) { successCount, failureCount in
            XCTAssertEqual(successCount, 0, "Should fail with invalid key")
            XCTAssertGreaterThan(failureCount, 0, "Should have failures")
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 30.0)
        
        // Even with invalid key, session() should work (but no pins configured)
        let session = DynamicPinning.session()
        XCTAssertNotNil(session, "Should still return a session")
        
        NSLog("[Test] Invalid public key test: SDK initialized but pins not configured")
    }
    
    // MARK: - Performance Tests
    
    func testPinningPerformance() throws {
        guard !shouldSkipTests else {
            throw XCTSkip("Integration tests skipped - environment not configured")
        }
        
        guard let pinningServiceURL = pinningServiceURL,
              let signingPublicKey = signingPublicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Initialize and warm up cache (wait for completion)
        let initExpectation = self.expectation(description: "SDK initialized")
        DynamicPinning.initialize(
            signingPublicKey: signingPublicKey,
            pinningServiceURL: pinningServiceURL,
            domains: [testDomain]
        ) { _, _ in
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 30.0)
        
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
        
        guard let pinningServiceURL = pinningServiceURL,
              let signingPublicKey = signingPublicKey,
              let testDomain = testDomain else {
            XCTFail("Test configuration missing")
            return
        }
        
        // Initialize SDK (wait for completion)
        let initExpectation = self.expectation(description: "SDK initialized")
        DynamicPinning.initialize(
            signingPublicKey: signingPublicKey,
            pinningServiceURL: pinningServiceURL,
            domains: [testDomain]
        ) { _, _ in
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 30.0)
        
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
    
}

// MARK: - Test Utilities

@available(iOS 14.0, macOS 10.15, *)
extension PinningIntegrationTests {
    
    /// Helper to print test configuration
    func printTestConfiguration() {
        print("=== Integration Test Configuration ===")
        print("Service URL: \(pinningServiceURL?.absoluteString ?? "NOT SET")")
        print("Test Domain: \(testDomain ?? "NOT SET")")
        print("Public Key: \(signingPublicKey?.prefix(20) ?? "NOT SET")...")
        print("=====================================")
    }
}
