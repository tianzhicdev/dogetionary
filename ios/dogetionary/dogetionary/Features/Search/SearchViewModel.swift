//
//  SearchViewModel.swift
//  dogetionary
//
//  ViewModel for SearchView - manages search state and business logic
//

import SwiftUI
import StoreKit
import os.log

@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Dependencies
    private let dictionaryService: DictionaryService
    private let userManager: UserManager
    private let logger = Logger(subsystem: "com.shojin.app", category: "SearchViewModel")

    // MARK: - Published State

    // Search state
    @Published var searchText = ""
    @Published var definitions: [Definition] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showValidationAlert = false
    @Published var validationSuggestion: String?
    @Published var currentSearchQuery = ""
    @Published var currentWordConfidence: Double = 1.0
    @Published var pendingDefinitions: [Definition] = []

    // Test progress state
    @Published var testProgress: TestProgressResponse?
    @Published var isLoadingProgress = false

    // Achievement progress state
    @Published var achievementProgress: AchievementProgressResponse?
    @Published var isLoadingAchievements = false

    // Test vocabulary awards state
    @Published var testVocabularyAwards: TestVocabularyAwardsResponse?
    @Published var isLoadingTestVocabAwards = false

    // Progress bar expansion state
    @Published var isProgressBarExpanded = false

    // Video search workflow state
    @Published var isCheckingVideos = false
    @Published var videoSearchTriggered = false
    @Published var showVideoSearchMessage = false
    @Published var videoSearchMessageText = ""

    // MARK: - Computed Properties

    var isSearchActive: Bool {
        return !definitions.isEmpty || errorMessage != nil || isLoading
    }

    // MARK: - Initialization

    init(
        dictionaryService: DictionaryService = .shared,
        userManager: UserManager = .shared
    ) {
        self.dictionaryService = dictionaryService
        self.userManager = userManager
    }

    // MARK: - Public Methods

    func searchWord() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentSearchQuery = searchQuery

        // Track dictionary search
        AnalyticsManager.shared.track(action: .dictionarySearch, metadata: [
            "query": searchQuery,
            "language": userManager.learningLanguage
        ])

        isLoading = true
        errorMessage = nil

        dictionaryService.searchWord(searchQuery) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case .success(let definitions):
                    guard let definition = definitions.first else {
                        self.errorMessage = "No definition found"
                        return
                    }

                    // Store V3 validation data
                    self.currentWordConfidence = definition.validWordScore
                    self.validationSuggestion = definition.suggestion

                    if definition.isValid {
                        // High confidence (≥0.9) - show definition immediately
                        // Note: Word is auto-saved by backend on search
                        self.definitions = definitions

                        // Track successful search
                        AnalyticsManager.shared.track(action: .dictionaryAutoSave, metadata: [
                            "word": definition.word,
                            "confidence": definition.validWordScore,
                            "language": self.userManager.learningLanguage
                        ])

                        // Request app rating on first successful word lookup
                        if !self.userManager.hasRequestedAppRating {
                            try? await Task.sleep(nanoseconds: AppConstants.Delay.appRatingDelay) // 1 second
                            self.requestAppRating()
                        }

                        // NEW: Video workflow - check if word has videos
                        self.checkAndHandleVideoWorkflow(word: definition.word)
                    } else {
                        // Low confidence (<0.9) - store definition and show alert
                        self.pendingDefinitions = definitions
                        self.showValidationAlert = true

                        // Track validation event
                        AnalyticsManager.shared.track(action: .validationInvalid, metadata: [
                            "original_query": searchQuery,
                            "confidence": definition.validWordScore,
                            "suggested": definition.suggestion ?? "none",
                            "language": self.userManager.learningLanguage
                        ])
                    }

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.definitions = []
                }
            }
        }
    }

    func loadTestProgress() {
        isLoadingProgress = true

        dictionaryService.getTestProgress { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoadingProgress = false

                switch result {
                case .success(let progress):
                    self.testProgress = progress
                case .failure:
                    self.testProgress = nil
                }
            }
        }
    }

    func loadAchievementProgress() {
        isLoadingAchievements = true

        dictionaryService.getAchievementProgress { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoadingAchievements = false

                switch result {
                case .success(let progress):
                    self.achievementProgress = progress
                case .failure:
                    self.achievementProgress = nil
                }
            }
        }
    }

    func loadTestVocabularyAwards() {
        isLoadingTestVocabAwards = true

        dictionaryService.getTestVocabularyAwards { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoadingTestVocabAwards = false

                switch result {
                case .success(let awards):
                    self.testVocabularyAwards = awards
                case .failure:
                    self.testVocabularyAwards = nil
                }
            }
        }
    }

    func searchSuggestedWord() {
        if let suggestion = validationSuggestion {
            searchText = suggestion
            showValidationAlert = false
            searchWord()
        }
    }

    func showOriginalDefinition() {
        definitions = pendingDefinitions
        showValidationAlert = false
        pendingDefinitions = []
    }

    func cancelSearch() {
        showValidationAlert = false
        pendingDefinitions = []
    }

    func performSearchFromOnboarding(word: String) {
        searchText = word
        searchWord()
    }

    // MARK: - Private Methods

    private func requestAppRating() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
            userManager.markAppRatingRequested()
        }
    }

    // MARK: - Video Workflow

    private func checkAndHandleVideoWorkflow(word: String) {
        isCheckingVideos = true

        dictionaryService.checkWordHasVideos(word: word) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isCheckingVideos = false

                switch result {
                case .success(let hasVideos):
                    if hasVideos {
                        // Branch A: Has videos → fetch questions and navigate to Shojin
                        self.fetchVideoQuestionsAndNavigate(word: word)
                    } else {
                        // Branch B: No videos → trigger search
                        self.triggerVideoSearch(word: word)
                    }
                case .failure(let error):
                    // Fallback: trigger search anyway
                    self.logger.warning("Error checking videos for '\(word)': \(error.localizedDescription). Triggering search anyway.")
                    self.triggerVideoSearch(word: word)
                }
            }
        }
    }

    private func fetchVideoQuestionsAndNavigate(word: String) {
        logger.info("Fetching video questions for '\(word)'...")

        dictionaryService.getVideoQuestionsForWord(word: word, limit: 5) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                switch result {
                case .success(let questions):
                    guard !questions.isEmpty else {
                        self.logger.warning("No video questions returned for '\(word)' despite hasVideos=true")
                        return
                    }

                    // Insert to front of queue
                    QuestionQueueManager.shared.prependQuestions(questions)

                    // Switch to Shojin tab
                    AppState.shared.navigateToReview()

                    self.logger.info("Prepended \(questions.count) video questions for '\(word)' and navigated to Shojin")

                case .failure(let error):
                    self.logger.error("Failed to fetch video questions for '\(word)': \(error.localizedDescription)")
                }
            }
        }
    }

    private func triggerVideoSearch(word: String) {
        videoSearchTriggered = true
        videoSearchMessageText = "Searching... Videos will show up in Shojin later"
        showVideoSearchMessage = true

        logger.info("Triggering background video search for '\(word)'...")

        dictionaryService.triggerVideoSearch(word: word) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                // Auto-hide message after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.showVideoSearchMessage = false

                switch result {
                case .success:
                    self.logger.info("Video search triggered successfully for '\(word)'")
                case .failure(let error):
                    self.logger.error("Failed to trigger video search for '\(word)': \(error.localizedDescription)")
                }
            }
        }
    }
}
