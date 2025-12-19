//
//  NetworkInterceptor.swift
//  dogetionary
//
//  URLProtocol subclass that intercepts ALL network requests for debug logging
//  Automatically captures requests made via URLSession.shared without code changes
//

import Foundation
import os.log

/// Custom URLProtocol that intercepts all HTTP/HTTPS requests for debug logging
class NetworkInterceptor: URLProtocol {
    private static let logger = Logger(subsystem: "com.dogetionary", category: "NetworkInterceptor")

    // Thread-safe storage for request metadata
    private struct RequestMetadata {
        let logId: UUID
        let startTime: Date
    }

    private static var requestMetadata: [URLRequest: RequestMetadata] = [:]
    private static let metadataQueue = DispatchQueue(label: "com.dogetionary.networkinterceptor.metadata")

    // MARK: - URLProtocol Overrides

    /// Determines if this protocol can handle the given request
    override class func canInit(with request: URLRequest) -> Bool {
        // Only intercept if debug mode is enabled
        guard DebugConfig.isDeveloperModeEnabled else {
            return false
        }

        // Only intercept HTTP/HTTPS requests
        guard let url = request.url,
              let scheme = url.scheme,
              scheme == "http" || scheme == "https" else {
            return false
        }

        // Avoid intercepting the same request multiple times
        // Check if we've already processed this request
        if URLProtocol.property(forKey: "NetworkInterceptorHandled", in: request) != nil {
            return false
        }

        return true
    }

    /// Returns the canonical version of the request
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    /// Start loading the request
    override func startLoading() {
        // Mark request as handled to avoid infinite loops
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return
        }
        URLProtocol.setProperty(true, forKey: "NetworkInterceptorHandled", in: mutableRequest)

        let startTime = Date()

        // Generate or extract request ID
        let requestId: String
        if let existingId = request.value(forHTTPHeaderField: "X-Request-ID") {
            requestId = existingId
        } else {
            requestId = UUID().uuidString
            URLProtocol.setProperty(requestId, forKey: "X-Request-ID", in: mutableRequest)
        }

        // Log request to NetworkLogger
        let logId = NetworkLogger.shared.logRequest(
            url: request.url?.absoluteString ?? "",
            method: request.httpMethod ?? "GET",
            body: request.httpBody,
            requestId: requestId
        )

        // Store metadata for this request
        Self.metadataQueue.sync {
            Self.requestMetadata[request] = RequestMetadata(logId: logId, startTime: startTime)
        }

        // Create a data task to actually perform the network request
        let task = URLSession.shared.dataTask(with: mutableRequest as URLRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            // Retrieve metadata
            var metadata: RequestMetadata?
            Self.metadataQueue.sync {
                metadata = Self.requestMetadata[self.request]
                Self.requestMetadata.removeValue(forKey: self.request)
            }

            guard let metadata = metadata else { return }

            // Log response
            let httpResponse = response as? HTTPURLResponse
            NetworkLogger.shared.logResponse(
                id: metadata.logId,
                status: httpResponse?.statusCode,
                data: data,
                headers: httpResponse?.allHeaderFields,
                error: error,
                startTime: metadata.startTime
            )

            // Forward the response to the client
            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
            } else {
                if let response = response {
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
                if let data = data {
                    self.client?.urlProtocol(self, didLoad: data)
                }
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }

        task.resume()
    }

    /// Stop loading the request
    override func stopLoading() {
        // Clean up metadata
        Self.metadataQueue.sync {
            _ = Self.requestMetadata.removeValue(forKey: request)
        }
    }

    // MARK: - Public API

    /// Register the interceptor to capture all network requests
    /// Call this once at app startup
    static func register() {
        guard DebugConfig.isDeveloperModeEnabled else {
            logger.info("NetworkInterceptor registration skipped - debug mode disabled")
            return
        }

        URLProtocol.registerClass(NetworkInterceptor.self)
        logger.info("✅ NetworkInterceptor registered - all network requests will be logged")
    }

    /// Unregister the interceptor
    static func unregister() {
        URLProtocol.unregisterClass(NetworkInterceptor.self)
        logger.info("NetworkInterceptor unregistered")
    }
}
