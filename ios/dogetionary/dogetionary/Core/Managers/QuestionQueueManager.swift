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

        guard hasMore else {
            logger.debug("No more questions available, skipping refill")
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
            // Continue fetching until target size
            if self.questionQueue.count < self.targetQueueSize && self.hasMore {
                self.refillIfNeeded()
            }
        }
    }

    /// Clear the queue (e.g., when user logs out or data changes)
    func clearQueue() {
        questionQueue.removeAll()
        queuedWords.removeAll()
        hasMore = true
        totalAvailable = 0
        lastError = nil
        logger.info("Queue cleared")
    }

    /// Force refresh - clear and reload
    func forceRefresh() {
        clearQueue()
        preloadQuestions()
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
            logger.info("Prefetching \(videoIds.count) videos sequentially in background")
            // Videos will download in order - first question's video downloads first
            VideoService.shared.preloadVideos(videoIds: videoIds)
        }
    }
}

// MARK: - Debug View

struct QueueDebugOverlay: View {
    @ObservedObject var queueManager = QuestionQueueManager.shared

    var body: some View {
        if queueManager.debugMode {
            VStack(alignment: .leading, spacing: 4) {
                // Header with queue count
                HStack {
                    Image(systemName: "ladybug.fill")
                        .foregroundColor(AppTheme.warningColor)
                    Text("Queue: \(queueManager.queueCount)/\(queueManager.hasMore ? "10+" : "\(queueManager.totalAvailable)")")
                        .font(.caption.monospaced())
                }

                // Show queued words with type and position
                if !queueManager.questionQueue.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(queueManager.questionQueue.prefix(5).enumerated()), id: \.element.word) { index, question in
                            HStack(spacing: 4) {
                                // Position in local queue
                                Text("\(index)")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                    .frame(width: 12, alignment: .trailing)

                                // Source type badge
                                Text(question.sourceLabel)
                                    .font(.caption2.bold())
                                    .foregroundColor(colorForSource(question.source))
                                    .frame(width: 30, alignment: .leading)

                                // Word
                                Text(question.word)
                                    .font(.caption2.monospaced())
                                    .lineLimit(1)
                            }
                        }
                        if queueManager.queueCount > 5 {
                            Text("... +\(queueManager.queueCount - 5) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Fetching/error status
                HStack(spacing: 8) {
                    if queueManager.isFetching {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Fetching...")
                            .font(.caption2)
                    }

                    if queueManager.lastError != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.errorColor)
                            .font(.caption2)
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground).opacity(0.95))
                    .shadow(radius: 2)
            )
            .padding(8)
        }
    }

    private func colorForSource(_ source: String) -> Color {
        // Colors match priority order: new -> test_practice -> non_test_practice -> not_due_yet
        switch source {
        case "new": return .blue              // Priority 1: New scheduled words
        case "test_practice": return .orange  // Priority 2: Test practice words
        case "non_test_practice": return .green // Priority 3: Non-test practice words
        case "not_due_yet": return .purple    // Priority 4: Extra practice (not due yet)
        default: return .gray
        }
    }
}
