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
    private let targetQueueSize = 20  // Always maintain 20 questions
    private let maxConcurrentFetches = 5  // Allow up to 5 simultaneous API calls
    private let logger = Logger(subsystem: "com.dogetionary", category: "QuestionQueue")

    // MARK: - Published State
    @Published private(set) var questionQueue: [BatchReviewQuestion] = []
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

    /// Get the next question from the queue
    func popQuestion() -> BatchReviewQuestion? {
        guard !questionQueue.isEmpty else { return nil }
        let question = questionQueue.removeFirst()
        logger.info("Popped question: \(question.word), queue size: \(self.questionQueue.count)")

        // Cleanup player for video questions (after user has finished with it)
        if question.question.question_type == "video_mc",
           let videoId = question.question.video_id {
            AVPlayerManager.shared.removePlayer(videoId: videoId)
        }

        // Trigger background refill if needed
        refillIfNeeded()

        return question
    }

    /// Peek at the current question without removing it
    func currentQuestion() -> BatchReviewQuestion? {
        return questionQueue.first
    }

    /// Check if queue has questions
    var hasQuestions: Bool {
        return !questionQueue.isEmpty
    }

    /// Number of questions in queue
    var queueCount: Int {
        return questionQueue.count
    }

    /// Prepend questions to the FRONT of the queue (for instant video practice)
    func prependQuestions(_ questions: [BatchReviewQuestion]) {
        guard !questions.isEmpty else { return }

        // Insert at beginning
        questionQueue.insert(contentsOf: questions, at: 0)

        // Prefetch videos for video_mc questions (same as addToQueue)
//        prefetchVideosFromQueue(questions)

        logger.info("Prepended \(questions.count) questions to queue, new size: \(self.questionQueue.count)")
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

        guard questionQueue.isEmpty else {
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
    func refillIfNeeded() {
        // Calculate how many questions we need
        let neededQuestions = targetQueueSize - questionQueue.count
        guard neededQuestions > 0 else {
            logger.debug("Queue size \(self.questionQueue.count) >= target \(self.targetQueueSize), skipping refill")
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
                    if self.questionQueue.count < self.targetQueueSize {
                        self.refillIfNeeded()
                    }
                }
            }
        }
    }

    /// Clear the queue (e.g., when user logs out or data changes)
    func clearQueue(preserveFirst: Bool = false) {
        if preserveFirst && !questionQueue.isEmpty {
            // Keep only the first question
            let first = questionQueue[0]
            questionQueue = [first]

            logger.info("Queue cleared (preserved first question: \(first.word))")

            // Clear all cached players except current question's video
            if let videoId = first.question.video_id {
                AVPlayerManager.shared.clearExcept(videoId: videoId)
            } else {
                AVPlayerManager.shared.clearAll()
            }
        } else {
            // Remove everything
            questionQueue.removeAll()

            logger.info("Queue cleared (all questions removed)")

            // Clear all cached players
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

        let excludeWords = questionQueue.map { $0.word }
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
                addToQueue([question])
                logger.info("Fetched 1 question (video cached), queue size: \(self.questionQueue.count)")
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
                                self.addToQueue([question])
                                self.logger.info("Fetched 1 question (video failed), queue size: \(self.questionQueue.count)")
                                completion?(false)
                            }
                        },
                        receiveValue: { [weak self] url in
                            guard let self = self else { return }

                            // Video downloaded successfully - AVPlayer already created by VideoService
                            self.logger.info("✓ Video \(videoId) downloaded, adding to queue")
                            self.addToQueue([question])
                            self.logger.info("Fetched 1 question (video ready), queue size: \(self.questionQueue.count)")
                            completion?(true)
                        }
                    )
                    .store(in: &self.cancellables)
            }

        } else {
            // Non-video question - add immediately
            addToQueue([question])
            logger.info("Fetched 1 question (non-video), queue size: \(self.questionQueue.count)")
            completion?(true)
        }
    }

    private func addToQueue(_ questions: [BatchReviewQuestion]) {
        for question in questions {
            guard !questionQueue.contains(where: { $0.word == question.word }) else {
                logger.debug("Skipping duplicate word: \(question.word)")
                continue
            }
            questionQueue.append(question)
        }
    }
}
