//
//  ReviewView.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//

import SwiftUI
import os.log

// MARK: - Main Review View

struct ReviewView: View {
    private static let logger = Logger(subsystem: "com.dogetionary.app", category: "ReviewView")
    // Queue manager for instant question loading
    @StateObject private var queueManager = QuestionQueueManager.shared

    // ViewModel
    @StateObject private var viewModel = ReviewViewModel()

    // Current question is now computed directly from queue - no caching
    private var currentQuestion: BatchReviewQuestion? {
        return queueManager.currentQuestion()
    }

    var body: some View {
        ZStack {
            // Background
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar (fixed at top)
                PracticeStatusBar(
                    practiceStatus: viewModel.practiceStatus,
                    score: viewModel.currentScore,
                    scoreAnimationScale: viewModel.scoreAnimationScale,
                    scoreAnimationColor: viewModel.scoreAnimationColor,
                    showMiniCurve: viewModel.showMiniCurve,
                    curveIsCorrect: viewModel.curveIsCorrect,
                    onCurveDismiss: {
                        viewModel.dismissMiniCurve()
                    }
                )
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(
                    AppTheme.lightBlue
                        .shadow(color: AppTheme.subtleShadowColor, radius: 2, x: 0, y: 2)
                )

                // Main content area (fills remaining space)
                ZStack {
                    if viewModel.isLoadingStatus {
                        ProgressView("Loading practice...")
                    } else if let status = viewModel.practiceStatus, !status.has_practice, !queueManager.hasQuestions {
                        NothingToPracticeView()
                    } else if queueManager.isFetching && currentQuestion == nil {
                        ProgressView("Loading question...")
                    } else if let question = currentQuestion {
                        // Question card with definition below
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
                        .id(question.word)
                        .offset(x: viewModel.cardOffset)
                        .opacity(viewModel.cardOpacity)
                    } else if !queueManager.hasMore && !queueManager.hasQuestions {
                        NothingToPracticeView()
                    } else {
                        VStack(spacing: 16) {
                            Text("Loading questions...")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            if queueManager.isFetching {
                                ProgressView()
                            } else {
                                Button("Retry") {
                                    queueManager.forceRefresh()
                                    viewModel.loadPracticeStatus()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(AppTheme.errorColor)
                        .font(.caption)
                        .padding()
                }
            }

            // Badge celebration overlay
            if viewModel.showBadgeCelebration, let badge = viewModel.earnedBadge {
                BadgeCelebrationView(badge: badge) {
                    viewModel.dismissBadgeCelebration()
                }
            }

            // Debug overlay (bottom-left)
            VStack {
                Spacer()
                HStack {
                    QueueDebugOverlay()
                    Spacer()
                }
            }
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
        // Trigger queue refill when needed (UI updates automatically via computed property)
        .onChange(of: queueManager.queueCount) { _, _ in
            queueManager.refillIfNeeded()
        }
    }

}

// MARK: - Question Card View

struct QuestionCardView: View {
    let question: ReviewQuestion
    let definition: WordDefinitionResponse?
    let word: String
    let learningLanguage: String
    let nativeLanguage: String
    @Binding var isAnswered: Bool
    @Binding var wasCorrect: Bool?
    let onImmediateFeedback: ((Bool) -> Void)?
    let onAnswer: (Bool, String) -> Void
    let onSwipeComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var showSwipeHint = false
    @State private var isExcluded = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var swipeHintScale: CGFloat = 1.0

    private let swipeThreshold: CGFloat = 100

    // Convert WordDefinitionResponse to Definition model for DefinitionCard
    // Uses the same conversion logic as search results
    private var convertedDefinition: Definition? {
        guard let defResponse = definition else { return nil }
        return Definition(from: defResponse)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Question section
                EnhancedQuestionView(
                    question: question,
                    onImmediateFeedback: { isCorrect in
                        guard !isAnswered else { return }
                        onImmediateFeedback?(isCorrect)
                    },
                    onAnswer: { isCorrect in
                        guard !isAnswered else { return }
                        onAnswer(isCorrect, question.question_type)
                    }
                )
                .disabled(isAnswered)

                // Definition section (shown after answering)
                if isAnswered {
                    VStack(spacing: 16) {
                        // Definition card
                        if let def = convertedDefinition {
                            DefinitionCard(definition: def)
                                .padding(.horizontal)
                        }

                        // Exclude from practice button
                        Button(action: toggleExclusion) {
                            HStack {
                                Image(systemName: isExcluded ? "checkmark.circle.fill" : "xmark.circle")
                                    .font(.system(size: 16, weight: .medium))
                                Text(isExcluded ? "Excluded from practice" : "Exclude this word from practice")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundColor(isExcluded ? .white : AppTheme.errorColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isExcluded ? Color.gray : AppTheme.errorColor.opacity(AppTheme.lightOpacity))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)

                        // Prominent swipe indicator on the right side
                        Spacer()
                            .frame(height: 20)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: AppTheme.subtleShadowColor.opacity(2.0), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .offset(x: dragOffset)
        .gesture(
            isAnswered ?
            DragGesture()
                .onChanged { value in
                    if value.translation.width < 0 {
                        dragOffset = value.translation.width
                    }
                }
                .onEnded { value in
                    if value.translation.width < -swipeThreshold {
                        onSwipeComplete()
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = 0
                        }
                    }
                }
            : nil
        )
        .onChange(of: isAnswered) { _, newValue in
            if newValue {
                // Show swipe hint immediately (no delay)
                withAnimation(.easeIn) {
                    showSwipeHint = true
                }
            } else {
                // Reset scale when hiding
                swipeHintScale = 1.0
            }
        }
        .overlay(
            // Prominent swipe indicator on the right edge
            Group {
                if isAnswered && showSwipeHint {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(AppTheme.primaryGradient)

                            Text("next")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(AppTheme.primaryGradient)

                            Image(systemName: "chevron.left")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(AppTheme.primaryGradient)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(AppTheme.infoColor.opacity(AppTheme.lightOpacity))
                                .shadow(color: AppTheme.strongShadowColor, radius: 8, x: -4, y: 0)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppTheme.infoColor.opacity(AppTheme.veryStrongOpacity), lineWidth: 2)
                        )
                    }
                    .padding(.trailing, 8)
                    .scaleEffect(swipeHintScale)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .onAppear {
                        // Start pulsing animation
                        withAnimation(
                            Animation.easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: true)
                        ) {
                            swipeHintScale = 1.1
                        }
                    }
                }
            }
        )
        .overlay(
            Group {
                if showToast {
                    VStack {
                        Spacer()
                        Text(toastMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(AppTheme.strongOpacity * 2.67))
                            .cornerRadius(8)
                            .padding(.bottom, 50)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        )
    }

    private func toggleExclusion() {
        let newExcludedStatus = !isExcluded

        DictionaryService.shared.toggleExcludeFromPractice(word: word, excluded: newExcludedStatus) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.isExcluded = response.is_excluded
                    self.toastMessage = response.message
                    self.showToast = true

                    // Hide toast after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            self.showToast = false
                        }
                    }

                    // Track analytics
                    AnalyticsManager.shared.track(
                        action: response.is_excluded ? .savedMarkKnown : .savedMarkLearning,
                        metadata: ["word": self.word, "source": "review"]
                    )
                case .failure(let error):
                    self.toastMessage = "Failed to update: \(error.localizedDescription)"
                    self.showToast = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation {
                            self.showToast = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Practice Status Bar
struct PracticeStatusBar: View {
    let practiceStatus: PracticeStatusResponse?
    let score: Int
    let scoreAnimationScale: CGFloat
    let scoreAnimationColor: Color
    let showMiniCurve: Bool
    let curveIsCorrect: Bool
    let onCurveDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // New words indicator (from schedule)
            if let status = practiceStatus, status.new_words_count > 0 {
                StatusPill(
                    icon: "star.fill",
                    count: status.new_words_count,
                    label: "new",
                    color: AppTheme.infoColor
                )
            }

            // Test practice words indicator
            if let status = practiceStatus, status.test_practice_count > 0 {
                StatusPill(
                    icon: "book.fill",
                    count: status.test_practice_count,
                    label: "test",
                    color: AppTheme.warningColor
                )
            }

            // Non-test practice words indicator
            if let status = practiceStatus, status.non_test_practice_count > 0 {
                StatusPill(
                    icon: "repeat",
                    count: status.non_test_practice_count,
                    label: "prac",
                    color: AppTheme.successColor
                )
            }

            // Not-due-yet words indicator (extra practice)
            if let status = practiceStatus, status.not_due_yet_count > 0 {
                StatusPill(
                    icon: "arrow.counterclockwise",
                    count: status.not_due_yet_count,
                    label: "extra",
                    color: Color.purple
                )
            }

            // Mini curve animation (appears after answering)
            if showMiniCurve {
                MiniCurveAnimationView(
                    isCorrect: curveIsCorrect,
                    onDismiss: onCurveDismiss
                )
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // Score display
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.yellow)

                Text("\(score)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(scoreAnimationColor)
                    .scaleEffect(scoreAnimationScale)

                Text("pts")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(.systemBackground))
                    .shadow(color: AppTheme.subtleShadowColor.opacity(1.6), radius: 3, x: 0, y: 1)
            )
        }
    }
}

struct StatusPill: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - Nothing to Practice View
struct NothingToPracticeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(AppTheme.successColor)

            VStack(spacing: 8) {
                Text("All Caught Up!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("You have no words to practice right now.\nAdd more words or check back later!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
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
                    .foregroundColor(.white)
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
    private static let logger = Logger(subsystem: "com.dogetionary.app", category: "ReviewSession")

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
                                .foregroundColor(.blue)
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
                                    .foregroundColor(.green)
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
                    ProgressView("Loading definitions...")
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
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red)
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
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
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
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
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
    
//    private func loadWordDefinitions() {
//        isLoadingDefinitions = true
//        
//        DictionaryService.shared.searchWord(currentWord.word) { result in
//            DispatchQueue.main.async {
//                self.isLoadingDefinitions = false
//                
//                switch result {
//                case .success(let definitions):
//                    if !definitions.isEmpty {
//                        self.wordDefinitions = definitions
//                    }
//                case .failure(let error):
//                    print("Failed to load definitions: \(error.localizedDescription)")
//                }
//            }
//        }
//    }
    
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
                            .foregroundColor(.red)

                        Text("Incorrect - Study the definition")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)

                        Spacer()
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
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
                        .foregroundColor(.white)
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
            .navigationTitle("Word Definition")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Badge Celebration View

struct BadgeCelebrationView: View {
    let badge: NewBadge
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var iconRotation: Double = 0

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWithAnimation()
                }

            // Badge card
            VStack(spacing: 20) {
                // Badge icon with glow effect
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(badgeColor.opacity(0.3))
                        .frame(width: 140, height: 140)
                        .blur(radius: 20)

                    // Icon background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [badgeColor, badgeColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: badgeColor.opacity(0.5), radius: 10, x: 0, y: 5)

                    // Icon
                    Image(systemName: badge.symbol)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(iconRotation))
                }

                // Title
                Text("New Badge!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)

                // Badge name
                Text(badge.title)
                    .font(.title)
                    .fontWeight(.heavy)
                    .foregroundColor(badgeColor)

                // Milestone
                Text("\(badge.milestone) points reached")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                // Dismiss button
                Button(action: dismissWithAnimation) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 150)
                        .padding(.vertical, 12)
                        .background(badgeColor)
                        .cornerRadius(25)
                }
                .padding(.top, 10)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground).opacity(0.95))
                    .shadow(color: badgeColor.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }

            // Subtle icon animation
            withAnimation(.easeInOut(duration: 0.5).delay(0.3)) {
                iconRotation = 360
            }

            // Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                dismissWithAnimation()
            }
        }
    }

    private var badgeColor: Color {
        switch badge.tier {
        case "beginner":
            return .green
        case "intermediate":
            return .blue
        case "advanced":
            return .purple
        case "expert":
            return .orange
        default:
            return .blue
        }
    }

    private func dismissWithAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 0.8
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}

#Preview {
    ReviewView()
}
