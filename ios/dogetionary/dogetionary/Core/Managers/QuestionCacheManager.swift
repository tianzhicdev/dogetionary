//
//  QuestionCacheManager.swift
//  dogetionary
//
//  Manages persistent caching of review questions to disk.
//  Cache key: {word}_{learningLanguage}_{nativeLanguage}
//

import Foundation
import os

/// Singleton manager for question caching
class QuestionCacheManager {
    static let shared = QuestionCacheManager()

    private let logger = Logger(subsystem: "com.dogetionary", category: "QuestionCache")
    private let fileManager = FileManager.default
    private let cacheDirectoryName = "QuestionCache"

    /// Cache directory URL
    private var cacheDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }

    private init() {
        createCacheDirectoryIfNeeded()
    }

    // MARK: - Cache Operations

    /// Save a question to cache
    func saveQuestion(word: String, learningLang: String, nativeLang: String, question: BatchReviewQuestion) {
        // Check if caching is enabled
        guard UserManager.shared.cacheEnabled else {
            logger.debug("Cache disabled by user, skipping save for: \(word)")
            return
        }

        let cacheKey = makeCacheKey(word: word, learningLang: learningLang, nativeLang: nativeLang)
        let fileURL = cacheDirectory.appendingPathComponent("\(cacheKey).json")

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(question)
            try data.write(to: fileURL)
            logger.debug("Saved question to cache: \(cacheKey)")
        } catch {
            logger.error("Failed to save question \(cacheKey): \(error.localizedDescription)")
        }
    }

    /// Load a question from cache
    func loadQuestion(word: String, learningLang: String, nativeLang: String) -> BatchReviewQuestion? {
        let cacheKey = makeCacheKey(word: word, learningLang: learningLang, nativeLang: nativeLang)
        let fileURL = cacheDirectory.appendingPathComponent("\(cacheKey).json")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.debug("Cache miss: \(cacheKey)")
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let question = try decoder.decode(BatchReviewQuestion.self, from: data)
            logger.debug("Cache hit: \(cacheKey)")
            return question
        } catch {
            logger.error("Failed to load cached question \(cacheKey): \(error.localizedDescription)")
            // Delete corrupted cache file
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
    }

    /// Clear all cached questions
    func clearCache() -> Result<Int, Error> {
        do {
            guard fileManager.fileExists(atPath: cacheDirectory.path) else {
                logger.info("Cache directory doesn't exist, nothing to clear")
                return .success(0)
            }

            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }

            var deletedCount = 0
            for file in jsonFiles {
                try fileManager.removeItem(at: file)
                deletedCount += 1
            }

            logger.info("Cleared \(deletedCount) cached questions")
            return .success(deletedCount)
        } catch {
            logger.error("Failed to clear cache: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Get cache statistics
    func getCacheInfo() -> (fileCount: Int, sizeBytes: Int) {
        do {
            guard fileManager.fileExists(atPath: cacheDirectory.path) else {
                return (0, 0)
            }

            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            let jsonFiles = files.filter { $0.pathExtension == "json" }

            var totalSize = 0
            for file in jsonFiles {
                if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                   let fileSize = attributes[.size] as? Int {
                    totalSize += fileSize
                }
            }

            return (jsonFiles.count, totalSize)
        } catch {
            logger.error("Failed to get cache info: \(error.localizedDescription)")
            return (0, 0)
        }
    }

    // MARK: - Private Helpers

    /// Create cache directory if it doesn't exist
    private func createCacheDirectoryIfNeeded() {
        guard !fileManager.fileExists(atPath: cacheDirectory.path) else { return }

        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            logger.info("Created cache directory at \(self.cacheDirectory.path)")
        } catch {
            logger.error("Failed to create cache directory: \(error.localizedDescription)")
        }
    }

    /// Generate cache key from word and languages
    private func makeCacheKey(word: String, learningLang: String, nativeLang: String) -> String {
        // Sanitize word to make it filename-safe
        let sanitized = word
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")

        return "\(sanitized)_\(learningLang)_\(nativeLang)"
    }
}
