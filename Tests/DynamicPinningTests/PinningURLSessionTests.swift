@testable import DynamicPinning
import XCTest

/// Tests for PinningURLSession retry logic.
@available(iOS 14.0, macOS 10.15, *)
final class PinningURLSessionTests: XCTestCase {
    
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
    
    // MARK: - Retry Logic Tests
    
    func testRetryOnSSLCancellationError() {
        // Given - Mock URLSession and pin refresh
        var requestCount = 0
        MockRetryURLProtocol.requestHandler = { request in
            requestCount += 1
            
            if requestCount == 1 {
                // First request: SSL cancellation error
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
            } else {
                // Second request (after retry): Success
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                let data = "{\"success\":true}".data(using: .utf8)!
                return (response, data)
            }
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRetryURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let pinningSession = PinningURLSession(session: mockSession)
        
        // Mock pin refresh (always succeeds)
        pinningSession.pinRefreshHandler = { completion in
            completion(1, 0) // 1 success, 0 failures
        }
        
        // When - Make a request that will fail then retry
        let requestExpectation = self.expectation(description: "Request completed")
        var finalError: Error?
        var finalData: Data?
        var finalResponse: URLResponse?
        
        let task = pinningSession.dataTask(with: URL(string: "https://test.com/api")!) { data, response, error in
            finalData = data
            finalResponse = response
            finalError = error
            requestExpectation.fulfill()
        }
        
        task.resume()
        
        // Then - Should succeed after retry
        wait(for: [requestExpectation], timeout: 5.0)
        
        XCTAssertNil(finalError, "Final error should be nil after successful retry")
        XCTAssertNotNil(finalData, "Should have data after retry")
        XCTAssertEqual(requestCount, 2, "Should have made exactly 2 requests (original + 1 retry)")
        
        if let httpResponse = finalResponse as? HTTPURLResponse {
            XCTAssertEqual(httpResponse.statusCode, 200, "Final response should be successful")
        }
    }
    
    func testNoRetryOnNonSSLError() {
        // Given - Mock URLSession with non-SSL error
        var requestCount = 0
        MockRetryURLProtocol.requestHandler = { _ in
            requestCount += 1
            // Network error (not SSL)
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRetryURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let pinningSession = PinningURLSession(session: mockSession)
        
        // When - Make a request that fails with non-SSL error
        let requestExpectation = self.expectation(description: "Request completed")
        var finalError: Error?
        
        let task = pinningSession.dataTask(with: URL(string: "https://test.com/api")!) { _, _, error in
            finalError = error
            requestExpectation.fulfill()
        }
        
        task.resume()
        
        // Then - Should NOT retry
        wait(for: [requestExpectation], timeout: 2.0)
        
        XCTAssertNotNil(finalError, "Should have error")
        XCTAssertEqual(requestCount, 1, "Should have made only 1 request (no retry for non-SSL errors)")
        
        let nsError = finalError as NSError?
        XCTAssertEqual(nsError?.code, NSURLErrorNotConnectedToInternet)
    }
    
    func testNoDoubleRetry() {
        // Given - Mock to fail twice with SSL error
        var requestCount = 0
        MockRetryURLProtocol.requestHandler = { _ in
            requestCount += 1
            // Always fail with SSL cancellation
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRetryURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let pinningSession = PinningURLSession(session: mockSession)
        
        // Mock pin refresh (always succeeds)
        pinningSession.pinRefreshHandler = { completion in
            completion(1, 0)
        }
        
        // When - Make a request that will fail twice
        let requestExpectation = self.expectation(description: "Request completed")
        var finalError: Error?
        
        let task = pinningSession.dataTask(with: URL(string: "https://test.com/api")!) { _, _, error in
            finalError = error
            requestExpectation.fulfill()
        }
        
        task.resume()
        
        // Then - Should retry only once (max 2 attempts total)
        wait(for: [requestExpectation], timeout: 5.0)
        
        XCTAssertNotNil(finalError, "Should have error after retry also fails")
        XCTAssertEqual(requestCount, 2, "Should have made exactly 2 requests (original + 1 retry, no infinite loop)")
    }
    
    func testSuccessfulRequestDoesNotTriggerRetry() {
        // Given - Mock to always succeed
        var requestCount = 0
        MockRetryURLProtocol.requestHandler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = "{\"success\":true}".data(using: .utf8)!
            return (response, data)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRetryURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let pinningSession = PinningURLSession(session: mockSession)
        
        // When - Make a successful request
        let requestExpectation = self.expectation(description: "Request completed")
        var finalError: Error?
        
        let task = pinningSession.dataTask(with: URL(string: "https://test.com/api")!) { _, _, error in
            finalError = error
            requestExpectation.fulfill()
        }
        
        task.resume()
        
        // Then - Should NOT retry
        wait(for: [requestExpectation], timeout: 2.0)
        
        XCTAssertNil(finalError, "Should not have error")
        XCTAssertEqual(requestCount, 1, "Should have made only 1 request (no retry on success)")
    }
    
    func testRetryOnlyIfPinRefreshSucceeds() {
        // Given - Mock to fail with SSL error
        var requestCount = 0
        MockRetryURLProtocol.requestHandler = { _ in
            requestCount += 1
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRetryURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let pinningSession = PinningURLSession(session: mockSession)
        
        // Mock pin refresh (fails - 0 successes)
        pinningSession.pinRefreshHandler = { completion in
            completion(0, 1) // 0 success, 1 failure
        }
        
        // When - Make request that triggers retry
        let requestExpectation = self.expectation(description: "Request completed")
        var finalError: Error?
        
        let task = pinningSession.dataTask(with: URL(string: "https://test.com/api")!) { _, _, error in
            finalError = error
            requestExpectation.fulfill()
        }
        
        task.resume()
        
        // Then - Should NOT retry if pin refresh failed
        wait(for: [requestExpectation], timeout: 2.0)
        
        XCTAssertNotNil(finalError, "Should have error")
        XCTAssertEqual(requestCount, 1, "Should have made only 1 request (no retry when pin refresh fails)")
    }
    
    func testRetryResetsForDifferentRequests() {
        // Given - Mock setup for two different URLs
        var request1Count = 0
        var request2Count = 0
        
        MockRetryURLProtocol.requestHandler = { request in
            if request.url?.path.contains("/api1") == true {
                request1Count += 1
                if request1Count == 1 {
                    throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
                } else {
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (response, "API1 success".data(using: .utf8)!)
                }
            } else {
                request2Count += 1
                if request2Count == 1 {
                    throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
                } else {
                    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                    return (response, "API2 success".data(using: .utf8)!)
                }
            }
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRetryURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let pinningSession = PinningURLSession(session: mockSession)
        
        // Mock pin refresh (always succeeds)
        pinningSession.pinRefreshHandler = { completion in
            completion(1, 0)
        }
        
        // When - Make two different requests
        let expectation1 = self.expectation(description: "Request 1 completed")
        let expectation2 = self.expectation(description: "Request 2 completed")
        
        pinningSession.dataTask(with: URL(string: "https://test.com/api1")!) { _, _, error in
            XCTAssertNil(error, "Request 1 should succeed after retry")
            expectation1.fulfill()
        }.resume()
        
        pinningSession.dataTask(with: URL(string: "https://test.com/api2")!) { _, _, error in
            XCTAssertNil(error, "Request 2 should succeed after retry")
            expectation2.fulfill()
        }.resume()
        
        // Then - Both should retry successfully
        wait(for: [expectation1, expectation2], timeout: 5.0)
        
        XCTAssertEqual(request1Count, 2, "Request 1 should have retried")
        XCTAssertEqual(request2Count, 2, "Request 2 should have retried (retry tracking is per-request)")
    }
    
    func testResetRetryTracking() {
        // Given - Mock to fail with SSL error
        var requestCount = 0
        MockRetryURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount <= 2 {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
            } else {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, "success".data(using: .utf8)!)
            }
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockRetryURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        let pinningSession = PinningURLSession(session: mockSession)
        
        // Mock pin refresh
        pinningSession.pinRefreshHandler = { completion in
            completion(1, 0)
        }
        
        // When - Make first request (will fail twice)
        let expectation1 = self.expectation(description: "First request")
        pinningSession.dataTask(with: URL(string: "https://test.com/api")!) { _, _, error in
            XCTAssertNotNil(error, "Should fail after max retries")
            expectation1.fulfill()
        }.resume()
        
        wait(for: [expectation1], timeout: 3.0)
        XCTAssertEqual(requestCount, 2, "Should have tried twice")
        
        // Reset retry tracking
        pinningSession.resetRetryTracking()
        
        // Make second request to same URL (should be able to retry again)
        let expectation2 = self.expectation(description: "Second request")
        pinningSession.dataTask(with: URL(string: "https://test.com/api")!) { _, _, error in
            XCTAssertNil(error, "Should succeed after reset")
            expectation2.fulfill()
        }.resume()
        
        // Then
        wait(for: [expectation2], timeout: 3.0)
        XCTAssertEqual(requestCount, 3, "Should have made one more request after reset")
    }
}

// MARK: - Mock URLProtocol for Retry Tests

class MockRetryURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockRetryURLProtocol.requestHandler else {
            fatalError("Handler is unavailable.")
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {
        // Required override
    }
}
