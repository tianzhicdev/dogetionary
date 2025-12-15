//
//  NetworkLogger.swift
//  dogetionary
//
//  Network request/response logger for debug mode
//  Stores last 50 HTTP calls for debugging purposes
//

import Foundation
import SwiftUI
import os.log

/// Singleton service that logs all network requests/responses for debug inspection
class NetworkLogger: ObservableObject {
    static let shared = NetworkLogger()

    private let logger = Logger(subsystem: "com.dogetionary", category: "NetworkLogger")
    private let maxCalls = 50

    // MARK: - Network Call Model

    struct NetworkCall: Identifiable {
        let id: UUID
        let timestamp: Date
        let url: String
        let method: String
        let requestBody: String?
        var responseStatus: Int?
        var responseBody: String?
        var responseHeaders: [String: String]?
        var duration: TimeInterval?
        var error: String?
        var endTime: Date?

        var isComplete: Bool {
            return endTime != nil
        }

        var statusColor: Color {
            guard let status = responseStatus else { return .gray }
            if status >= 200 && status < 300 {
                return .green
            } else if status >= 400 {
                return .red
            } else {
                return .orange
            }
        }

        var durationString: String {
            guard let duration = duration else { return "pending" }
            return String(format: "%.0fms", duration * 1000)
        }
    }

    // MARK: - Published State

    @Published private(set) var recentCalls: [NetworkCall] = []

    private init() {
        logger.info("NetworkLogger initialized")
    }

    // MARK: - Public API

    /// Log the start of a network request
    /// Returns a UUID to correlate with the response
    func logRequest(url: String, method: String, body: Data?) -> UUID {
        guard DebugConfig.isDeveloperModeEnabled else {
            // Skip logging if debug mode is disabled
            return UUID()
        }

        let id = UUID()
        let timestamp = Date()

        // Parse body if available
        var bodyString: String?
        if let body = body,
           let jsonObject = try? JSONSerialization.jsonObject(with: body),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            bodyString = prettyString
        } else if let body = body, let rawString = String(data: body, encoding: .utf8) {
            bodyString = rawString
        }

        let call = NetworkCall(
            id: id,
            timestamp: timestamp,
            url: url,
            method: method,
            requestBody: bodyString,
            responseStatus: nil,
            responseBody: nil,
            responseHeaders: nil,
            duration: nil,
            error: nil,
            endTime: nil
        )

        DispatchQueue.main.async {
            self.recentCalls.insert(call, at: 0)

            // Keep only last 50 calls
            if self.recentCalls.count > self.maxCalls {
                self.recentCalls.removeLast()
            }
        }

        logger.debug("Logged request: \(method) \(url)")
        return id
    }

    /// Log the completion of a network request
    func logResponse(id: UUID, status: Int?, data: Data?, headers: [AnyHashable: Any]?, error: Error?, startTime: Date) {
        guard DebugConfig.isDeveloperModeEnabled else { return }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Parse response body
        var bodyString: String?
        if let data = data {
            // Try to pretty-print JSON
            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                bodyString = prettyString
            } else if let rawString = String(data: data, encoding: .utf8) {
                // Fallback to raw string
                bodyString = rawString
            } else {
                bodyString = "<binary data: \(data.count) bytes>"
            }
        } else {
            // Data is nil - likely a download task where data is saved directly to file
            if status == 200 {
                bodyString = "<download task - data saved to file>"
            }
        }

        // Convert headers to string dictionary
        var headersDict: [String: String]?
        if let headers = headers {
            headersDict = headers.reduce(into: [String: String]()) { result, pair in
                result[String(describing: pair.key)] = String(describing: pair.value)
            }
        }

        DispatchQueue.main.async {
            if let index = self.recentCalls.firstIndex(where: { $0.id == id }) {
                var updatedCall = self.recentCalls[index]
                updatedCall.responseStatus = status
                updatedCall.responseBody = bodyString
                updatedCall.responseHeaders = headersDict
                updatedCall.duration = duration
                updatedCall.error = error?.localizedDescription
                updatedCall.endTime = endTime

                self.recentCalls[index] = updatedCall

                self.logger.debug("Logged response: \(status ?? 0) in \(duration * 1000)ms")
            } else {
                self.logger.warning("Could not find request with id \(id.uuidString)")
            }
        }
    }

    /// Clear all logged calls
    func clearLogs() {
        DispatchQueue.main.async {
            self.recentCalls.removeAll()
            self.logger.info("Cleared all network logs")
        }
    }
}
