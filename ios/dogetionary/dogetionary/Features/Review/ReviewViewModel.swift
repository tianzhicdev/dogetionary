//
//  ReviewViewModel.swift
//  dogetionary
//
//  ViewModel for ReviewView - manages review session state and business logic
//

import SwiftUI
import Combine

@MainActor
class ReviewViewModel: ObservableObject {
    // MARK: - Dependencies
    private let dictionaryService: DictionaryService
    private let questionQueue: QuestionQueueManager
    private let userManager: UserManager

    // MARK: - Published State

    // Practice status
    @Published var practiceStatus: PracticeStatusResponse?
    @Published var isLoadingStatus = true
    @Published var errorMessage: String?

    // Score tracking with animation
    @Published var currentScore: Int = 0
    @Published var scoreAnimationScale: CGFloat = 1.0
    @Published var scoreAnimationColor: Color = .primary

    // Badge celebration
    @Published var showBadgeCelebration = false
    @Published var earnedBadge: NewBadge?

    // Mini curve animation
    @Published var showMiniCurve = false
    @Published var curveIsCorrect: Bool = false

    // Card swipe state
    @Published var cardOffset: CGFloat = 0
    @Published var cardOpacity: Double = 1
    @Published var isAnswered = false
    @Published var wasCorrect: Bool? = nil
    @Published var pendingSubmission: (response: Bool, questionType: String)?

    // MARK: - Private State
    private var reviewStartTime: Date?

    // MARK: - Initialization

    init(
        dictionaryService: DictionaryService = .shared,
        questionQueue: QuestionQueueManager = .shared,
        userManager: UserManager = .shared
    ) {
        self.dictionaryService = dictionaryService
        self.questionQueue = questionQueue
        self.userManager = userManager
    }

    // MARK: - Public Methods

    func loadPracticeStatus() {
        isLoadingStatus = true
        errorMessage = nil

        dictionaryService.getPracticeStatus { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                switch result {
                case .success(let status):
                    self.practiceStatus = status
                    self.currentScore = status.score
                    self.isLoadingStatus = false

                    // If there's practice available, ensure the queue is loading
                    if status.has_practice || self.questionQueue.hasQuestions {
                        if !self.questionQueue.hasQuestions && !self.questionQueue.isFetching {
                            self.questionQueue.forceRefresh()
                        }
                    }

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.isLoadingStatus = false
                }
            }
        }
    }

    func refreshPracticeStatus() async {
        // Force refresh the queue
        questionQueue.forceRefresh()

        await withCheckedContinuation { continuation in
            dictionaryService.getPracticeStatus { [weak self] result in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                Task { @MainActor in
                    if case .success(let status) = result {
                        self.practiceStatus = status
                        self.currentScore = status.score
                    }
                    continuation.resume()
                }
            }
        }
    }

    func handleAnswer(_ isCorrect: Bool, questionType: String) {
        isAnswered = true
        wasCorrect = isCorrect
        pendingSubmission = (response: isCorrect, questionType: questionType)
    }

    func handleSwipeComplete(currentQuestion: BatchReviewQuestion?) {
        // Animate card off screen
        withAnimation(.easeOut(duration: 0.25)) {
            cardOffset = -UIScreen.main.bounds.width
            cardOpacity = 0
        }

        // Submit and load next after animation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: AppConstants.Animation.standardDuration) // 0.3 seconds

            if let submission = pendingSubmission {
                await submitReview(
                    question: currentQuestion,
                    response: submission.response,
                    questionType: submission.questionType
                )
            }

            // Reset card state for next question
            cardOffset = 0
            cardOpacity = 1
            isAnswered = false
            wasCorrect = nil
            pendingSubmission = nil
        }
    }

    func dismissBadgeCelebration() {
        showBadgeCelebration = false
        earnedBadge = nil
    }

    func dismissMiniCurve() {
        showMiniCurve = false
    }

    func showMiniCurveAnimation(isCorrect: Bool) {
        curveIsCorrect = isCorrect
        showMiniCurve = true
    }

    // MARK: - Private Methods

    private func submitReview(question: BatchReviewQuestion?, response: Bool, questionType: String) async {
        guard let question = question else { return }

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

        await withCheckedContinuation { continuation in
            dictionaryService.submitReview(
                word: word,
                learningLanguage: learningLanguage,
                nativeLanguage: nativeLanguage,
                response: response,
                questionType: questionType
            ) { [weak self] result in
                guard let self = self else {
                    continuation.resume()
                    return
                }

                Task { @MainActor in
                    switch result {
                    case .success(let submitResponse):
                        self.animateScoreChange(points: response ? 2 : 1, isCorrect: response)

                        if let newBadge = submitResponse.new_badge {
                            self.earnedBadge = newBadge
                            self.showBadgeCelebration = true
                        }

                        // Advance to next question
                        self.advanceToNextQuestion()
                        self.refreshStatusAfterCompletion()

                        // Refresh practice status
                        await self.userManager.refreshPracticeStatus()

                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }

                    continuation.resume()
                }
            }
        }
    }

    private func advanceToNextQuestion() {
        // Remove the current question from queue
        _ = questionQueue.popQuestion()

        // Reset review start time for next question
        reviewStartTime = Date()

        // Trigger refill if needed
        if !questionQueue.hasQuestions && !questionQueue.hasMore {
            refreshStatusAfterCompletion()
        } else {
            questionQueue.refillIfNeeded()
        }
    }

    private func refreshStatusAfterCompletion() {
        dictionaryService.getPracticeStatus { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                if case .success(let status) = result {
                    self.practiceStatus = status
                }
            }
        }
    }

    private func animateScoreChange(points: Int, isCorrect: Bool) {
        currentScore += points
        scoreAnimationColor = isCorrect ? AppTheme.successColor : AppTheme.warningColor

        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            scoreAnimationScale = 1.3
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: AppConstants.Animation.shortDuration) // 0.2 seconds

            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                self.scoreAnimationScale = 1.0
                self.scoreAnimationColor = .primary
            }
        }
    }
}
