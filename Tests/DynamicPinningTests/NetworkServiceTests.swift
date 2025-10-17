@testable import DynamicPinning
import XCTest

/// Tests for the NetworkService class.
@available(iOS 14.0, macOS 10.15, *)
final class NetworkServiceTests: XCTestCase {
    
    var networkService: NetworkService?
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
    
    // MARK: - Response Decoding Tests (JWS Format)
    
    func testJWSResponseDecoding() throws {
        // Given
        let json = """
        {
            "jws": "eyJhbGciOiJFZERTQSIsImtpZCI6IjdmZGE0YzFlIn0.eyJkb21haW4iOiJleGFtcGxlLmNvbSIsInBpbnMiOlsiODhjMzI5Li4uIl0sImlhdCI6MTczNDQ0MTYwMCwiZXhwIjoxNzM0NDQ1MjAwLCJ0dGxfc2Vjb25kcyI6MzYwMH0.SIGNATURE_BYTES"
        }
        """
        let jsonData = json.data(using: .utf8) ?? Data()
        
        // When
        let decoder = JSONDecoder()
        let response = try decoder.decode(NetworkService.FingerprintResponse.self, from: jsonData)
        
        // Then
        XCTAssertNotNil(response.jws)
        XCTAssertTrue(response.jws.contains("."))
    }
    
    // MARK: - Network Request Tests
    
    func testFetchFingerprintSuccess() {
        // Given
        let expectation = self.expectation(description: "Fetch fingerprint")
        let mockJWS = "eyJhbGciOiJFZERTQSIsImtpZCI6InRlc3QifQ.eyJkb21haW4iOiJleGFtcGxlLmNvbSIsInBpbnMiOlsiYWJjMTIzIl0sImlhdCI6MTcwMDAwMDAwMCwiZXhwIjoxNzAwMDAzNjAwLCJ0dGxfc2Vjb25kcyI6MzYwMH0.c2lnbmF0dXJl"
        let mockResponse = """
        {"jws": "\(mockJWS)"}
        """
        
        // Setup mock
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(mockResponse.utf8))
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // When
        let service = NetworkService(serviceURL: testServiceURL, session: mockSession)
        service.fetchFingerprint(forDomain: "example.com", includeBackupPins: false) { result in
            // Then
            switch result {
            case .success(let jwsToken):
                XCTAssertEqual(jwsToken, mockJWS)
            case .failure(let error):
                XCTFail("Expected success, got error: \(error)")
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testFetchFingerprintNetworkError() {
        // Given
        let expectation = self.expectation(description: "Network error")
        
        MockURLProtocol.requestHandler = { _ in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // When
        let service = NetworkService(serviceURL: testServiceURL, session: mockSession)
        service.fetchFingerprint(forDomain: "example.com", includeBackupPins: false) { result in
            // Then
            switch result {
            case .success:
                XCTFail("Expected error, got success")
            case .failure(let error):
                guard case .networkFailure = error else {
                    XCTFail("Expected networkFailure, got \(error)")
                    return
                }
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testFetchFingerprintInvalidStatusCode() {
        // Given
        let expectation = self.expectation(description: "Invalid status code")
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // When
        let service = NetworkService(serviceURL: testServiceURL, session: mockSession)
        service.fetchFingerprint(forDomain: "example.com", includeBackupPins: false) { result in
            // Then
            switch result {
            case .success:
                XCTFail("Expected error, got success")
            case .failure(let error):
                guard case .invalidStatusCode(let code) = error else {
                    XCTFail("Expected invalidStatusCode, got \(error)")
                    return
                }
                XCTAssertEqual(code, 404)
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testFetchFingerprintInvalidJSON() {
        // Given
        let expectation = self.expectation(description: "Invalid JSON")
        let invalidJSON = "not valid json"
        
        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(invalidJSON.utf8))
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // When
        let service = NetworkService(serviceURL: testServiceURL, session: mockSession)
        service.fetchFingerprint(forDomain: "example.com", includeBackupPins: false) { result in
            // Then
            switch result {
            case .success:
                XCTFail("Expected error, got success")
            case .failure(let error):
                guard case .decodingFailed = error else {
                    XCTFail("Expected decodingFailed, got \(error)")
                    return
                }
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
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
    
    // MARK: - Query Parameters Tests
    
    func testFetchFingerprintIncludesDomainQueryParameter() {
        // Given
        let expectation = self.expectation(description: "Request includes domain param")
        var capturedRequest: URLRequest?
        
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            
            guard let url = request.url else {
                throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let mockJWS = "eyJhbGciOiJFUzI1NiJ9.eyJkb21haW4iOiJhcGkuZXhhbXBsZS5jb20iLCJwaW5zIjpbImFiYzEyMyJdLCJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MTcwMDAzNjAwLCJ0dGxfc2Vjb25kcyI6MzYwMH0.c2lnbmF0dXJl"
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("{\"jws\":\"\(mockJWS)\"}".utf8)
            return (response, data)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // When
        let service = NetworkService(serviceURL: testServiceURL, session: mockSession)
        service.fetchFingerprint(forDomain: "api.example.com", includeBackupPins: false) { _ in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertNotNil(capturedRequest)
        guard let request = capturedRequest, let url = request.url else {
            XCTFail("Request or URL is nil")
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let domainParam = components?.queryItems?.first { $0.name == "domain" }
        
        XCTAssertNotNil(domainParam, "Should include 'domain' query parameter")
        XCTAssertEqual(domainParam?.value, "api.example.com")
    }
    
    func testFetchFingerprintIncludesBackupPinsParameter() {
        // Given
        let expectation = self.expectation(description: "Request includes backup pins param")
        var capturedRequest: URLRequest?
        
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            
            guard let url = request.url else {
                throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let mockJWS = "eyJhbGciOiJFUzI1NiJ9.eyJkb21haW4iOiJleGFtcGxlLmNvbSIsInBpbnMiOlsiYWJjMTIzIiwiZGVmNDU2Il0sImlhdCI6MTcwMDAwMDAwMCwiZXhwIjoxNzAwMDM2MDAsInR0bF9zZWNvbmRzIjozNjAwfQ.c2lnbmF0dXJl"
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("{\"jws\":\"\(mockJWS)\"}".utf8)
            return (response, data)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // When - Request with includeBackupPins = true
        let service = NetworkService(serviceURL: testServiceURL, session: mockSession)
        service.fetchFingerprint(forDomain: "example.com", includeBackupPins: true) { _ in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertNotNil(capturedRequest)
        guard let request = capturedRequest, let url = request.url else {
            XCTFail("Request or URL is nil")
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let backupParam = components?.queryItems?.first { $0.name == "include-backup-pins" }
        
        XCTAssertNotNil(backupParam, "Should include 'include-backup-pins' query parameter")
        XCTAssertEqual(backupParam?.value, "true")
    }
    
    func testFetchFingerprintWithoutBackupPinsParameter() {
        // Given
        let expectation = self.expectation(description: "Request without backup pins param")
        var capturedRequest: URLRequest?
        
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            
            guard let url = request.url else {
                throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let mockJWS = "eyJhbGciOiJFUzI1NiJ9.eyJkb21haW4iOiJleGFtcGxlLmNvbSIsInBpbnMiOlsiYWJjMTIzIl0sImlhdCI6MTcwMDAwMDAwMCwiZXhwIjoxNzAwMDM2MDAsInR0bF9zZWNvbmRzIjozNjAwfQ.c2lnbmF0dXJl"
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("{\"jws\":\"\(mockJWS)\"}".utf8)
            return (response, data)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // When - Request with includeBackupPins = false (default)
        let service = NetworkService(serviceURL: testServiceURL, session: mockSession)
        service.fetchFingerprint(forDomain: "example.com", includeBackupPins: false) { _ in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertNotNil(capturedRequest)
        guard let request = capturedRequest, let url = request.url else {
            XCTFail("Request or URL is nil")
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let backupParam = components?.queryItems?.first { $0.name == "include-backup-pins" }
        
        XCTAssertNil(backupParam, "Should NOT include 'include-backup-pins' when false")
    }
    
    // MARK: - HTTP Headers Tests
    
    func testFetchFingerprintIncludesAcceptHeader() {
        // Given
        let expectation = self.expectation(description: "Request includes Accept header")
        var capturedRequest: URLRequest?
        
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            
            guard let url = request.url else {
                throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let mockJWS = "eyJhbGciOiJFUzI1NiJ9.eyJkb21haW4iOiJleGFtcGxlLmNvbSIsInBpbnMiOlsiYWJjMTIzIl0sImlhdCI6MTcwMDAwMDAwMCwiZXhwIjoxNzAwMDM2MDAsInR0bF9zZWNvbmRzIjozNjAwfQ.c2lnbmF0dXJl"
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("{\"jws\":\"\(mockJWS)\"}".utf8)
            return (response, data)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // When
        let service = NetworkService(serviceURL: testServiceURL, session: mockSession)
        service.fetchFingerprint(forDomain: "example.com", includeBackupPins: false) { _ in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertNotNil(capturedRequest)
        let acceptHeader = capturedRequest?.value(forHTTPHeaderField: "Accept")
        XCTAssertEqual(acceptHeader, "application/json", "Should include Accept: application/json header")
    }
    
    func testFetchFingerprintUsesGETMethod() {
        // Given
        let expectation = self.expectation(description: "Request uses GET method")
        var capturedRequest: URLRequest?
        
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            
            guard let url = request.url else {
                throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let mockJWS = "eyJhbGciOiJFUzI1NiJ9.eyJkb21haW4iOiJleGFtcGxlLmNvbSIsInBpbnMiOlsiYWJjMTIzIl0sImlhdCI6MTcwMDAwMDAwMCwiZXhwIjoxNzAwMDM2MDAsInR0bF9zZWNvbmRzIjozNjAwfQ.c2lnbmF0dXJl"
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("{\"jws\":\"\(mockJWS)\"}".utf8)
            return (response, data)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // When
        let service = NetworkService(serviceURL: testServiceURL, session: mockSession)
        service.fetchFingerprint(forDomain: "example.com", includeBackupPins: false) { _ in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.httpMethod, "GET", "Should use GET method")
    }
    
    func testFetchFingerprintHasTimeout() {
        // Given
        let expectation = self.expectation(description: "Request has timeout")
        var capturedRequest: URLRequest?
        
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            
            guard let url = request.url else {
                throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            let mockJWS = "eyJhbGciOiJFUzI1NiJ9.eyJkb21haW4iOiJleGFtcGxlLmNvbSIsInBpbnMiOlsiYWJjMTIzIl0sImlhdCI6MTcwMDAwMDAwMCwiZXhwIjoxNzAwMDM2MDAsInR0bF9zZWNvbmRzIjozNjAwfQ.c2lnbmF0dXJl"
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("{\"jws\":\"\(mockJWS)\"}".utf8)
            return (response, data)
        }
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let mockSession = URLSession(configuration: config)
        
        // When
        let service = NetworkService(serviceURL: testServiceURL, session: mockSession)
        service.fetchFingerprint(forDomain: "example.com", includeBackupPins: false) { _ in
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.timeoutInterval, 10, "Should have 10 second timeout")
    }
}

// MARK: - Mock URLProtocol

class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
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
