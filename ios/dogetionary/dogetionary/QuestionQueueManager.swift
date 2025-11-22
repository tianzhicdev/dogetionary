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
    private let initialLoadCount = 3
    private let targetQueueSize = 10
    private let logger = Logger(subsystem: "com.dogetionary", category: "QuestionQueue")

    // MARK: - Published State
    @Published private(set) var questionQueue: [BatchReviewQuestion] = []
    @Published private(set) var queuedWords: Set<String> = []
    @Published private(set) var isFetching = false
    @Published private(set) var hasMore = true
    @Published private(set) var totalAvailable = 0
    @Published private(set) var lastError: String?

    // Debug mode - enable by default for development
    #if DEBUG
    @Published var debugMode = true
    #else
    @Published var debugMode = false
    #endif

    private init() {}

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

    /// Initial load on app launch - fetch 3 questions quickly
    func preloadQuestions() {
        guard questionQueue.isEmpty else {
            logger.info("Queue already has questions, skipping preload")
            return
        }

        logger.info("Preloading \(self.initialLoadCount) questions on app launch")
        fetchBatch(count: initialLoadCount) { [weak self] success in
            guard let self = self, success else { return }
            // After initial load, fetch more in background
            self.refillIfNeeded()
        }
    }

    /// Background refill to maintain target queue size
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
        fetchBatch(count: targetQueueSize)
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

    private func fetchBatch(count: Int, completion: ((Bool) -> Void)? = nil) {
        guard !isFetching else {
            completion?(false)
            return
        }

        DispatchQueue.main.async {
            self.isFetching = true
            self.lastError = nil
        }

        let excludeWords = Array(queuedWords)

        DictionaryService.shared.getReviewWordsBatch(count: count, excludeWords: excludeWords) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isFetching = false

                switch result {
                case .success(let response):
                    self.addToQueue(response.questions)
                    self.hasMore = response.has_more
                    self.totalAvailable = response.total_available
                    self.logger.info("Fetched \(response.questions.count) questions, queue size: \(self.questionQueue.count), has_more: \(response.has_more)")
                    completion?(true)

                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.logger.error("Failed to fetch batch: \(error.localizedDescription)")
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
                        .foregroundColor(.orange)
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
                            .foregroundColor(.red)
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
