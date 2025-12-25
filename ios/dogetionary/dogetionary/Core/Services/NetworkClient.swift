//
//  NetworkClient.swift
//  dogetionary
//
//  Centralized network client that handles:
//  - Automatic X-Request-ID header injection for all requests
//  - Debug logging to NetworkLogger (only in developer mode)
//  - Consistent API for data tasks, download tasks, and async/await
//

import Foundation
import os.log

/// Centralized network client - single source of truth for all HTTP requests
class NetworkClient {
    static let shared = NetworkClient()

    private let logger = Logger(subsystem: "com.dogetionary", category: "NetworkClient")
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0     // 10 seconds for request timeout
        config.timeoutIntervalForResource = 10.0    // 10 seconds for total resource timeout
        return URLSession(configuration: config)
    }()

    private init() {
        logger.info("NetworkClient initialized with 10s timeout")
    }

    // MARK: - Data Task (Completion Handler)

    /// Create a data task with automatic request ID and logging
    /// - Parameters:
    ///   - url: The URL to request
    ///   - method: HTTP method (default: GET)
    ///   - headers: Optional additional headers
    ///   - body: Optional request body
    ///   - completion: Completion handler with data, response, and error
    /// - Returns: URLSessionDataTask that can be resumed
    func dataTask(
        url: URL,
        method: String = "GET",
        headers: [String: String]? = nil,
        body: Data? = nil,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        // Build request with automatic request ID
        let (request, requestId, startTime) = buildRequest(
            url: url,
            method: method,
            headers: headers,
            body: body
        )

        // Create task
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            // Log response (only in dev mode)
            self?.logResponse(
                requestId: requestId,
                status: (response as? HTTPURLResponse)?.statusCode,
                data: data,
                headers: (response as? HTTPURLResponse)?.allHeaderFields,
                error: error,
                startTime: startTime
            )

            // Call completion handler
            completion(data, response, error)
        }

        return task
    }

    // MARK: - Data Task (Async/Await)

    /// Async version of dataTask for modern Swift concurrency
    /// - Parameters:
    ///   - url: The URL to request
    ///   - method: HTTP method (default: GET)
    ///   - headers: Optional additional headers
    ///   - body: Optional request body
    /// - Returns: Tuple of (Data, URLResponse)
    /// - Throws: Error if request fails
    func data(
        from url: URL,
        method: String = "GET",
        headers: [String: String]? = nil,
        body: Data? = nil
    ) async throws -> (Data, URLResponse) {
        // Build request with automatic request ID
        let (request, requestId, startTime) = buildRequest(
            url: url,
            method: method,
            headers: headers,
            body: body
        )

        // Execute async request
        let (data, response) = try await session.data(for: request)

        // Log response (only in dev mode)
        logResponse(
            requestId: requestId,
            status: (response as? HTTPURLResponse)?.statusCode,
            data: data,
            headers: (response as? HTTPURLResponse)?.allHeaderFields,
            error: nil,
            startTime: startTime
        )

        return (data, response)
    }

    // MARK: - Download Task

    /// Create a download task with automatic request ID and logging
    /// - Parameters:
    ///   - url: The URL to download from
    ///   - headers: Optional additional headers
    ///   - completion: Completion handler with temp file location, response, and error
    /// - Returns: URLSessionDownloadTask that can be resumed
    func downloadTask(
        url: URL,
        headers: [String: String]? = nil,
        completion: @escaping (URL?, URLResponse?, Error?) -> Void
    ) -> URLSessionDownloadTask {
        // Build request with automatic request ID
        let (request, requestId, startTime) = buildRequest(
            url: url,
            method: "GET",
            headers: headers,
            body: nil
        )

        // Create download task
        let task = session.downloadTask(with: request) { [weak self] location, response, error in
            // Log response (only in dev mode)
            // For downloads, data is nil (saved to file)
            self?.logResponse(
                requestId: requestId,
                status: (response as? HTTPURLResponse)?.statusCode,
                data: nil,
                headers: (response as? HTTPURLResponse)?.allHeaderFields,
                error: error,
                startTime: startTime
            )

            // Call completion handler
            completion(location, response, error)
        }

        return task
    }

    // MARK: - Helper Methods

    /// Build URLRequest with automatic X-Request-ID header and logging
    /// Returns (request, requestId, startTime) for correlation
    private func buildRequest(
        url: URL,
        method: String,
        headers: [String: String]?,
        body: Data?
    ) -> (URLRequest, String, Date) {
        var request = URLRequest(url: url)
        request.httpMethod = method

        // Add custom headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Add body if present
        if let body = body {
            request.httpBody = body
        }

        // Generate and add X-Request-ID header
        let requestId = UUID().uuidString
        request.setValue(requestId, forHTTPHeaderField: "X-Request-ID")

        // Record start time for duration calculation
        let startTime = Date()

        // Log request (only in dev mode)
        logRequest(
            url: url.absoluteString,
            method: method,
            body: body,
            requestId: requestId
        )

        return (request, requestId, startTime)
    }

    /// Log request to NetworkLogger (only in developer mode)
    private func logRequest(url: String, method: String, body: Data?, requestId: String) {
        guard DebugConfig.isDeveloperModeEnabled else { return }

        let _ = NetworkLogger.shared.logRequest(
            url: url,
            method: method,
            body: body,
            requestId: requestId
        )
    }

    /// Log response to NetworkLogger (only in developer mode)
    private func logResponse(
        requestId: String,
        status: Int?,
        data: Data?,
        headers: [AnyHashable: Any]?,
        error: Error?,
        startTime: Date
    ) {
        guard DebugConfig.isDeveloperModeEnabled else { return }

        NetworkLogger.shared.logResponse(
            id: requestId,
            status: status,
            data: data,
            headers: headers,
            error: error,
            startTime: startTime
        )
    }
}
