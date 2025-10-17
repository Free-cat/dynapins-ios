import Foundation

/// A URLSession wrapper that automatically retries failed requests with fresh pins
/// when SSL validation fails due to certificate rotation.
///
/// This enables seamless certificate rotation without app restart.
///
/// **How it works**:
/// 1. URLSession delegate validates certificates using TrustKit
/// 2. If validation fails (pin mismatch), this session detects the error
/// 3. Pins are refreshed from the server
/// 4. Request is automatically retried once with updated pins
@available(iOS 14.0, macOS 10.15, *)
public class PinningURLSession {
    
    private let underlyingSession: URLSession
    private let queue = DispatchQueue(label: "com.dynapins.pinningsession", attributes: .concurrent)
    
    /// Track if we've already done a pin refresh for this request
    /// to prevent infinite retry loops (max 1 retry per request)
    private var retriedRequests = Set<String>()
    
    /// Pin refresh handler (injectable for testing)
    internal var pinRefreshHandler: ((@escaping (Int, Int) -> Void) -> Void)?
    
    init(session: URLSession) {
        self.underlyingSession = session
        self.pinRefreshHandler = nil
    }
    
    /// Creates a smart data task that automatically retries with fresh pins on SSL errors
    public func dataTask(with url: URL, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        return dataTask(with: URLRequest(url: url), completionHandler: completionHandler)
    }
    
    /// Creates a smart data task that automatically retries with fresh pins on SSL errors
    public func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        let requestID = requestIdentifier(for: request)
        
        return underlyingSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completionHandler(data, response, error)
                return
            }
            
            // Check if this is an SSL authentication challenge failure
            // When TrustKit delegate cancels authentication, we get NSURLErrorCancelled
            if let error = error as NSError?,
               error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled,
               !self.hasRetried(requestID) {
                
                NSLog("[DynamicPinning] 🔄 SSL validation failed, refreshing pins and retrying...")
                
                // Mark as retried to prevent loops
                self.markAsRetried(requestID)
                
                // Refresh pins and retry
                let refreshHandler = self.pinRefreshHandler ?? { completion in
                    DynamicPinning.refreshPins(completion: completion)
                }
                
                refreshHandler { successCount, _ in
                    guard successCount > 0 else {
                        NSLog("[DynamicPinning] ❌ Pin refresh failed, cannot retry")
                        completionHandler(data, response, error)
                        return
                    }
                    
                    NSLog("[DynamicPinning] 🔄 Retrying request with fresh pins...")
                    
                    // After pins are refreshed, retry the request
                    let retryTask = self.underlyingSession.dataTask(with: request) { retryData, retryResponse, retryError in
                        if let retryError = retryError {
                            NSLog("[DynamicPinning] ❌ Retry failed: \(retryError.localizedDescription)")
                        } else {
                            NSLog("[DynamicPinning] ✅ Retry succeeded with fresh pins")
                        }
                        completionHandler(retryData, retryResponse, retryError)
                    }
                    retryTask.resume()
                }
                return
            }
            
            // Not an SSL error or already retried - pass through
            completionHandler(data, response, error)
        }
    }
    
    /// Generate a unique identifier for a request
    private func requestIdentifier(for request: URLRequest) -> String {
        let urlString = request.url?.absoluteString ?? ""
        let method = request.httpMethod ?? "GET"
        return "\(method):\(urlString)"
    }
    
    /// Check if we've already retried this request
    private func hasRetried(_ requestID: String) -> Bool {
        return queue.sync { retriedRequests.contains(requestID) }
    }
    
    /// Mark a request as retried
    private func markAsRetried(_ requestID: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.retriedRequests.insert(requestID)
        }
    }
    
    /// Reset retry tracking (useful for testing)
    internal func resetRetryTracking() {
        queue.async(flags: .barrier) { [weak self] in
            self?.retriedRequests.removeAll()
        }
    }
}
