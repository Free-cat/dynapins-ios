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
    }
    
    /// Response from the fingerprint service
    struct FingerprintResponse: Codable {
        /// The domain pattern this fingerprint applies to (e.g., "*.example.com")
        let domain: String
        
        /// Array of SHA-256 hashes of the certificate's public keys (hex-encoded)
        let pins: [String]
        
        /// ISO8601 creation timestamp
        let created: String?
        
        /// ISO8601 expiration timestamp
        let expires: String?
        
        /// Time-to-live in seconds for this fingerprint
        let ttlSeconds: Int
        
        /// Key ID for the signing key
        let keyId: String?
        
        /// Algorithm used for signing (Ed25519)
        let alg: String?
        
        /// The Ed25519 signature (Base64-encoded)
        let signature: String
        
        /// Computed property for backwards compatibility
        var fingerprint: String {
            // Return the first pin from the array
            pins.first ?? ""
        }
        
        /// Computed property for backwards compatibility
        var ttl: Int {
            ttlSeconds
        }
        
        private enum CodingKeys: String, CodingKey {
            case domain
            case pins
            case created
            case expires
            case ttlSeconds = "ttl_seconds"
            case keyId
            case alg
            case signature
        }
    }
    
    private let serviceURL: URL
    
    /// Creates a new network service instance.
    ///
    /// - Parameter serviceURL: The base URL of the Dynapins service
    init(serviceURL: URL) {
        self.serviceURL = serviceURL
    }
    
    /// Fetches a signed certificate fingerprint from the Dynapins service.
    ///
    /// - Parameter completion: Completion handler called with the result
    func fetchFingerprint(completion: @escaping (Result<FingerprintResponse, NetworkError>) -> Void) {
        // Create the request
        var request = URLRequest(url: serviceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Create a URLSession without our custom delegate to avoid circular pinning
        let session = URLSession(configuration: .default)
        
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
                completion(.success(fingerprintResponse))
            } catch {
                completion(.failure(.decodingFailed(error)))
            }
        }
        
        task.resume()
    }
    
    /// Fetches a fingerprint synchronously using a semaphore.
    ///
    /// - Returns: The fingerprint response
    /// - Throws: `NetworkError` if the operation fails
    ///
    /// - Warning: This method blocks the current thread. Use with caution.
    func fetchFingerprintSync() throws -> FingerprintResponse {
        var result: Result<FingerprintResponse, NetworkError>?
        let semaphore = DispatchSemaphore(value: 0)
        
        fetchFingerprint { response in
            result = response
            semaphore.signal()
        }
        
        semaphore.wait()
        
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        case .none:
            throw NetworkError.invalidResponse
        }
    }
}

