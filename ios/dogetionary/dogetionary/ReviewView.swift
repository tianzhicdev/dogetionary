//
//  ReviewView.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//

import SwiftUI

// MARK: - Main Review View

struct ReviewView: View {
    // Queue manager for instant question loading
    @StateObject private var queueManager = QuestionQueueManager.shared

    // Current question from queue
    @State private var currentQuestion: BatchReviewQuestion?
    @State private var errorMessage: String?
    @State private var reviewStartTime: Date?

    // Practice status
    @State private var practiceStatus: PracticeStatusResponse?
    @State private var isLoadingStatus = true

    // Score tracking with animation
    @State private var currentScore: Int = 0
    @State private var scoreAnimationScale: CGFloat = 1.0
    @State private var scoreAnimationColor: Color = .primary

    // Badge celebration
    @State private var showBadgeCelebration = false
    @State private var earnedBadge: NewBadge?

    // Card swipe state
    @State private var cardOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1
    @State private var isAnswered = false
    @State private var wasCorrect: Bool? = nil
    @State private var pendingSubmission: (response: Bool, questionType: String)?

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar (fixed at top)
                PracticeStatusBar(
                    practiceStatus: practiceStatus,
                    score: currentScore,
                    scoreAnimationScale: scoreAnimationScale,
                    scoreAnimationColor: scoreAnimationColor
                )
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(
                    Color(red: 0.95, green: 0.97, blue: 1.0)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 2)
                )

                // Main content area (fills remaining space)
                ZStack {
                    if isLoadingStatus {
                        ProgressView("Loading practice...")
                    } else if let status = practiceStatus, !status.has_practice, !queueManager.hasQuestions {
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
                            isAnswered: $isAnswered,
                            wasCorrect: $wasCorrect,
                            onAnswer: handleAnswer,
                            onSwipeComplete: handleSwipeComplete
                        )
                        .id(question.word)
                        .offset(x: cardOffset)
                        .opacity(cardOpacity)
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
                                    loadPracticeStatus()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }
            }

            // Badge celebration overlay
            if showBadgeCelebration, let badge = earnedBadge {
                BadgeCelebrationView(badge: badge) {
                    showBadgeCelebration = false
                    earnedBadge = nil
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
            loadPracticeStatus()
        }
        .refreshable {
            await refreshPracticeStatus()
        }
        // Watch for queue updates when current question is nil
        .onChange(of: queueManager.queueCount) { _, newCount in
            if currentQuestion == nil && newCount > 0 {
                loadNextQuestionFromQueue()
            }
        }
    }

    // MARK: - Actions

    private func handleAnswer(_ isCorrect: Bool, questionType: String) {
        isAnswered = true
        wasCorrect = isCorrect
        pendingSubmission = (response: isCorrect, questionType: questionType)
    }

    private func handleSwipeComplete() {
        // Animate card off screen
        withAnimation(.easeOut(duration: 0.25)) {
            cardOffset = -UIScreen.main.bounds.width
            cardOpacity = 0
        }

        // Submit and load next after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let submission = pendingSubmission {
                submitReview(response: submission.response, questionType: submission.questionType)
            }
            // Reset card state for next question
            cardOffset = 0
            cardOpacity = 1
            isAnswered = false
            wasCorrect = nil
            pendingSubmission = nil
        }
    }

    private func loadPracticeStatus() {
        isLoadingStatus = true
        errorMessage = nil

        DictionaryService.shared.getPracticeStatus { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    self.practiceStatus = status
                    self.currentScore = status.score
                    self.isLoadingStatus = false

                    // If there's practice available, ensure the queue is loading
                    if status.has_practice {
                        // If queue is empty and not currently fetching, trigger a fetch
                        if !self.queueManager.hasQuestions && !self.queueManager.isFetching {
                            self.queueManager.forceRefresh()
                        }
                        // Try to load from queue (might be populated already)
                        self.loadNextQuestionFromQueue()
                    } else if self.queueManager.hasQuestions {
                        // No scheduled practice but queue has questions (e.g., extra practice)
                        self.loadNextQuestionFromQueue()
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.isLoadingStatus = false
                }
            }
        }
    }

    @MainActor
    private func refreshPracticeStatus() async {
        // Force refresh the queue
        queueManager.forceRefresh()

        await withCheckedContinuation { continuation in
            DictionaryService.shared.getPracticeStatus { result in
                DispatchQueue.main.async {
                    if case .success(let status) = result {
                        self.practiceStatus = status
                        self.currentScore = status.score
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func loadNextQuestionFromQueue() {
        // Peek at the current question (don't remove until submitted)
        if let nextQuestion = queueManager.currentQuestion() {
            currentQuestion = nextQuestion
            reviewStartTime = Date()
        } else if queueManager.hasMore {
            // Queue empty but more available - trigger fetch if not already fetching
            currentQuestion = nil
            if !queueManager.isFetching {
                queueManager.refillIfNeeded()
            }
        } else {
            // No more questions
            currentQuestion = nil
            refreshStatusAfterCompletion()
        }
    }

    private func advanceToNextQuestion() {
        // Remove the current question from queue (after submit)
        _ = queueManager.popQuestion()
        // Load the next one
        loadNextQuestionFromQueue()
    }

    private func refreshStatusAfterCompletion() {
        DictionaryService.shared.getPracticeStatus { result in
            DispatchQueue.main.async {
                if case .success(let status) = result {
                    self.practiceStatus = status
                }
            }
        }
    }

    private func submitReview(response: Bool, questionType: String) {
        guard let question = currentQuestion else { return }

        let word = question.word
        let learningLanguage = question.learning_language
        let nativeLanguage = question.native_language
        let responseTime = reviewStartTime.map { Int(Date().timeIntervalSince($0) * 1000) }

        // Track analytics
        let action: AnalyticsAction = response ? .reviewAnswerCorrect : .reviewAnswerIncorrect
        AnalyticsManager.shared.track(action: action, metadata: [
            "word": word,
            "question_type": questionType,
            "response_time_ms": responseTime ?? 0
        ])

        DictionaryService.shared.submitReview(
            word: word,
            learningLanguage: learningLanguage,
            nativeLanguage: nativeLanguage,
            response: response,
            questionType: questionType
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let submitResponse):
                    self.animateScoreChange(points: response ? 2 : 1, isCorrect: response)

                    if let newBadge = submitResponse.new_badge {
                        self.earnedBadge = newBadge
                        self.showBadgeCelebration = true
                    }

                    // Advance to next question (removes current from queue)
                    self.advanceToNextQuestion()
                    self.refreshStatusAfterCompletion()
                    BackgroundTaskManager.shared.updatePracticeCountsAfterReview()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func animateScoreChange(points: Int, isCorrect: Bool) {
        currentScore += points
        scoreAnimationColor = isCorrect ? .green : .orange

        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            scoreAnimationScale = 1.3
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                self.scoreAnimationScale = 1.0
                self.scoreAnimationColor = .primary
            }
        }
    }
}

// MARK: - Question Card View

struct QuestionCardView: View {
    let question: ReviewQuestion
    let definition: DefinitionData?
    let word: String
    let learningLanguage: String
    let nativeLanguage: String
    @Binding var isAnswered: Bool
    @Binding var wasCorrect: Bool?
    let onAnswer: (Bool, String) -> Void
    let onSwipeComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var showSwipeHint = false
    @State private var isExcluded = false
    @State private var showToast = false
    @State private var toastMessage = ""

    private let swipeThreshold: CGFloat = 100

    // Convert DefinitionData to Definition model for DefinitionCard
    private var convertedDefinition: Definition? {
        guard let def = definition else { return nil }

        let groupedDefinitions = Dictionary(grouping: def.definitions) { $0.type }
        let meanings = groupedDefinitions.map { (partOfSpeech, definitions) in
            let definitionDetails = definitions.map { d in
                let definitionText: String
                if let nativeDefinition = d.definition_native,
                   !nativeDefinition.isEmpty && nativeDefinition != d.definition {
                    definitionText = "\(d.definition)\n\n\(nativeDefinition)"
                } else {
                    definitionText = d.definition
                }
                return DefinitionDetail(
                    definition: definitionText,
                    example: d.examples.first,
                    synonyms: nil,
                    antonyms: d.cultural_notes != nil ? [d.cultural_notes!] : nil
                )
            }
            return Meaning(partOfSpeech: partOfSpeech, definitions: definitionDetails)
        }

        return Definition(
            id: UUID(),
            word: word,
            phonetic: def.phonetic,
            learning_language: learningLanguage,
            native_language: nativeLanguage,
            translations: def.translations ?? [],
            meanings: meanings,
            audioData: nil,
            hasWordAudio: false,
            exampleAudioAvailability: [:],
            validWordScore: def.valid_word_score ?? 1.0,
            suggestion: def.suggestion
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Question section
                EnhancedQuestionView(
                    question: question,
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
                            .foregroundColor(isExcluded ? .white : .red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isExcluded ? Color.gray : Color.red.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)

                        // Swipe hint
                        HStack {
                            Image(systemName: "arrow.left")
                            Text("Swipe left for next question")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 20)
                        .opacity(showSwipeHint ? 1 : 0)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.vertical, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
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
            }
        }
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
                            .background(Color.black.opacity(0.8))
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

    var body: some View {
        HStack(spacing: 8) {
            // New words indicator (from schedule)
            if let status = practiceStatus, status.new_words_count > 0 {
                StatusPill(
                    icon: "star.fill",
                    count: status.new_words_count,
                    label: "new",
                    color: .blue
                )
            }

            // Test practice words indicator
            if let status = practiceStatus, status.test_practice_count > 0 {
                StatusPill(
                    icon: "book.fill",
                    count: status.test_practice_count,
                    label: "test",
                    color: .orange
                )
            }

            // Non-test practice words indicator
            if let status = practiceStatus, status.non_test_practice_count > 0 {
                StatusPill(
                    icon: "repeat",
                    count: status.non_test_practice_count,
                    label: "prac",
                    color: .green
                )
            }

            // Not-due-yet words indicator (extra practice)
            if let status = practiceStatus, status.not_due_yet_count > 0 {
                StatusPill(
                    icon: "arrow.counterclockwise",
                    count: status.not_due_yet_count,
                    label: "extra",
                    color: .purple
                )
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
                    .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
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
                .foregroundColor(.green)

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
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)

                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(currentWord.native_language.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
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
                    print("Failed to load word definitions: \(error)")
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
    let definition: DefinitionData
    let learningLanguage: String
    let nativeLanguage: String
    let isCorrect: Bool
    let onNext: () -> Void

    // Convert DefinitionData to Definition model for DefinitionCard
    private var convertedDefinition: Definition {
        // Group definitions by type (part of speech)
        let groupedDefinitions = Dictionary(grouping: definition.definitions) { $0.type }
        let meanings = groupedDefinitions.map { (partOfSpeech, definitions) in
            let definitionDetails = definitions.map { def in
                // Show native definition if it exists and is different from main definition
                let definitionText: String
                if let nativeDefinition = def.definition_native,
                   !nativeDefinition.isEmpty && nativeDefinition != def.definition {
                    definitionText = "\(def.definition)\n\n\(nativeDefinition)"
                } else {
                    definitionText = def.definition
                }

                // Use first example (always in learning language)
                let exampleText = def.examples.first

                return DefinitionDetail(
                    definition: definitionText,
                    example: exampleText,
                    synonyms: nil,
                    antonyms: def.cultural_notes != nil ? [def.cultural_notes!] : nil
                )
            }
            return Meaning(partOfSpeech: partOfSpeech, definitions: definitionDetails)
        }

        return Definition(
            id: UUID(),
            word: word,
            phonetic: definition.phonetic,
            learning_language: learningLanguage,
            native_language: nativeLanguage,
            translations: definition.translations ?? [],
            meanings: meanings,
            audioData: nil,
            hasWordAudio: false,
            exampleAudioAvailability: [:],
            validWordScore: definition.valid_word_score ?? 1.0,
            suggestion: definition.suggestion
        )
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
