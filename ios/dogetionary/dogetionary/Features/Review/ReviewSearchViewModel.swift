//
//  ReviewSearchViewModel.swift
//  dogetionary
//
//  Handles word search within TAT/Review view
//  Simple 2-branch logic: videos OR definition
//

import SwiftUI
import os.log

@MainActor
class ReviewSearchViewModel: ObservableObject {
    // MARK: - Dependencies
    private let dictionaryService: DictionaryService
    private let userManager: UserManager
    private let logger = Logger(subsystem: "com.shojin.app", category: "ReviewSearch")

    // MARK: - Published State
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var showDefinitionSheet = false
    @Published var currentDefinition: Definition?
    @Published var showValidationAlert = false
    @Published var validationSuggestion: String?
    @Published var currentWordConfidence: Double = 1.0

    // Streaming prepend state
    @Published var isStreamingPrepend = false
    @Published var streamProgress: (ready: Int, total: Int) = (0, 0)
    @Published var firstQuestionReady = false

    // MARK: - Initialization
    init(
        dictionaryService: DictionaryService = .shared,
        userManager: UserManager = .shared
    ) {
        self.dictionaryService = dictionaryService
        self.userManager = userManager
    }

    // MARK: - Public Methods

    func searchWord(onVideosPrepended: @escaping () -> Void) {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        logger.info("Searching for '\(query)' in TAT view")

        isLoading = true

        // Check if videos exist first
        dictionaryService.checkWordHasVideos(word: query) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                switch result {
                case .success(let hasVideos):
                    if hasVideos {
                        // Branch A: Has videos → fetch and prepend
                        self.fetchVideoQuestionsAndPrepend(word: query, onComplete: onVideosPrepended)
                    } else {
                        // Branch B: No videos → fetch definition
                        self.fetchDefinitionAndShow(word: query)
                    }

                case .failure(let error):
                    self.logger.error("Error checking videos for '\(query)': \(error.localizedDescription)")
                    // Fallback: fetch definition
                    self.fetchDefinitionAndShow(word: query)
                }
            }
        }
    }

    func searchSuggestedWord(onVideosPrepended: @escaping () -> Void) {
        if let suggestion = validationSuggestion {
            searchText = suggestion
            showValidationAlert = false
            searchWord(onVideosPrepended: onVideosPrepended)
        }
    }

    func confirmOriginalWord() {
        showValidationAlert = false

        // Show the definition that was already fetched
        if let definition = currentDefinition {
            showDefinitionSheet = true
            triggerVideoSearchSilently(word: definition.word)
        }
    }

    func cancelSearch() {
        showValidationAlert = false
        currentDefinition = nil
        isLoading = false
    }

    func dismissDefinition() {
        showDefinitionSheet = false
        currentDefinition = nil
        searchText = ""
    }

    // MARK: - Private Methods

    private func fetchVideoQuestionsAndPrepend(word: String, onComplete: @escaping () -> Void) {
        logger.info("Fetching video questions for '\(word)'")

        dictionaryService.getVideoQuestionsForWord(word: word, limit: 5) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                switch result {
                case .success(let questions):
                    guard !questions.isEmpty else {
                        self.logger.warning("No video questions returned for '\(word)'")
                        self.isLoading = false
                        return
                    }

                    self.logger.info("Starting streaming prepend for \(questions.count) video questions")

                    // Start streaming append to priority queue
                    self.isStreamingPrepend = true
                    self.streamProgress = (0, questions.count)
                    self.firstQuestionReady = false

                    QuestionQueueManager.shared.streamAppendToPriorityQueue(
                        questions,
                        onFirstReady: { [weak self] in
                            guard let self = self else { return }
                            Task { @MainActor in
                                self.firstQuestionReady = true
                                self.isLoading = false
                                self.logger.info("First question ready for '\(word)'")

                                // Clear search and close immediately when first question ready
                                self.searchText = ""
                                onComplete()
                            }
                        },
                        onProgress: { [weak self] ready, total in
                            guard let self = self else { return }
                            Task { @MainActor in
                                self.streamProgress = (ready, total)
                                self.logger.info("Streaming progress: \(ready)/\(total)")
                            }
                        },
                        onComplete: { [weak self] in
                            guard let self = self else { return }
                            Task { @MainActor in
                                self.isStreamingPrepend = false
                                self.logger.info("All video questions ready for '\(word)'")
                            }
                        }
                    )

                case .failure(let error):
                    self.logger.error("Failed to fetch video questions: \(error.localizedDescription)")
                    self.isLoading = false
                    self.isStreamingPrepend = false
                }
            }
        }
    }

    private func fetchDefinitionAndShow(word: String) {
        logger.info("Fetching definition for '\(word)'")

        dictionaryService.searchWord(word) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case .success(let definitions):
                    guard let definition = definitions.first else {
                        self.logger.warning("No definition found for '\(word)'")
                        return
                    }

                    self.currentDefinition = definition
                    self.currentWordConfidence = definition.validWordScore
                    self.validationSuggestion = definition.suggestion

                    if definition.isValid {
                        // High confidence → show definition immediately
                        self.showDefinitionSheet = true

                        // Trigger background video search silently
                        self.triggerVideoSearchSilently(word: definition.word)
                    } else {
                        // Low confidence → show validation alert first
                        self.showValidationAlert = true
                    }

                case .failure(let error):
                    self.logger.error("Failed to fetch definition: \(error.localizedDescription)")
                }
            }
        }
    }

    private func triggerVideoSearchSilently(word: String) {
        logger.info("Triggering background video search for '\(word)'")

        dictionaryService.triggerVideoSearch(word: word) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                self.logger.info("Video search triggered successfully for '\(word)'")
            case .failure(let error):
                self.logger.error("Failed to trigger video search: \(error.localizedDescription)")
            }
        }
    }
}
