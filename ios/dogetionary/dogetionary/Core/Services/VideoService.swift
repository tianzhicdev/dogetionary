//
//  VideoService.swift
//  dogetionary
//
//  Video downloading and caching service for practice mode
//

import Foundation
import Combine

// MARK: - Download State

enum VideoDownloadState: Equatable {
    case notStarted
    case downloading(
        progress: Double,
        startTime: Date,
        bytesDownloaded: Int64,
        totalBytes: Int64?
    )
    case cached(
        url: URL,
        downloadDuration: TimeInterval,
        fileSize: Int64
    )
    case failed(
        error: String,
        retryCount: Int,
        duration: TimeInterval?
    )

    static func == (lhs: VideoDownloadState, rhs: VideoDownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted):
            return true
        case (.downloading(let p1, let s1, let b1, let t1), .downloading(let p2, let s2, let b2, let t2)):
            return p1 == p2 && s1 == s2 && b1 == b2 && t1 == t2
        case (.cached(let u1, let d1, let f1), .cached(let u2, let d2, let f2)):
            return u1 == u2 && d1 == d2 && f1 == f2
        case (.failed(let e1, let r1, let d1), .failed(let e2, let r2, let d2)):
            return e1 == e2 && r1 == r2 && d1 == d2
        default:
            return false
        }
    }

    // Helper to extract basic state for simple comparisons
    var simpleState: String {
        switch self {
        case .notStarted: return "notStarted"
        case .downloading: return "downloading"
        case .cached: return "cached"
        case .failed: return "failed"
        }
    }
}

// MARK: - Download Delegate

/// URLSession delegate for tracking download progress
class VideoDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var videoService: VideoService?
    private var videoIdMap: [URLSessionTask: Int] = [:]
    private var startTimes: [Int: Date] = [:]
    private let queue = DispatchQueue(label: "com.dogetionary.video.delegate", attributes: .concurrent)

    func setVideoId(_ videoId: Int, for task: URLSessionDownloadTask, startTime: Date) {
        queue.async(flags: .barrier) { [weak self] in
            self?.videoIdMap[task] = videoId
            self?.startTimes[videoId] = startTime
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        queue.sync { [weak self] in
            guard let self = self,
                  let videoId = self.videoIdMap[downloadTask],
                  let startTime = self.startTimes[videoId] else {
                return
            }

            let progress = totalBytesExpectedToWrite > 0
                ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                : 0.0

            // Update state with progress (debounce to every 10% or 0.5s)
            DispatchQueue.main.async {
                self.videoService?.updateState(
                    videoId: videoId,
                    state: .downloading(
                        progress: progress,
                        startTime: startTime,
                        bytesDownloaded: totalBytesWritten,
                        totalBytes: totalBytesExpectedToWrite
                    )
                )
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Cleanup handled in completion handler
    }

    func cleanup(for task: URLSessionTask) {
        queue.async(flags: .barrier) { [weak self] in
            if let videoId = self?.videoIdMap[task] {
                self?.startTimes.removeValue(forKey: videoId)
            }
            self?.videoIdMap.removeValue(forKey: task)
        }
    }
}

class VideoService: ObservableObject {
    static let shared = VideoService()

    private let baseURL: String
    private let cacheDirectory: URL
    private let maxCacheSizeBytes: Int = 500 * 1024 * 1024  // 500 MB
    private let maxConcurrentDownloads = 1  // Sequential download: one-by-one
    private let maxRetries = 3
    private let retryDelays: [TimeInterval] = [1.0, 2.0, 4.0]

    private var downloadTasks: [Int: URLSessionDownloadTask] = [:]
    @Published private(set) var downloadStates: [Int: VideoDownloadState] = [:]
    private let fileManager = FileManager.default

    // Background queue for sequential video downloads (semaphore limits to 1 at a time)
    private let downloadQueue = DispatchQueue(label: "com.dogetionary.video.download", qos: .utility, attributes: .concurrent)
    private let downloadSemaphore: DispatchSemaphore

    // Custom URLSession with delegate for progress tracking
    private let downloadDelegate: VideoDownloadDelegate
    private let urlSession: URLSession

    private init() {
        self.baseURL = Configuration.effectiveBaseURL
        self.downloadSemaphore = DispatchSemaphore(value: maxConcurrentDownloads)

        // Create cache directory if it doesn't exist
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cachesDir.appendingPathComponent("videos", isDirectory: true)

        // Setup custom URLSession with delegate
        self.downloadDelegate = VideoDownloadDelegate()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        self.urlSession = URLSession(
            configuration: config,
            delegate: downloadDelegate,
            delegateQueue: nil
        )

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        print("VideoService: Cache directory: \(cacheDirectory.path)")

        // Set reference to self in delegate (after all properties initialized)
        self.downloadDelegate.videoService = self

        // Initialize states for cached videos
        initializeCachedStates()
    }

    /// Initialize states for already-cached videos on startup
    private func initializeCachedStates() {
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return
        }

        for fileURL in files where fileURL.pathExtension == "mp4" {
            // Extract video ID from filename: video_123.mp4
            let filename = fileURL.deletingPathExtension().lastPathComponent
            if let videoIdStr = filename.split(separator: "_").last,
               let videoId = Int(videoIdStr) {
                // Get file size
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

                // Unknown download duration for pre-existing files
                updateState(videoId: videoId, state: .cached(
                    url: fileURL,
                    downloadDuration: 0.0,
                    fileSize: Int64(fileSize)
                ))
            }
        }

        print("VideoService: Initialized \(downloadStates.count) cached videos")
    }

    // MARK: - State Management

    /// Get current download state for a video
    func getDownloadState(videoId: Int) -> VideoDownloadState {
        // Always read on main thread to avoid race conditions
        if Thread.isMainThread {
            return downloadStates[videoId] ?? .notStarted
        } else {
            return DispatchQueue.main.sync {
                return downloadStates[videoId] ?? .notStarted
            }
        }
    }

    /// Update download state (thread-safe) - internal for delegate access
    /// MUST be called on main thread for @Published to work correctly
    func updateState(videoId: Int, state: VideoDownloadState) {
        if Thread.isMainThread {
            downloadStates[videoId] = state
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.downloadStates[videoId] = state
            }
        }
    }

    // MARK: - Public API

    /// Fetch video by ID, returning local file URL (from cache or after download)
    func fetchVideo(videoId: Int) -> AnyPublisher<URL, Error> {
        let state = getDownloadState(videoId: videoId)

        switch state {
        case .cached(let url, _, _):
            print("VideoService: Cache hit for video \(videoId)")
            return Just(url)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()

        case .downloading:
            // Already downloading - wait for completion by observing state changes
            print("VideoService: Video \(videoId) already downloading, waiting...")
            return waitForDownloadCompletion(videoId: videoId)

        case .failed(_, let retryCount, _):
            print("VideoService: Video \(videoId) previously failed (\(retryCount) retries), retrying...")
            return downloadVideoWithRetry(videoId: videoId, attempt: retryCount)

        case .notStarted:
            print("VideoService: Starting download for video \(videoId)")
            return downloadVideoWithRetry(videoId: videoId, attempt: 0)
        }
    }

    /// Preload multiple videos in background (sequential, non-blocking)
    func preloadVideos(videoIds: [Int]) {
        guard !videoIds.isEmpty else { return }

        print("VideoService: Queuing \(videoIds.count) videos for sequential download (one-by-one)")

        for videoId in videoIds {
            let state = getDownloadState(videoId: videoId)

            // Skip if already cached or downloading
            switch state {
            case .cached:
                print("VideoService: Skipping video \(videoId) - already cached")
                continue
            case .downloading:
                print("VideoService: Skipping video \(videoId) - already downloading")
                continue
            default:
                break
            }

            // Download in background (non-blocking, returns immediately)
            downloadQueue.async { [weak self] in
                guard let self = self else { return }

                // Semaphore ensures downloads happen one-by-one (sequential)
                self.downloadSemaphore.wait()
                defer { self.downloadSemaphore.signal() }

                print("VideoService: Starting background download for video \(videoId)")

                // Download with retry logic
                var cancellable: AnyCancellable?
                let semaphore = DispatchSemaphore(value: 0)

                cancellable = self.downloadVideoWithRetry(videoId: videoId, attempt: 0)
                    .sink(
                        receiveCompletion: { completion in
                            if case .failure(let error) = completion {
                                print("VideoService: Background download failed for video \(videoId): \(error.localizedDescription)")
                            }
                            semaphore.signal()
                        },
                        receiveValue: { url in
                            print("VideoService: ✓ Background downloaded video \(videoId) -> \(url.lastPathComponent)")
                        }
                    )

                semaphore.wait()
                _ = cancellable // Keep reference alive
            }
        }
    }

    /// Wait for an ongoing download to complete
    private func waitForDownloadCompletion(videoId: Int) -> AnyPublisher<URL, Error> {
        let subject = PassthroughSubject<URL, Error>()

        // Poll state every 0.5 seconds until download completes
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }

                let state = self.getDownloadState(videoId: videoId)
                switch state {
                case .cached(let url, _, _):
                    subject.send(url)
                    subject.send(completion: .finished)
                case .failed(let error, _, _):
                    subject.send(completion: .failure(NSError(domain: "VideoService", code: -1, userInfo: [NSLocalizedDescriptionKey: error])))
                case .downloading, .notStarted:
                    // Keep waiting
                    break
                }
            }
            .store(in: &cancellables)

        return subject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()

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

    // MARK: - Download with Retry

    /// Download video with automatic retry on failure
    private func downloadVideoWithRetry(videoId: Int, attempt: Int) -> AnyPublisher<URL, Error> {
        // Check if already cached (might have been downloaded by another call)
        if let cachedURL = getCachedVideoURL(videoId: videoId) {
            // Get file size
            let fileSize = (try? fileManager.attributesOfItem(atPath: cachedURL.path)[.size] as? Int64) ?? 0
            updateState(videoId: videoId, state: .cached(
                url: cachedURL,
                downloadDuration: 0.0,  // Unknown for pre-existing/race-condition files
                fileSize: fileSize
            ))
            return Just(cachedURL)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }

        // Start download
        return downloadVideo(videoId: videoId)
            .catch { [weak self] error -> AnyPublisher<URL, Error> in
                guard let self = self else {
                    return Fail(error: error).eraseToAnyPublisher()
                }

                // Check if we should retry
                if attempt < self.maxRetries {
                    let delay = self.retryDelays[min(attempt, self.retryDelays.count - 1)]
                    print("VideoService: Retrying video \(videoId) in \(delay)s (attempt \(attempt + 1)/\(self.maxRetries))")

                    // Update state to show retry count (duration unknown during retry)
                    self.updateState(videoId: videoId, state: .failed(
                        error: error.localizedDescription,
                        retryCount: attempt,
                        duration: nil
                    ))

                    // Retry after delay
                    return Just(())
                        .delay(for: .seconds(delay), scheduler: DispatchQueue.global())
                        .flatMap { _ in
                            self.downloadVideoWithRetry(videoId: videoId, attempt: attempt + 1)
                        }
                        .eraseToAnyPublisher()
                } else {
                    // Max retries exceeded (duration unknown)
                    print("VideoService: Max retries exceeded for video \(videoId)")
                    self.updateState(videoId: videoId, state: .failed(
                        error: error.localizedDescription,
                        retryCount: attempt,
                        duration: nil
                    ))
                    return Fail(error: error).eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }

    private func downloadVideo(videoId: Int) -> AnyPublisher<URL, Error> {
        let subject = PassthroughSubject<URL, Error>()

        // Capture start time for tracking
        let startTime = Date()

        // Update state to downloading with start time
        updateState(videoId: videoId, state: .downloading(
            progress: 0.0,
            startTime: startTime,
            bytesDownloaded: 0,
            totalBytes: nil
        ))

        // Build URL
        let videoURL = URL(string: "\(baseURL)/v3/videos/\(videoId)")!
        print("📥 VideoService: Starting download for video \(videoId)")
        print("   URL: \(videoURL)")
        print("   Base URL: \(baseURL)")

        // Log request to NetworkLogger (manual logging for downloadTask)
        let requestId = UUID().uuidString
        let _ = NetworkLogger.shared.logRequest(
            url: videoURL.absoluteString,
            method: "GET",
            body: nil,
            requestId: requestId
        )

        // Create download task with custom session (has delegate for progress)
        let task = urlSession.downloadTask(with: videoURL) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            // Remove from active tasks
            self.downloadTasks.removeValue(forKey: videoId)

            // Log response to NetworkLogger (using requestId)
            let httpResponse = response as? HTTPURLResponse
            // For download tasks, we don't have the data directly, so pass nil
            NetworkLogger.shared.logResponse(
                id: requestId,
                status: httpResponse?.statusCode,
                data: nil, // Video data is saved to file, not available here
                headers: httpResponse?.allHeaderFields,
                error: error,
                startTime: startTime
            )

            // Calculate duration
            let duration = Date().timeIntervalSince(startTime)

            // Cleanup delegate (get task from downloadTasks)
            if let completedTask = self.downloadTasks[videoId] {
                self.downloadDelegate.cleanup(for: completedTask)
            }

            // Handle errors
            if let error = error {
                print("❌ VideoService: Network error for video \(videoId)")
                print("   Error: \(error.localizedDescription)")
                print("   Domain: \((error as NSError).domain)")
                print("   Code: \((error as NSError).code)")
                print("   Duration: \(String(format: "%.1f", duration))s")
                self.updateState(videoId: videoId, state: .failed(
                    error: error.localizedDescription,
                    retryCount: 0,
                    duration: duration
                ))
                subject.send(completion: .failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ VideoService: Invalid response for video \(videoId)")
                let error = NSError(domain: "VideoService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                self.updateState(videoId: videoId, state: .failed(
                    error: error.localizedDescription,
                    retryCount: 0,
                    duration: duration
                ))
                subject.send(completion: .failure(error))
                return
            }

            print("📡 VideoService: Got HTTP response for video \(videoId)")
            print("   Status code: \(httpResponse.statusCode)")
            print("   Headers: \(httpResponse.allHeaderFields)")

            guard httpResponse.statusCode == 200 else {
                print("❌ VideoService: Bad status code \(httpResponse.statusCode) for video \(videoId)")
                let error = NSError(domain: "VideoService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                self.updateState(videoId: videoId, state: .failed(
                    error: error.localizedDescription,
                    retryCount: 0,
                    duration: duration
                ))
                subject.send(completion: .failure(error))
                return
            }

            guard let tempURL = tempURL else {
                print("❌ VideoService: No temp file for video \(videoId)")
                let error = NSError(domain: "VideoService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No temp file"])
                self.updateState(videoId: videoId, state: .failed(
                    error: error.localizedDescription,
                    retryCount: 0,
                    duration: duration
                ))
                subject.send(completion: .failure(error))
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

                // Get final file size
                let fileSize = (try? self.fileManager.attributesOfItem(atPath: cacheURL.path)[.size] as? Int64) ?? 0

                if fileSize > 0 {
                    print("✓ VideoService: Successfully cached video \(videoId) - \(fileSize) bytes")
                    print("   Cache path: \(cacheURL.path)")
                    print("   Duration: \(String(format: "%.1f", duration))s")
                } else {
                    print("⚠️ VideoService: Cached but can't read attributes for video \(videoId)")
                }

                // Check cache size and cleanup if needed
                self.enforceMaxCacheSize()

                // Update state to cached with timing info
                self.updateState(videoId: videoId, state: .cached(
                    url: cacheURL,
                    downloadDuration: duration,
                    fileSize: fileSize
                ))

                // Pre-create AVPlayer for this video
                AVPlayerManager.shared.createPlayer(videoId: videoId, url: cacheURL)

                subject.send(cacheURL)
                subject.send(completion: .finished)

            } catch {
                print("❌ VideoService: Failed to cache video \(videoId)")
                print("   Error: \(error.localizedDescription)")
                self.updateState(videoId: videoId, state: .failed(
                    error: error.localizedDescription,
                    retryCount: 0,
                    duration: duration
                ))
                subject.send(completion: .failure(error))
            }
        }

        // Store task reference
        downloadTasks[videoId] = task

        // Register task with delegate for progress tracking
        downloadDelegate.setVideoId(videoId, for: task, startTime: startTime)

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
