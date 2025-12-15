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

    // Serial queue for sequential video downloads
    private let serialDownloadQueue = DispatchQueue(label: "com.dogetionary.video.download", qos: .utility)

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

    /// Preload multiple videos in background (sequential downloads, no locks needed)
    func preloadVideos(videoIds: [Int]) {
        guard !videoIds.isEmpty else { return }

        print("VideoService: Queuing \(videoIds.count) videos for sequential download")

        // Use serial queue to download videos one by one
        serialDownloadQueue.async { [weak self] in
            guard let self = self else { return }

            for videoId in videoIds {
                // Skip if already cached (check on background thread)
                if self.getCachedVideoURL(videoId: videoId) != nil {
                    print("VideoService: Skipping video \(videoId) - already cached")
                    continue
                }

                print("VideoService: Downloading video \(videoId) sequentially...")

                // Synchronous download using semaphore
                let semaphore = DispatchSemaphore(value: 0)
                var downloadError: Error?

                _ = self.downloadVideo(videoId: videoId)
                    .sink(
                        receiveCompletion: { completion in
                            if case .failure(let error) = completion {
                                downloadError = error
                                print("VideoService: Failed to download video \(videoId): \(error.localizedDescription)")
                            }
                            semaphore.signal()
                        },
                        receiveValue: { url in
                            print("VideoService: ✓ Downloaded video \(videoId) -> \(url.lastPathComponent)")
                        }
                    )

                // Wait for this download to complete before moving to next
                semaphore.wait()

                // Log if there was an error but continue to next video
                if let error = downloadError {
                    print("VideoService: Continuing to next video after error: \(error.localizedDescription)")
                }
            }

            print("VideoService: Finished sequential download batch")
        }
    }

    /// Clear all cached videos
    func clearCache() -> Result<Int, Error> {
        print("VideoService: Clearing video cache at \(cacheDirectory.path)")

        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            let videoFiles = files.filter { $0.pathExtension == "mp4" }

            var deletedCount = 0
            var totalSize: Int64 = 0

            for file in videoFiles {
                if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                   let fileSize = attributes[.size] as? Int64 {
                    totalSize += fileSize
                }

                try fileManager.removeItem(at: file)
                deletedCount += 1
            }

            print("✓ VideoService: Cleared \(deletedCount) videos (\(totalSize / 1024 / 1024) MB)")
            return .success(deletedCount)

        } catch {
            print("❌ VideoService: Failed to clear cache: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Get current cache size and file count
    func getCacheInfo() -> (fileCount: Int, sizeBytes: Int64) {
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
            let videoFiles = files.filter { $0.pathExtension == "mp4" }

            var totalSize: Int64 = 0
            for file in videoFiles {
                if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                   let fileSize = attributes[.size] as? Int64 {
                    totalSize += fileSize
                }
            }

            return (videoFiles.count, totalSize)
        } catch {
            return (0, 0)
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

    /// Check if a video is downloaded and cached
    func isVideoDownloaded(videoId: Int) -> Bool {
        return getCachedVideoURL(videoId: videoId) != nil
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
        print("📥 VideoService: Starting download for video \(videoId)")
        print("   URL: \(videoURL)")
        print("   Base URL: \(baseURL)")

        // Create download task
        let task = URLSession.shared.downloadTask(with: videoURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            // Remove from active tasks
            self.downloadTasks.removeValue(forKey: videoId)

            // Handle errors
            if let error = error {
                print("❌ VideoService: Network error for video \(videoId)")
                print("   Error: \(error.localizedDescription)")
                print("   Domain: \((error as NSError).domain)")
                print("   Code: \((error as NSError).code)")
                subject.send(completion: .failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ VideoService: Invalid response for video \(videoId)")
                subject.send(completion: .failure(NSError(domain: "VideoService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }

            print("📡 VideoService: Got HTTP response for video \(videoId)")
            print("   Status code: \(httpResponse.statusCode)")
            print("   Headers: \(httpResponse.allHeaderFields)")

            guard httpResponse.statusCode == 200 else {
                print("❌ VideoService: Bad status code \(httpResponse.statusCode) for video \(videoId)")
                subject.send(completion: .failure(NSError(domain: "VideoService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])))
                return
            }

            guard let tempURL = tempURL else {
                print("❌ VideoService: No temp file for video \(videoId)")
                subject.send(completion: .failure(NSError(domain: "VideoService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No temp file"])))
                return
            }

            // Check temp file
            if let tempAttributes = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
               let tempSize = tempAttributes[.size] as? Int64 {
                print("✓ VideoService: Downloaded to temp file - \(tempSize) bytes")
                print("   Temp path: \(tempURL.path)")
            }

            // Move to cache directory
            let cacheURL = self.cacheDirectory.appendingPathComponent("video_\(videoId).mp4")

            do {
                // Remove old file if exists
                if self.fileManager.fileExists(atPath: cacheURL.path) {
                    print("   Removing old cached file at \(cacheURL.path)")
                    try self.fileManager.removeItem(at: cacheURL)
                }

                // Move temp file to cache
                try self.fileManager.moveItem(at: tempURL, to: cacheURL)

                // Verify final file
                if let cacheAttributes = try? self.fileManager.attributesOfItem(atPath: cacheURL.path),
                   let cacheSize = cacheAttributes[.size] as? Int64 {
                    print("✓ VideoService: Successfully cached video \(videoId) - \(cacheSize) bytes")
                    print("   Cache path: \(cacheURL.path)")
                } else {
                    print("⚠️ VideoService: Cached but can't read attributes for video \(videoId)")
                }

                // Check cache size and cleanup if needed
                self.enforceMaxCacheSize()

                subject.send(cacheURL)
                subject.send(completion: .finished)

            } catch {
                print("❌ VideoService: Failed to cache video \(videoId)")
                print("   Error: \(error.localizedDescription)")
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
