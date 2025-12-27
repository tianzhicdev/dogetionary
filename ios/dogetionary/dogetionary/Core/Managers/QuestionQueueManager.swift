//
//  QuestionQueueManager.swift
//  dogetionary
//
//  Manages a local queue of review questions for instant transitions.
//  Preloads questions on app launch and refills in background.
//

import SwiftUI
import os
import Combine

/// Singleton manager for review question queue
class QuestionQueueManager: ObservableObject {
    static let shared = QuestionQueueManager()

    // MARK: - Configuration
    private let targetQueueSize = 20  // Always maintain 20 questions in backgroundQueue
    private let maxConcurrentFetches = 5  // Allow up to 5 simultaneous API calls
    private let logger = Logger(subsystem: "com.dogetionary", category: "QuestionQueue")

    // MARK: - Published State

    // Dual queue system: priority (search) + background (stream)
    @Published private(set) var priorityQueue: [BatchReviewQuestion] = []      // User-initiated searches (FIFO)
    @Published private(set) var backgroundQueue: [BatchReviewQuestion] = []    // Normal practice stream

    @Published private(set) var activeFetchCount = 0  // Track concurrent fetches
    @Published private(set) var hasMore = true
    @Published private(set) var totalAvailable = 0
    @Published private(set) var lastError: String?

    // Developer mode - controlled by DebugConfig
    @Published var debugMode = DebugConfig.enableDebugLogging

    // MARK: - Private State
    private var cancellables = Set<AnyCancellable>()

    private init() {
        logger.info("QuestionQueueManager initialized")
        // Note: Test settings change observation now handled via AppState in ReviewView
    }

    // MARK: - Queue Operations

    /// Get the next question from the queue (priority first, then background)
    func popQuestion() -> BatchReviewQuestion? {
        // Priority: check priorityQueue first, then backgroundQueue
        if !priorityQueue.isEmpty {
            let question = priorityQueue.removeFirst()
            logger.info("Popped from priorityQueue: \(question.word), remaining: \(self.priorityQueue.count)")

            // Cleanup player for video questions (after user has finished with it)
            if question.question.question_type == "video_mc",
               let videoId = question.question.video_id {
                AVPlayerManager.shared.removePlayer(videoId: videoId)
            }

            // No refill for priorityQueue (user-driven), but check backgroundQueue
            refillIfNeeded()

            return question
        } else if !backgroundQueue.isEmpty {
            let question = backgroundQueue.removeFirst()
            logger.info("Popped from backgroundQueue: \(question.word), remaining: \(self.backgroundQueue.count)")

            // Cleanup player for video questions (after user has finished with it)
            if question.question.question_type == "video_mc",
               let videoId = question.question.video_id {
                AVPlayerManager.shared.removePlayer(videoId: videoId)
            }

            // Trigger background refill
            refillIfNeeded()

            return question
        }

        return nil
    }

    /// Peek at the current question without removing it (priority first)
    func currentQuestion() -> BatchReviewQuestion? {
        return priorityQueue.first ?? backgroundQueue.first
    }

    /// Check if either queue has questions
    var hasQuestions: Bool {
        return !priorityQueue.isEmpty || !backgroundQueue.isEmpty
    }

    /// Total number of questions in both queues
    var queueCount: Int {
        return priorityQueue.count + backgroundQueue.count
    }

    /// Number of questions in priority queue (for debugging)
    var priorityQueueCount: Int {
        return priorityQueue.count
    }

    /// Number of questions in background queue (for debugging)
    var backgroundQueueCount: Int {
        return backgroundQueue.count
    }


    /// Stream append questions to priority queue as videos become ready
    /// Simple FIFO order - questions appended as each video downloads
    func streamAppendToPriorityQueue(
        _ questions: [BatchReviewQuestion],
        onFirstReady: @escaping () -> Void,
        onProgress: @escaping (Int, Int) -> Void,
        onComplete: @escaping () -> Void
    ) {
        guard !questions.isEmpty else {
            onComplete()
            return
        }

        logger.info("Starting stream append to priorityQueue: \(questions.count) questions")

        var readyCount = 0
        var firstQuestionReady = false
        let totalCount = questions.count

        // Start parallel downloads for all video questions
        for question in questions {
            guard question.question.question_type == "video_mc",
                  let videoId = question.question.video_id else {
                // Non-video question - append immediately
                DispatchQueue.main.async { [weak self] in
                    self?.appendToPriorityQueue(question)
                    readyCount += 1
                    onProgress(readyCount, totalCount)

                    if !firstQuestionReady {
                        firstQuestionReady = true
                        onFirstReady()
                    }

                    if readyCount == totalCount {
                        onComplete()
                    }
                }
                continue
            }

            // Check if video already cached
            let state = VideoService.shared.getDownloadState(videoId: videoId)

            if case .cached(let url, _, _) = state {
                // Already cached - ensure player exists
                AVPlayerManager.shared.createPlayer(videoId: videoId, url: url)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    self.appendToPriorityQueue(question)
                    readyCount += 1
                    self.logger.info("✓ Video \(videoId) cached, appended (\(readyCount)/\(totalCount))")
                    onProgress(readyCount, totalCount)

                    if !firstQuestionReady {
                        firstQuestionReady = true
                        onFirstReady()
                    }

                    if readyCount == totalCount {
                        onComplete()
                    }
                }
            } else {
                // Need to download - wait for completion
                self.logger.info("Downloading video \(videoId) for priority queue...")

                VideoService.shared.fetchVideo(videoId: videoId)
                    .receive(on: DispatchQueue.main)
                    .sink(
                        receiveCompletion: { [weak self] result in
                            guard let self = self else { return }

                            if case .failure(let error) = result {
                                self.logger.error("Failed to download video \(videoId): \(error.localizedDescription)")
                                // Skip this question on failure
                                readyCount += 1
                                onProgress(readyCount, totalCount)

                                if readyCount == totalCount {
                                    onComplete()
                                }
                            }
                        },
                        receiveValue: { [weak self] url in
                            guard let self = self else { return }

                            // Video ready - append to priority queue (FIFO)
                            self.appendToPriorityQueue(question)
                            readyCount += 1
                            self.logger.info("✓ Video \(videoId) ready, appended (\(readyCount)/\(totalCount))")
                            onProgress(readyCount, totalCount)

                            if !firstQuestionReady {
                                firstQuestionReady = true
                                self.logger.info("First question ready in priorityQueue")
                                onFirstReady()
                            }

                            if readyCount == totalCount {
                                self.logger.info("All \(totalCount) questions ready in priorityQueue")
                                onComplete()
                            }
                        }
                    )
                    .store(in: &self.cancellables)
            }
        }
    }

    /// Append question to priority queue (simple FIFO)
    private func appendToPriorityQueue(_ question: BatchReviewQuestion) {
        // Allow duplicates between queues (per Q5)
        // Only check for duplicates within priorityQueue itself
        guard !priorityQueue.contains(where: { $0.word == question.word }) else {
            logger.debug("Skipping duplicate in priorityQueue: \(question.word)")
            return
        }

        priorityQueue.append(question)
        logger.info("Appended to priorityQueue: \(question.word), total: \(self.priorityQueue.count)")
    }

    // MARK: - Fetching

    /// Initial load on app launch - fetch ONE-BY-ONE until target size
    func preloadQuestions() {
        // Don't preload if onboarding hasn't been completed yet
        // This prevents videos from downloading/playing during onboarding
        guard UserManager.shared.hasCompletedOnboarding else {
            logger.info("Skipping preload - onboarding not completed yet")
            return
        }

        guard backgroundQueue.isEmpty else {
            logger.info("Queue already has questions, skipping preload")
            return
        }

        logger.info("Preloading questions ONE-BY-ONE on app launch")
        // Fetch first question, then continue in refillIfNeeded
        fetchNextQuestion { [weak self] success in
            guard let self = self, success else { return }
            // After first question loads, fetch more in background
            self.refillIfNeeded()
        }
    }

    /// Background refill to maintain target queue size - CONCURRENT (up to 5 at once)
    /// Only refills backgroundQueue (priorityQueue is user-driven via search)
    func refillIfNeeded() {
        // Calculate how many questions we need in backgroundQueue
        let neededQuestions = targetQueueSize - backgroundQueue.count
        guard neededQuestions > 0 else {
            logger.debug("backgroundQueue size \(self.backgroundQueue.count) >= target \(self.targetQueueSize), skipping refill")
            return
        }

        // Calculate how many new fetches we can start (respect max concurrency)
        let availableSlots = maxConcurrentFetches - activeFetchCount
        guard availableSlots > 0 else {
            logger.debug("Already at max concurrency (\(self.activeFetchCount)/\(self.maxConcurrentFetches)), skipping refill")
            return
        }

        // Start multiple fetches in parallel (up to available slots)
        let fetchesToStart = min(neededQuestions, availableSlots)
        logger.info("Starting \(fetchesToStart) concurrent fetches (active: \(self.activeFetchCount), needed: \(neededQuestions))")

        for _ in 0..<fetchesToStart {
            activeFetchCount += 1

            fetchNextQuestion { [weak self] success in
                guard let self = self else { return }

                // Decrement counter on completion (success or failure)
                DispatchQueue.main.async {
                    self.activeFetchCount -= 1

                    // After each fetch completes, check if we need more
                    if self.backgroundQueue.count < self.targetQueueSize {
                        self.refillIfNeeded()
                    }
                }
            }
        }
    }

    /// Clear both queues (e.g., when user logs out or data changes)
    func clearQueue(preserveFirst: Bool = false) {
        if preserveFirst {
            // Preserve first from priorityQueue if exists, else from backgroundQueue
            if !priorityQueue.isEmpty {
                let first = priorityQueue[0]
                priorityQueue = [first]
                backgroundQueue.removeAll()

                logger.info("Queues cleared (preserved first from priorityQueue: \(first.word))")

                // Clear all players except current
                if let videoId = first.question.video_id {
                    AVPlayerManager.shared.clearExcept(videoId: videoId)
                } else {
                    AVPlayerManager.shared.clearAll()
                }
            } else if !backgroundQueue.isEmpty {
                let first = backgroundQueue[0]
                backgroundQueue = [first]

                logger.info("Queues cleared (preserved first from backgroundQueue: \(first.word))")

                // Clear all players except current
                if let videoId = first.question.video_id {
                    AVPlayerManager.shared.clearExcept(videoId: videoId)
                } else {
                    AVPlayerManager.shared.clearAll()
                }
            } else {
                // Both empty
                priorityQueue.removeAll()
                backgroundQueue.removeAll()
                logger.info("Queues cleared (both already empty)")
                AVPlayerManager.shared.clearAll()
            }
        } else {
            // Remove everything
            priorityQueue.removeAll()
            backgroundQueue.removeAll()

            logger.info("Queues cleared (all removed)")
            AVPlayerManager.shared.clearAll()
        }

        hasMore = true
        totalAvailable = 0
        lastError = nil
    }

    /// Force refresh - clear and reload (preserves current question)
    func forceRefresh() {
        clearQueue(preserveFirst: true)
        refillIfNeeded()  // Refill from position 1 onward
    }

    // MARK: - Private Methods

    /// Fetch the next single question and download video if needed before adding to queue
    private func fetchNextQuestion(completion: ((Bool) -> Void)? = nil) {
        // No guard needed - concurrency controlled by activeFetchCount in refillIfNeeded()
        // Each call increments activeFetchCount before calling this method

        lastError = nil

        let excludeWords = backgroundQueue.map { $0.word }
        let userManager = UserManager.shared
        let learningLang = userManager.learningLanguage
        let nativeLang = userManager.nativeLanguage

        // Always fetch from API with count=1 to get deterministic ordering
        // (Cache lookup would break ordering since we don't know which word is next)
        DictionaryService.shared.getReviewWordsBatch(count: 1, excludeWords: excludeWords) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // activeFetchCount decremented in refillIfNeeded() completion callback

                switch result {
                case .success(let response):
                    // Save fetched question to cache for future use
                    for question in response.questions {
                        QuestionCacheManager.shared.saveQuestion(
                            word: question.word,
                            learningLang: learningLang,
                            nativeLang: nativeLang,
                            question: question
                        )
                    }

                    // OPTION B: Download video BEFORE adding to queue (if video question)
                    self.downloadVideoIfNeededThenAddToQueue(
                        questions: response.questions,
                        completion: completion
                    )

                    self.hasMore = response.has_more
                    self.totalAvailable = response.total_available

                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.logger.error("Failed to fetch question: \(error.localizedDescription)")
                    completion?(false)
                }
            }
        }
    }

    /// Download video if needed, THEN add question to queue
    /// This ensures videos are ready before questions become available
    private func downloadVideoIfNeededThenAddToQueue(
        questions: [BatchReviewQuestion],
        completion: ((Bool) -> Void)?
    ) {
        guard let question = questions.first else {
            completion?(true)
            return
        }

        // Check if this is a video question
        if question.question.question_type == "video_mc",
           let videoId = question.question.video_id {

            // Check if video is already cached
            let state = VideoService.shared.getDownloadState(videoId: videoId)

            switch state {
            case .cached(let url, _, _):
                // Already cached - ensure AVPlayer is created, then add to queue
                logger.info("Video \(videoId) already cached, ensuring player exists")
                AVPlayerManager.shared.createPlayer(videoId: videoId, url: url)
                appendToBackgroundQueue([question])
                logger.info("Fetched 1 question (video cached), queue size: \(self.backgroundQueue.count)")
                completion?(true)

            case .downloading, .notStarted, .failed:
                // Need to download - wait for completion before adding to queue
                logger.info("Video \(videoId) needs download, waiting before adding to queue...")

                VideoService.shared.fetchVideo(videoId: videoId)
                    .receive(on: DispatchQueue.main)
                    .sink(
                        receiveCompletion: { [weak self] result in
                            guard let self = self else { return }

                            if case .failure(let error) = result {
                                self.logger.error("Failed to download video \(videoId): \(error.localizedDescription)")
                                // Add to queue anyway - VideoQuestionView will handle error
                                self.appendToBackgroundQueue([question])
                                self.logger.info("Fetched 1 question (video failed), queue size: \(self.backgroundQueue.count)")
                                completion?(false)
                            }
                        },
                        receiveValue: { [weak self] url in
                            guard let self = self else { return }

                            // Video downloaded successfully - AVPlayer already created by VideoService
                            self.logger.info("✓ Video \(videoId) downloaded, adding to queue")
                            self.appendToBackgroundQueue([question])
                            self.logger.info("Fetched 1 question (video ready), queue size: \(self.backgroundQueue.count)")
                            completion?(true)
                        }
                    )
                    .store(in: &self.cancellables)
            }

        } else {
            // Non-video question - add immediately
            appendToBackgroundQueue([question])
            logger.info("Fetched 1 question (non-video), queue size: \(self.backgroundQueue.count)")
            completion?(true)
        }
    }

    private func appendToBackgroundQueue(_ questions: [BatchReviewQuestion]) {
        for question in questions {
            // Allow duplicates between priority and background queues (per Q5)
            // Only check for duplicates within backgroundQueue itself
            guard !backgroundQueue.contains(where: { $0.word == question.word }) else {
                logger.debug("Skipping duplicate in backgroundQueue: \(question.word)")
                continue
            }
            backgroundQueue.append(question)
        }
    }
}
