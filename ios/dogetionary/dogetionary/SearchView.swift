//
//  SearchView.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI
import StoreKit

struct SearchView: View {
    var selectedTab: Binding<Int>?
    var showProgressBar: Bool = true  // Default to true for backward compatibility

    @ObservedObject private var userManager = UserManager.shared
    @State private var searchText = ""
    @State private var definitions: [Definition] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showValidationAlert = false
    @State private var validationSuggestion: String?
    @State private var currentSearchQuery = ""
    @State private var currentWordConfidence: Double = 1.0
    @State private var pendingDefinitions: [Definition] = [] // Store definition while showing alert

    // Test progress state
    @State private var testProgress: TestProgressResponse?
    @State private var isLoadingProgress = false

    // Achievement progress state
    @State private var achievementProgress: AchievementProgressResponse?
    @State private var isLoadingAchievements = false

    // Test vocabulary awards state
    @State private var testVocabularyAwards: TestVocabularyAwardsResponse?
    @State private var isLoadingTestVocabAwards = false

    // Progress bar expansion state
    @State private var isProgressBarExpanded = false

    private var isSearchActive: Bool {
        return !definitions.isEmpty || errorMessage != nil || isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            // Show progress bar at top if user has schedule OR has achievement progress (for score mode)
            if showProgressBar, let progress = testProgress, (progress.has_schedule || achievementProgress != nil) {
                TestProgressBar(
                    progress: progress.progress,
                    totalWords: progress.total_words,
                    savedWords: progress.saved_words,
                    testType: progress.test_type ?? "NONE",
                    streakDays: progress.streak_days,
                    achievementProgress: achievementProgress,
                    testVocabularyAwards: testVocabularyAwards,
                    isExpanded: $isProgressBarExpanded
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            Spacer()

            // Main content
            ZStack {
                if isSearchActive {
                    // Active search layout - search bar at top
                    VStack(spacing: 20) {
                        searchBarView()
                            .padding(.horizontal)

                        if isLoading {
                            ProgressView("Searching...")
                                .padding()
                        }

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .padding()
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(definitions) { definition in
                                    DefinitionCard(definition: definition)
                                }
                            }
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Dismiss keyboard when tapping on results
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }

                        Spacer()
                    }
                } else {
                    // Landing page layout - centered search bar (hidden when progress bar is expanded)
                    if !isProgressBarExpanded {
                        VStack(spacing: 16) {
                            searchBarView()

                            // Practice button below search bar
                            if let tabBinding = selectedTab,
                               userManager.practiceCount > 0,
                               !isSearchActive {
                                Button(action: {
                                    tabBinding.wrappedValue = 2  // Navigate to Practice tab
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.title2)
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [.white, .white.opacity(0.9)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Ready to Practice")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                            Text("\(userManager.practiceCount) word\(userManager.practiceCount == 1 ? "" : "s") waiting")
                                                .font(.subheadline)
                                                .opacity(0.9)
                                        }

                                        Spacer()

                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .background(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.3, green: 0.4, blue: 0.95),
                                                Color(red: 0.6, green: 0.3, blue: 0.9)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(16)
                                    .shadow(color: Color.purple.opacity(0.3), radius: 12, x: 0, y: 6)
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                    }
                }
            }
            
            Spacer()
        }
//        .contentShape(Rectangle())
        .onTapGesture {
            // Dismiss keyboard when tapping outside text field
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .alert("Word Validation", isPresented: $showValidationAlert) {
            if let suggestion = validationSuggestion {
                // Has suggestion - show suggestion and "yes" options
                Button(suggestion) {
                    searchSuggestedWord()
                }
                Button("Yes") {
                    showOriginalDefinition()
                }
                Button("Cancel", role: .cancel) {
                    cancelSearch()
                }
            } else {
                // No suggestion - show "yes" and cancel options
                Button("Yes") {
                    showOriginalDefinition()
                }
                Button("Cancel", role: .cancel) {
                    cancelSearch()
                }
            }
        } message: {
            Text("\"\(currentSearchQuery)\" is likely not a valid word or phrase, are you sure you want to read its definition?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .performSearchFromOnboarding)) { notification in
            if let word = notification.object as? String {
                // Set the search text and perform search
                searchText = word
                searchWord()
            }
        }
        .onAppear {
            if showProgressBar {
                loadTestProgress()
                loadAchievementProgress()
                loadTestVocabularyAward()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wordAutoSaved)) { _ in
            // Refresh progress when a word is saved
            if showProgressBar {
                loadTestProgress()
                loadAchievementProgress()
                loadTestVocabularyAward()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .testSettingsChanged)) { _ in
            // Refresh progress when test settings change
            if showProgressBar {
                loadTestProgress()
                loadAchievementProgress()
                loadTestVocabularyAward()
            }
        }
    }
    
    @ViewBuilder
    private func searchBarView() -> some View {
        HStack(spacing: 12) {
            HStack {
                TextField("Enter a word or phrase", text: $searchText)
                    .font(.title2)
                    .foregroundColor(.primary)
                    .onSubmit {
                        searchWord()
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        definitions = []
                        errorMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.purple.opacity(0.6))
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.96, blue: 1.0),
                        Color(red: 0.98, green: 0.95, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.3),
                                Color.purple.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Color.purple.opacity(0.1), radius: 8, x: 0, y: 4)

            Button(action: {
                searchWord()
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.5, blue: 1.0),
                                Color(red: 0.6, green: 0.4, blue: 0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(searchText.isEmpty || isLoading)
        }
    }
    
    private func searchWord() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentSearchQuery = searchQuery

        // Track dictionary search
        AnalyticsManager.shared.track(action: .dictionarySearch, metadata: [
            "query": searchQuery,
            "language": UserManager.shared.learningLanguage
        ])

        isLoading = true
        errorMessage = nil

        // Single merged call to get both definition and validation
        DictionaryService.shared.searchWord(searchQuery) { result in
            DispatchQueue.main.async {
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
                            "language": UserManager.shared.learningLanguage
                        ])

                        // Request app rating on first successful word lookup
                        if !UserManager.shared.hasRequestedAppRating {
                            // Small delay to let the view fully appear before showing rating
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.requestAppRating()
                            }
                        }
                    } else {
                        // Low confidence (<0.9) - store definition and show alert
                        // User can choose to view this definition or search for suggestion
                        self.pendingDefinitions = definitions
                        self.showValidationAlert = true

                        // Track validation event
                        AnalyticsManager.shared.track(action: .validationInvalid, metadata: [
                            "original_query": searchQuery,
                            "confidence": definition.validWordScore,
                            "suggested": definition.suggestion ?? "none",
                            "language": UserManager.shared.learningLanguage
                        ])
                    }

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.definitions = []
                }
            }
        }
    }

    private func fetchAndDisplayDefinition(_ word: String, autoSave: Bool) {
        DictionaryService.shared.searchWord(word) { result in
            DispatchQueue.main.async {
                self.isLoading = false

                switch result {
                case .success(let definitions):
                    self.definitions = definitions

                    // Auto-save only if requested and we have definitions
                    if autoSave, let firstDefinition = definitions.first {
                        self.autoSaveWord(firstDefinition.word)
                    }

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.definitions = []
                }
            }
        }
    }


    private func showOriginalDefinition() {
        // Track user choosing original word
        AnalyticsManager.shared.track(action: .validationUseOriginal, metadata: [
            "original_query": currentSearchQuery,
            "suggested": validationSuggestion ?? "none",
            "language": UserManager.shared.learningLanguage
        ])

        showValidationAlert = false

        // Display the definition we already fetched (no need to ask backend again!)
        self.definitions = pendingDefinitions

        // Do NOT auto-save low-confidence words
    }

    private func searchSuggestedWord() {
        guard let suggestion = validationSuggestion else { return }

        // Track user accepting suggestion
        AnalyticsManager.shared.track(action: .validationAcceptSuggestion, metadata: [
            "original_query": currentSearchQuery,
            "accepted_suggestion": suggestion,
            "language": UserManager.shared.learningLanguage
        ])

        showValidationAlert = false
        searchText = suggestion
        isLoading = true

        // Fetch and show definition for suggested word AND auto-save it
        fetchAndDisplayDefinition(suggestion, autoSave: true)
    }

    private func cancelSearch() {
        // Track user canceling validation
        AnalyticsManager.shared.track(action: .validationCancel, metadata: [
            "original_query": currentSearchQuery,
            "suggested": validationSuggestion ?? "none",
            "language": UserManager.shared.learningLanguage
        ])

        // Clear everything and return to landing page
        showValidationAlert = false
        searchText = ""
        definitions = []
        pendingDefinitions = []
        errorMessage = nil
        currentSearchQuery = ""
        validationSuggestion = nil
        currentWordConfidence = 1.0
    }

    private func autoSaveWord(_ word: String) {
        // Check if word is already saved with current language pair to avoid duplicates
        DictionaryService.shared.getSavedWords { result in
            switch result {
            case .success(let savedWords):
                let isAlreadySaved = savedWords.contains {
                    $0.word.lowercased() == word.lowercased() &&
                    $0.learning_language == UserManager.shared.learningLanguage &&
                    $0.native_language == UserManager.shared.nativeLanguage
                }

                if !isAlreadySaved {
                    // Auto-save the word
                    DictionaryService.shared.saveWord(word) { saveResult in
                        DispatchQueue.main.async {
                            switch saveResult {
                            case .success:
                                // Track auto-save event
                                AnalyticsManager.shared.track(action: .dictionaryAutoSave, metadata: [
                                    "word": word,
                                    "language": UserManager.shared.learningLanguage
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

    private func loadTestProgress() {
        guard !isLoadingProgress else { return }

        isLoadingProgress = true
        DictionaryService.shared.getTestProgress { result in
            DispatchQueue.main.async {
                self.isLoadingProgress = false

                switch result {
                case .success(let progress):
                    self.testProgress = progress
                case .failure(let error):
                    print("Failed to load test progress: \(error.localizedDescription)")
                    // Silently fail - progress bar simply won't show
                }
            }
        }
    }

    private func loadAchievementProgress() {
        guard !isLoadingAchievements else { return }

        isLoadingAchievements = true
        DictionaryService.shared.getAchievementProgress { result in
            DispatchQueue.main.async {
                self.isLoadingAchievements = false

                switch result {
                case .success(let progress):
                    self.achievementProgress = progress
                case .failure(let error):
                    print("Failed to load achievement progress: \(error.localizedDescription)")
                    // Silently fail - achievements simply won't show
                }
            }
        }
    }

    private func loadTestVocabularyAward() {
        guard !isLoadingTestVocabAwards else { return }

        isLoadingTestVocabAwards = true
        DictionaryService.shared.getTestVocabularyAwards { result in
            DispatchQueue.main.async {
                self.isLoadingTestVocabAwards = false

                switch result {
                case .success(let awards):
                    self.testVocabularyAwards = awards
                case .failure(let error):
                    print("Failed to load test vocabulary awards: \(error.localizedDescription)")
                    // Silently fail - awards simply won't show
                }
            }
        }
    }

    private func requestAppRating() {
        // Request app store rating using native iOS API
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
            // Mark that we've requested rating so we don't ask again
            UserManager.shared.markAppRatingRequested()
        }
    }

}


#Preview {
    SearchView()
}
