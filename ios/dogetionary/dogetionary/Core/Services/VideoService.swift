//
//  VideoService.swift
//  dogetionary
//
//  Video downloading and caching service for practice mode
//

import Foundation
import Combine

class VideoService {
    static let shared = VideoService()

    private let baseURL: String
    private let cacheDirectory: URL
    private let maxCacheSizeBytes: Int = 500 * 1024 * 1024  // 500 MB

    private var downloadTasks: [Int: URLSessionDownloadTask] = [:]
    private let fileManager = FileManager.default

    private init() {
        self.baseURL = Configuration.effectiveBaseURL

        // Create cache directory if it doesn't exist
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cachesDir.appendingPathComponent("videos", isDirectory: true)

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        print("VideoService: Cache directory: \(cacheDirectory.path)")
    }

    // MARK: - Public API

    /// Fetch video by ID, returning local file URL (from cache or after download)
    func fetchVideo(videoId: Int) -> AnyPublisher<URL, Error> {
        // Check cache first
        if let cachedURL = getCachedVideoURL(videoId: videoId) {
            print("VideoService: Cache hit for video \(videoId)")
            return Just(cachedURL)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }

        // Download from server
        print("VideoService: Downloading video \(videoId)")
        return downloadVideo(videoId: videoId)
    }

    /// Preload multiple videos in background
    func preloadVideos(videoIds: [Int]) {
        print("VideoService: Preloading \(videoIds.count) videos")

        for videoId in videoIds {
            // Skip if already cached
            if getCachedVideoURL(videoId: videoId) != nil {
                continue
            }

            // Skip if already downloading
            if downloadTasks[videoId] != nil {
                continue
            }

            // Start background download
            _ = downloadVideo(videoId: videoId)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("VideoService: Preload failed for video \(videoId): \(error)")
                        }
                    },
                    receiveValue: { url in
                        print("VideoService: Preloaded video \(videoId) -> \(url.lastPathComponent)")
                    }
                )
        }
    }

    /// Clear cache for videos older than specified days
    func clearOldCache(olderThanDays days: Int = 7) {
        print("VideoService: Clearing cache older than \(days) days")

        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))

        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }

        var deletedCount = 0
        for fileURL in files {
            if let modificationDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modificationDate < cutoffDate {
                try? fileManager.removeItem(at: fileURL)
                deletedCount += 1
            }
        }

        print("VideoService: Deleted \(deletedCount) old videos")
    }

    /// Get total cache size in bytes
    func getCacheSize() -> Int {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        return files.reduce(0) { total, fileURL in
            let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return total + (size ?? 0)
        }
    }

    /// Clear all cached videos
    func clearAllCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("VideoService: Cleared all cache")
    }

    // MARK: - Private Helpers

    private func getCachedVideoURL(videoId: Int) -> URL? {
        let cacheURL = cacheDirectory.appendingPathComponent("video_\(videoId).mp4")

        if fileManager.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        return nil
    }

    private func downloadVideo(videoId: Int) -> AnyPublisher<URL, Error> {
        let subject = PassthroughSubject<URL, Error>()

        // Build URL
        let videoURL = URL(string: "\(baseURL)/v3/videos/\(videoId)")!
        print("VideoService: Fetching from \(videoURL)")

        // Create download task
        let task = URLSession.shared.downloadTask(with: videoURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            // Remove from active tasks
            self.downloadTasks.removeValue(forKey: videoId)

            // Handle errors
            if let error = error {
                subject.send(completion: .failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                subject.send(completion: .failure(NSError(domain: "VideoService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }

            guard httpResponse.statusCode == 200 else {
                subject.send(completion: .failure(NSError(domain: "VideoService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])))
                return
            }

            guard let tempURL = tempURL else {
                subject.send(completion: .failure(NSError(domain: "VideoService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No temp file"])))
                return
            }

            // Move to cache directory
            let cacheURL = self.cacheDirectory.appendingPathComponent("video_\(videoId).mp4")

            do {
                // Remove old file if exists
                if self.fileManager.fileExists(atPath: cacheURL.path) {
                    try self.fileManager.removeItem(at: cacheURL)
                }

                // Move temp file to cache
                try self.fileManager.moveItem(at: tempURL, to: cacheURL)

                print("VideoService: Cached video \(videoId) at \(cacheURL.lastPathComponent)")

                // Check cache size and cleanup if needed
                self.enforceMaxCacheSize()

                subject.send(cacheURL)
                subject.send(completion: .finished)

            } catch {
                subject.send(completion: .failure(error))
            }
        }

        // Store task reference
        downloadTasks[videoId] = task

        // Start download
        task.resume()

        return subject.eraseToAnyPublisher()
    }

    private func enforceMaxCacheSize() {
        let currentSize = getCacheSize()

        if currentSize > maxCacheSizeBytes {
            print("VideoService: Cache size (\(currentSize / 1024 / 1024) MB) exceeds limit, cleaning up")

            // Get all files sorted by modification date (oldest first)
            guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                return
            }

            let sortedFiles = files.sorted { file1, file2 in
                let date1 = try? file1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                let date2 = try? file2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date.distantPast
                return (date1 ?? Date.distantPast) < (date2 ?? Date.distantPast)
            }

            // Delete oldest files until under limit
            var remainingSize = currentSize
            for fileURL in sortedFiles {
                if remainingSize <= maxCacheSizeBytes {
                    break
                }

                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                try? fileManager.removeItem(at: fileURL)
                remainingSize -= fileSize
                print("VideoService: Deleted \(fileURL.lastPathComponent) (\(fileSize / 1024) KB)")
            }
        }
    }
}
