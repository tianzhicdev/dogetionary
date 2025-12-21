//
//  QuestionQueueManager.swift
//  dogetionary
//
//  Manages a local queue of review questions for instant transitions.
//  Preloads questions on app launch and refills in background.
//

import SwiftUI
import os

/// Singleton manager for review question queue
class QuestionQueueManager: ObservableObject {
    static let shared = QuestionQueueManager()

    // MARK: - Configuration
    private let targetQueueSize = 10  // Always maintain 10 questions
    private let logger = Logger(subsystem: "com.dogetionary", category: "QuestionQueue")

    // MARK: - Published State
    @Published private(set) var questionQueue: [BatchReviewQuestion] = []
    @Published private(set) var queuedWords: Set<String> = []
    @Published private(set) var isFetching = false
    @Published private(set) var hasMore = true
    @Published private(set) var totalAvailable = 0
    @Published private(set) var lastError: String?

    // Developer mode - controlled by DebugConfig
    @Published var debugMode = DebugConfig.enableDebugLogging

    private init() {
        logger.info("QuestionQueueManager initialized")
        // Note: Test settings change observation now handled via AppState in ReviewView
    }

    // MARK: - Queue Operations

    /// Get the next question from the queue
    func popQuestion() -> BatchReviewQuestion? {
        guard !questionQueue.isEmpty else { return nil }
        let question = questionQueue.removeFirst()
        queuedWords.remove(question.word)
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

    // MARK: - Fetching

    /// Initial load on app launch - fetch ONE-BY-ONE until target size
    func preloadQuestions() {
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

    /// Background refill to maintain target queue size - ONE-BY-ONE
    func refillIfNeeded() {
        guard !isFetching else {
            logger.debug("Already fetching, skipping refill")
            return
        }

        guard questionQueue.count < targetQueueSize else {
            logger.debug("Queue size \(self.questionQueue.count) >= target \(self.targetQueueSize), skipping refill")
            return
        }

        logger.info("Refilling queue: current=\(self.questionQueue.count), target=\(self.targetQueueSize)")
        // Fetch ONE question at a time
        fetchNextQuestion { [weak self] success in
            guard let self = self, success else { return }
            // Continue fetching until target size (backend always has questions via 4-tier fallback)
            if self.questionQueue.count < self.targetQueueSize {
                self.refillIfNeeded()
            }
        }
    }

    /// Clear the queue (e.g., when user logs out or data changes)
    func clearQueue(preserveFirst: Bool = false) {
        if preserveFirst && !questionQueue.isEmpty {
            // Keep only the first question
            let first = questionQueue[0]
            questionQueue = [first]
            queuedWords = [first.word]

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
            queuedWords.removeAll()

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

    /// Fetch the next single question (cache-first, then API)
    private func fetchNextQuestion(completion: ((Bool) -> Void)? = nil) {
        guard !isFetching else {
            completion?(false)
            return
        }

        DispatchQueue.main.async {
            self.isFetching = true
            self.lastError = nil
        }

        let excludeWords = Array(queuedWords)
        let userManager = UserManager.shared
        let learningLang = userManager.learningLanguage
        let nativeLang = userManager.nativeLanguage

        // Always fetch from API with count=1 to get deterministic ordering
        // (Cache lookup would break ordering since we don't know which word is next)
        DictionaryService.shared.getReviewWordsBatch(count: 1, excludeWords: excludeWords) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetching = false

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

                    self.addToQueue(response.questions)
                    self.hasMore = response.has_more
                    self.totalAvailable = response.total_available
                    self.logger.info("Fetched 1 question, queue size: \(self.questionQueue.count), has_more: \(response.has_more)")
                    completion?(true)

                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.logger.error("Failed to fetch question: \(error.localizedDescription)")
                    completion?(false)
                }
            }
        }
    }

    private func addToQueue(_ questions: [BatchReviewQuestion]) {
        for question in questions {
            guard !queuedWords.contains(question.word) else {
                logger.debug("Skipping duplicate word: \(question.word)")
                continue
            }
            questionQueue.append(question)
            queuedWords.insert(question.word)
        }

        // Prefetch videos for video_mc questions
        prefetchVideosFromQueue(questions)
    }

    private func prefetchVideosFromQueue(_ questions: [BatchReviewQuestion]) {
        // Extract video IDs in order from the question queue
        let videoIds = questions.compactMap { question -> Int? in
            guard question.question.question_type == "video_mc",
                  let videoId = question.question.video_id else {
                return nil
            }
            return videoId
        }

        if !videoIds.isEmpty {
            logger.info("Prefetching \(videoIds.count) videos in background")

            // Download videos (non-blocking, sequential, returns immediately)
            VideoService.shared.preloadVideos(videoIds: videoIds)
        }
    }
}
