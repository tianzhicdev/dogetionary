//
//  BaseNetworkService.swift
//  dogetionary
//
//  Base networking service with shared request handling
//

import Foundation
import os.log

/// Base class for all network services providing shared networking logic
class BaseNetworkService {
    let baseURL = Configuration.effectiveBaseURL
    let logger: Logger

    init(category: String) {
        self.logger = Logger(subsystem: "com.dogetionary.app", category: category)
    }

    /// Generic network request handler with logging
    func performNetworkRequest<T: Codable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        responseType: T.Type,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            request.httpBody = body
        }

        // Log request details
        logger.info("REQUEST: \(method) \(url.absoluteString)")
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            logger.info("REQUEST BODY: \(bodyString)")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            // Log response status and headers
            self.logger.info("RESPONSE STATUS: \(httpResponse.statusCode)")
            self.logger.info("RESPONSE HEADERS: \(httpResponse.allHeaderFields)")

            guard let data = data else {
                self.logger.error("No data received")
                completion(.failure(DictionaryError.noData))
                return
            }

            // Log raw response data for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                self.logger.info("RAW RESPONSE: \(responseString)")
            } else {
                self.logger.error("Could not convert response data to string")
            }

            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                do {
                    let response = try JSONDecoder().decode(responseType, from: data)
                    self.logger.info("Successfully decoded response")
                    completion(.success(response))
                } catch {
                    self.logger.error("Failed to decode response: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        self.logger.error("Detailed decoding error: \(decodingError)")
                    }
                    completion(.failure(DictionaryError.decodingError(error)))
                }
            } else {
                self.logger.error("HTTP error: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
            }
        }.resume()
    }
}

/// Shared error types for all services
enum DictionaryError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case notFound
    case serverError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .noData:
            return "No data received"
        case .notFound:
            return "Word not found"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
