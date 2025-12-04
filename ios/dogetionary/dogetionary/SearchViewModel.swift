//
//  SearchViewModel.swift
//  dogetionary
//
//  ViewModel for SearchView - manages search state and business logic
//

import SwiftUI
import StoreKit

@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Dependencies
    private let dictionaryService: DictionaryService
    private let userManager: UserManager

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
                        // High confidence (≥0.9) - show definition immediately + auto-save
                        self.definitions = definitions

                        // Auto-save the word
                        self.autoSaveWord(definition.word)

                        // Track successful search
                        AnalyticsManager.shared.track(action: .dictionaryAutoSave, metadata: [
                            "word": definition.word,
                            "confidence": definition.validWordScore,
                            "language": self.userManager.learningLanguage
                        ])

                        // Request app rating on first successful word lookup
                        if !self.userManager.hasRequestedAppRating {
                            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                            self.requestAppRating()
                        }
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

    private func autoSaveWord(_ word: String) {
        // Check if word is already saved
        dictionaryService.getSavedWords { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                switch result {
                case .success(let savedWords):
                    let alreadySaved = savedWords.contains { $0.word.lowercased() == word.lowercased() }

                    if !alreadySaved {
                        // Save the word
                        self.dictionaryService.saveWord(word) { saveResult in
                            Task { @MainActor in
                                switch saveResult {
                                case .success:
                                    // Track auto-save
                                    AnalyticsManager.shared.track(action: .dictionaryAutoSave, metadata: [
                                        "word": word,
                                        "language": self.userManager.learningLanguage
                                    ])

                                    // Notify DefinitionCards to update their bookmark state
                                    NotificationCenter.default.post(name: .wordAutoSaved, object: word)

                                case .failure(let error):
                                    print("Auto-save failed for word '\(word)': \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                case .failure(let error):
                    print("Failed to check saved words for auto-save: \(error.localizedDescription)")
                }
            }
        }
    }

    private func requestAppRating() {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
            userManager.markAppRatingRequested()
        }
    }
}
