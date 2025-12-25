//
//  ReviewView.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//
//  Refactored by Claude Code on 12/5/25 - extracted inner views to separate files
//

import SwiftUI
import os.log

// MARK: - Main Review View

struct ReviewView: View {
    private static let logger = Logger(subsystem: "com.shojin.app", category: "ReviewView")
    // Queue manager for instant question loading
    @StateObject private var queueManager = QuestionQueueManager.shared

    // ViewModel
    @StateObject private var viewModel = ReviewViewModel()

    // Search ViewModel
    @StateObject private var searchViewModel = ReviewSearchViewModel()

    // App state for cross-view communication
    @Environment(AppState.self) private var appState

    // Search bar state (controlled by DailyProgressBanner in ContentView)
    @Binding var showSearchBar: Bool

    // Current question is now computed directly from queue - no caching
    private var currentQuestion: BatchReviewQuestion? {
        return queueManager.currentQuestion()
    }

    /// Generate stable, unique ID for SwiftUI view identity
    /// Uses video_id for video questions, saved_word_id for saved words, or combination for new words
    private func questionID(for question: BatchReviewQuestion) -> String {
        // Video questions: use video_id (always unique)
        if let videoId = question.question.video_id {
            return "video-\(videoId)"
        }

        // Saved words: use saved_word_id + type (unique per saved word)
        if let savedWordId = question.saved_word_id {
            return "saved-\(savedWordId)-\(question.question.question_type)"
        }

        // New words: use word + type + source (reasonably unique, duplicates prevented by queuedWords set)
        return "new-\(question.word)-\(question.question.question_type)-\(question.source)"
    }

    var body: some View {
        ZStack {
            // Gradient background
            AppTheme.verticalGradient2
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar overlay (shown when search button clicked)
                if showSearchBar {
                    searchBarView()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }

                // Main content area (fills remaining space)
                ZStack {
                    // Simple 2-state logic: Question OR Loading
                    // Backend always returns questions via 4-tier fallback (DUE → BUNDLE → EVERYDAY → RANDOM)
                    if let question = currentQuestion {
                        // State 1: Show question immediately
                        QuestionCardView(
                            question: question.question,
                            definition: question.definition,
                            word: question.word,
                            learningLanguage: question.learning_language,
                            nativeLanguage: question.native_language,
                            isAnswered: $viewModel.isAnswered,
                            wasCorrect: $viewModel.wasCorrect,
                            onImmediateFeedback: { isCorrect in
                                viewModel.showMiniCurveAnimation(isCorrect: isCorrect)
                            },
                            onAnswer: viewModel.handleAnswer,
                            onSwipeComplete: { viewModel.handleSwipeComplete(currentQuestion: currentQuestion) }
                        )
                        .id(questionID(for: question))
                        .offset(x: viewModel.cardOffset)
                        .opacity(viewModel.cardOpacity)
                    } else {
                        // State 2: Loading question from backend
                        ProgressView("LOADING QUESTION...")
                            .tint(AppTheme.accentCyan)
                            .foregroundColor(AppTheme.smallTitleText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .errorToast(message: viewModel.errorMessage) {
                viewModel.errorMessage = nil
            }
        }
        .sheet(isPresented: $searchViewModel.showDefinitionSheet) {
            // Definition modal (same pattern as VideoQuestionView:231)
            if let definition = searchViewModel.currentDefinition {
                NavigationView {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Info banner: Videos being prepared
                            HStack(spacing: 12) {
                                Image(systemName: "film.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppTheme.accentCyan)

                                Text("Videos for **\(definition.word)** will appear in Shojin shortly")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.bodyText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(
                                AppTheme.verticalGradient2.ignoresSafeArea())
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .padding(.top, 8)

                            DefinitionCard(definition: definition)
                                .padding(.horizontal)
                        }
                    }
                    .navigationTitle("Definition")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                searchViewModel.dismissDefinition()
                            }
                        }
                    }
                }
            }
        }
        .alert("Word Validation", isPresented: $searchViewModel.showValidationAlert) {
            if let suggestion = searchViewModel.validationSuggestion {
                Button(suggestion) {
                    searchViewModel.searchSuggestedWord {
                        withAnimation {
                            showSearchBar = false
                        }
                    }
                }
                Button("Yes, use original") {
                    searchViewModel.confirmOriginalWord()
                }
                Button("Cancel", role: .cancel) {
                    searchViewModel.cancelSearch()
                }
            } else {
                Button("Yes") {
                    searchViewModel.confirmOriginalWord()
                }
                Button("Cancel", role: .cancel) {
                    searchViewModel.cancelSearch()
                }
            }
        } message: {
            let confidence = searchViewModel.currentWordConfidence
            Text("This word seems unusual (confidence: \(Int(confidence * 100))%). Did you mean '\(searchViewModel.validationSuggestion ?? "")'?")
        }
        .onAppear {
            viewModel.loadPracticeStatus()

            // Refresh practice status when Practice tab appears
            Task {
                await UserManager.shared.refreshPracticeStatus()
            }
        }
        .refreshable {
            await viewModel.refreshPracticeStatus()
        }
        // Handle test settings changes via AppState
        .onChange(of: appState.testSettingsChanged) { _, changed in
            if changed {
                Self.logger.info("Test settings changed - refreshing question queue")
                queueManager.forceRefresh()
                viewModel.loadPracticeStatus()
            }
        }
    }

    // MARK: - Search Bar View

    @ViewBuilder
    private func searchBarView() -> some View {
        HStack(spacing: 12) {
            HStack {
                TextField("Search word...", text: $searchViewModel.searchText)
                    .font(.title2)
                    .foregroundColor(AppTheme.textFieldUserInput)
                    .onSubmit {
                        searchViewModel.searchWord {
                            // Close search bar when videos prepended
                            withAnimation {
                                showSearchBar = false
                            }
                        }
                    }

                if !searchViewModel.searchText.isEmpty {
                    Button(action: {
                        searchViewModel.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.selectableTint)
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppTheme.textFieldBackgroundColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppTheme.textFieldBorderColor, lineWidth: 2)
            )

            Button(action: {
                searchViewModel.searchWord {
                    // Close search bar when videos prepended
                    withAnimation {
                        showSearchBar = false
                    }
                }
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .foregroundColor(AppTheme.bigButtonForeground1)
                    .frame(width: 50, height: 50)
                    .background(AppTheme.bigButtonBackground1)
                    .cornerRadius(10)
            }
            .disabled(searchViewModel.searchText.isEmpty || searchViewModel.isLoading)
        }
    }
}

// MARK: - Today Complete View
struct TodayCompleteView: View {
    let staleWordsCount: Int
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 72))
                .foregroundColor(.yellow)

            VStack(spacing: 8) {
                Text("Today's Goal Complete!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("You've finished all new and due words for today.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Stale words option
            VStack(spacing: 12) {
                Text("Want to keep going?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button(action: onContinue) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Review \(staleWordsCount) stale word\(staleWordsCount == 1 ? "" : "s")")
                    }
                    .font(.headline)
                    .foregroundColor(AppTheme.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppTheme.primaryBlue)
                    .cornerRadius(12)
                }

                Text("Words not reviewed in 24+ hours")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

struct ReviewSessionView: View {
    private static let logger = Logger(subsystem: "com.shojin.app", category: "ReviewSession")

    let currentWord: ReviewWord
    let progress: String
    let onResponse: (Bool) -> Void
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var wordDefinitions: [Definition] = []
    @State private var isLoadingAudio = false
    @State private var isLoadingDefinitions = false
    @State private var hasAnswered = false
    @State private var userResponse: Bool? = nil
    @State private var exampleAudioData: Data?
    @State private var isLoadingExampleAudio = false
    
    // Computed property to get the first available example
    private var firstExample: String? {
        for definition in wordDefinitions {
            for meaning in definition.meanings {
                for defDetail in meaning.definitions {
                    if let example = defDetail.example, !example.isEmpty {
                        return example
                    }
                }
            }
        }
        return nil
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            HStack {
                Text(progress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            
            // Word card
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(currentWord.word)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    // Language pair display
                    HStack(spacing: 4) {
                        Text(currentWord.learning_language.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.infoColor.opacity(AppTheme.lightOpacity))
                            .foregroundColor(AppTheme.infoColor)
                            .cornerRadius(4)

                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(currentWord.native_language.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.successColor.opacity(AppTheme.lightOpacity))
                            .foregroundColor(AppTheme.successColor)
                            .cornerRadius(4)
                    }

                    // Audio controls
                    VStack(spacing: 8) {
                        // Pronunciation audio button
                        if !wordDefinitions.isEmpty, let audioData = wordDefinitions.first?.audioData {
                            Button(action: {
                                // Track review audio action
                                AnalyticsManager.shared.track(action: .reviewAudio, metadata: [
                                    "word": currentWord.word,
                                    "audio_type": "pronunciation"
                                ])

                                if audioPlayer.isPlaying {
                                    audioPlayer.stopAudio()
                                } else {
                                    audioPlayer.playAudio(from: audioData)
                                }
                            }) {
                                HStack {
                                    Image(systemName: audioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                        .font(.title2)
                                    Text("Pronunciation")
                                        .font(.subheadline)
                                }
                                .foregroundColor(AppTheme.infoColor)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Example audio button (if example is available)
                            if let example = firstExample {
                                Button(action: {
                                    // Track review audio action for examples
                                    AnalyticsManager.shared.track(action: .reviewAudio, metadata: [
                                        "word": currentWord.word,
                                        "audio_type": "example",
                                        "example_text": example
                                    ])

                                    playExampleAudio(example)
                                }) {
                                    HStack {
                                        if isLoadingExampleAudio {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "speaker.wave.2")
                                                .font(.title2)
                                        }
                                        Text("Example")
                                            .font(.subheadline)
                                    }
                                    .foregroundColor(AppTheme.successColor)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(isLoadingExampleAudio)
                                
                                // Show the example text
                                Text("\"" + example + "\"")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                        } else if isLoadingAudio && wordDefinitions.isEmpty {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading audio...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 32)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(16)
            .padding(.horizontal)
            
            // Show definitions if user answered "No"
            if hasAnswered && userResponse == false {
                if isLoadingDefinitions {
                    ProgressView()
                        .padding()
                } else if !wordDefinitions.isEmpty && wordDefinitions.first?.meanings.count ?? 0 > 0 {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(wordDefinitions) { definition in
                                DefinitionCard(definition: definition)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 300)
                }
            }
            
            // Question or instruction
            if !hasAnswered {
                Text("Do you know this word?")
                    .font(.title2)
                    .fontWeight(.medium)
                    .padding(.horizontal)
            }
            
            // Response buttons
            if !hasAnswered {
                HStack(spacing: 20) {
                    // No button
                    Button(action: {
                        userResponse = false
                        hasAnswered = true
                        isLoadingDefinitions = true
                        loadWordDefinitions()
                    }) {
                        HStack {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .fontWeight(.medium)
                            Text("No")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(AppTheme.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.errorColor)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Yes button
                    Button(action: {
                        userResponse = true
                        hasAnswered = true
                        onResponse(true)
                    }) {
                        HStack {
                            Image(systemName: "checkmark")
                                .font(.title3)
                                .fontWeight(.medium)
                            Text("Yes")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(AppTheme.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.successColor)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
            } else {
                // Next button after answering
                Button(action: {
                    if let response = userResponse {
                        onResponse(response)
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Next")
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(AppTheme.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppTheme.systemBlue)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .onAppear {
            loadWordAudio()
        }
        .onChange(of: currentWord.word) { _, newWord in
            // Reset state when word changes
            wordDefinitions = []
            hasAnswered = false
            userResponse = nil
            isLoadingDefinitions = false
            exampleAudioData = nil
            isLoadingExampleAudio = false
            loadWordAudio()
        }
    }

    private func loadWordAudio() {
        // Only show loading if we don't already have data for this word
        if wordDefinitions.isEmpty || wordDefinitions.first?.word != currentWord.word {
            isLoadingAudio = true
            
            // Load both audio and definitions to get examples
            loadWordDefinitionsWithAudio()
        }
    }
    
    private func loadWordDefinitionsWithAudio() {
        let learningLanguage = currentWord.learning_language
        
        // Load definitions first to get examples
        DictionaryService.shared.searchWord(
            currentWord.word,
            learningLanguage: currentWord.learning_language,
            nativeLanguage: currentWord.native_language
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let definitions):
                    if let definition = definitions.first {
                        // Load audio for the word
                        DictionaryService.shared.fetchAudioForText(self.currentWord.word, language: learningLanguage) { audioData in
                            DispatchQueue.main.async {
                                self.isLoadingAudio = false
                                
                                // Create definition with both full data and audio
                                let updatedDefinition = Definition(
                                    id: definition.id,
                                    word: definition.word,
                                    phonetic: definition.phonetic,
                                    learning_language: definition.learning_language,
                                    native_language: definition.native_language,
                                    translations: definition.translations,
                                    meanings: definition.meanings,
                                    audioData: audioData,
                                    hasWordAudio: audioData != nil,
                                    exampleAudioAvailability: definition.exampleAudioAvailability
                                )
                                self.wordDefinitions = [updatedDefinition]
                            }
                        }
                    } else {
                        self.isLoadingAudio = false
                        // Fallback: create minimal definition with just audio
                        DictionaryService.shared.fetchAudioForText(self.currentWord.word, language: learningLanguage) { audioData in
                            DispatchQueue.main.async {
                                if let audioData = audioData {
                                    let definition = Definition(
                                        id: UUID(),
                                        word: self.currentWord.word,
                                        phonetic: nil,
                                        learning_language: self.currentWord.learning_language,
                                        native_language: self.currentWord.native_language,
                                        translations: [],
                                        meanings: [],
                                        audioData: audioData,
                                        hasWordAudio: true,
                                        exampleAudioAvailability: [:]
                                    )
                                    self.wordDefinitions = [definition]
                                }
                            }
                        }
                    }
                case .failure(_):
                    // Fallback: load just audio without definitions
                    DictionaryService.shared.fetchAudioForText(self.currentWord.word, language: learningLanguage) { audioData in
                        DispatchQueue.main.async {
                            self.isLoadingAudio = false
                            if let audioData = audioData {
                                let definition = Definition(
                                    id: UUID(),
                                    word: self.currentWord.word,
                                    phonetic: nil,
                                    learning_language: self.currentWord.learning_language,
                                    native_language: self.currentWord.native_language,
                                    translations: [],
                                    meanings: [],
                                    audioData: audioData,
                                    hasWordAudio: true,
                                    exampleAudioAvailability: [:]
                                )
                                self.wordDefinitions = [definition]
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func loadWordDefinitions() {
        // Fetch full word definitions for display when user doesn't know the word
        DictionaryService.shared.searchWord(
            currentWord.word,
            learningLanguage: currentWord.learning_language,
            nativeLanguage: currentWord.native_language
        ) { result in
            DispatchQueue.main.async {
                self.isLoadingDefinitions = false
                
                switch result {
                case .success(let definitions):
                    // If we already have audio-only definition, update it with full data
                    if let existingDef = self.wordDefinitions.first, 
                       existingDef.word == self.currentWord.word,
                       let audioData = existingDef.audioData {
                        // Keep the audio data and add the full definition data
                        if let fullDef = definitions.first {
                            let updatedDef = Definition(
                                id: fullDef.id,
                                word: fullDef.word,
                                phonetic: fullDef.phonetic,
                                learning_language: fullDef.learning_language,
                                native_language: fullDef.native_language,
                                translations: fullDef.translations,
                                meanings: fullDef.meanings,
                                audioData: audioData, // Keep existing audio
                                hasWordAudio: fullDef.hasWordAudio,
                                exampleAudioAvailability: fullDef.exampleAudioAvailability
                            )
                            self.wordDefinitions = [updatedDef]
                        }
                    } else {
                        // No existing audio, just use the full definitions
                        self.wordDefinitions = definitions
                    }
                case .failure(let error):
                    // Handle error silently or show user-friendly message
                    Self.logger.error("Failed to load word definitions: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    private func playExampleAudio(_ text: String) {
        // If we already have audio data for this example, play it
        if let audioData = exampleAudioData {
            audioPlayer.playAudio(from: audioData)
            return
        }
        
        // Otherwise, fetch the audio data
        isLoadingExampleAudio = true
        let learningLanguage = currentWord.learning_language

        DictionaryService.shared.fetchAudioForText(text, language: learningLanguage) { audioData in
            DispatchQueue.main.async {
                self.isLoadingExampleAudio = false
                
                if let audioData = audioData {
                    self.exampleAudioData = audioData
                    self.audioPlayer.playAudio(from: audioData)
                }
            }
        }
    }
}


// MARK: - Definition Sheet View for Practice

struct DefinitionSheetView: View {
    let word: String
    let definition: WordDefinitionResponse
    let learningLanguage: String
    let nativeLanguage: String
    let isCorrect: Bool
    let onNext: () -> Void

    // Convert WordDefinitionResponse to Definition model for DefinitionCard
    // Uses the same conversion logic as search results
    private var convertedDefinition: Definition {
        return Definition(from: definition)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Feedback banner for incorrect answers
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(AppTheme.errorColor)

                        Text("Incorrect - Study the definition")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.errorColor)

                        Spacer()
                    }
                    .padding()
                    .background(AppTheme.errorColor.opacity(AppTheme.subtleOpacity))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Reuse DefinitionCard component
                    DefinitionCard(definition: convertedDefinition)
                        .padding(.horizontal)

                    // Next button
                    Button(action: onNext) {
                        HStack {
                            Text("Next")
                                .font(.headline)
                            Image(systemName: "arrow.right")
                        }
                        .foregroundColor(AppTheme.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppTheme.primaryBlue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .padding(.top)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Word Definition")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ReviewView(showSearchBar: .constant(false))
        .environment(AppState.shared)
}
