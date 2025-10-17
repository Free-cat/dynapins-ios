import Foundation

/// Service for fetching certificate fingerprints from the Dynapins backend.
internal final class NetworkService {
    
    /// Errors that can occur during network operations
    enum NetworkError: Error {
        case invalidURL
        case networkFailure(Error)
        case invalidResponse
        case invalidStatusCode(Int)
        case decodingFailed(Error)
        case unknown
    }
    
    /// Response from the fingerprint service (JWS format)
    struct FingerprintResponse: Codable {
        /// The JWS token containing the signed pin data
        let jws: String
    }
    
    /// Decoded fingerprint data from JWS payload
    struct FingerprintData {
        /// The domain pattern this fingerprint applies to (e.g., "*.example.com")
        let domain: String
        
        /// Array of SHA-256 hashes of the certificate's public keys (hex-encoded)
        let pins: [String]
        
        /// Issued at timestamp (Unix epoch seconds)
        let iat: Int
        
        /// Expiration timestamp (Unix epoch seconds)
        let exp: Int
        
        /// Time-to-live in seconds for this fingerprint
        let ttlSeconds: Int
        
        /// Computed property for backwards compatibility
        var fingerprint: String {
            // Return the first pin from the array
            pins.first ?? ""
        }
        
        /// Computed property for backwards compatibility
        var ttl: Int {
            ttlSeconds
        }
    }
    
    private let serviceURL: URL
    private let session: URLSession
    
    /// Creates a new network service instance.
    ///
    /// - Parameters:
    ///   - serviceURL: The base URL of the Dynapins service
    ///   - session: Optional URLSession for testing (defaults to ephemeral session)
    init(serviceURL: URL, session: URLSession? = nil) {
        self.serviceURL = serviceURL
        self.session = session ?? URLSession(configuration: .default)
    }
    
    /// Fetches a signed certificate fingerprint from the Dynapins service.
    ///
    /// - Parameters:
    ///   - forDomain: The domain to fetch fingerprint for (optional, if URL already includes it)
    ///   - completion: Completion handler called with the result
    func fetchFingerprint(
        forDomain domain: String,
        includeBackupPins: Bool,
        completion: @escaping (Result<String, NetworkError>) -> Void
    ) {
        // Construct the URL with the domain query parameter
        var components = URLComponents(url: serviceURL, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "domain", value: domain)]

        if includeBackupPins {
            queryItems.append(URLQueryItem(name: "include-backup-pins", value: "true"))
        }

        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            completion(.failure(.invalidURL))
            return
        }
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = session.dataTask(with: request) { data, response, error in
            // Check for network errors
            if let error = error {
                completion(.failure(.networkFailure(error)))
                return
            }
            
            // Check for valid HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            
            // Check status code
            guard httpResponse.statusCode == 200 else {
                completion(.failure(.invalidStatusCode(httpResponse.statusCode)))
                return
            }
            
            // Check for data
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            // Decode the response
            do {
                let decoder = JSONDecoder()
                let fingerprintResponse = try decoder.decode(FingerprintResponse.self, from: data)
                completion(.success(fingerprintResponse.jws))
            } catch {
                completion(.failure(.decodingFailed(error)))
            }
        }
        
        task.resume()
    }
}

// MARK: - Synchronous Fetching for Simpler Test Code

@available(iOS 14.0, macOS 10.15, *)
extension NetworkService {
    /// Synchronous wrapper for `fetchFingerprint` for easier testing.
    internal func fetchFingerprintSync(
        forDomain domain: String,
        includeBackupPins: Bool
    ) throws -> String {
        var result: Result<String, NetworkError>!
        let semaphore = DispatchSemaphore(value: 0)

        fetchFingerprint(forDomain: domain, includeBackupPins: includeBackupPins) { response in
            result = response
            semaphore.signal()
        }

        semaphore.wait()
        
        switch result {
        case .success(let jwsToken):
            return jwsToken
        case .failure(let error):
            throw error
        case .none:
            throw NetworkError.unknown
        }
    }
}
