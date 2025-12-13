//
//  QuestionCardView.swift
//  dogetionary
//
//  Created by Claude Code on 12/5/25.
//

import SwiftUI

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
    @State private var isAtBottom = false  // Track if scrolled to bottom
    @State private var indicatorOffset: CGFloat = 0  // Independent indicator animation
    @State private var indicatorOpacity: Double = 1.0  // Indicator fade animation

    private let swipeThreshold: CGFloat = 100  // Vertical swipe threshold

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
                            .foregroundColor(isExcluded ? AppTheme.bgPrimary : AppTheme.selectableTint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isExcluded ? AppTheme.panelFill : AppTheme.selectableTint.opacity(0.15))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)

                        // Add some spacing before bottom sentinel
                        Spacer()
                            .frame(height: 40)
                    }
                }

                // Bottom sentinel - detects when user scrolls to bottom
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: BottomReachedPreferenceKey.self,
                            value: geometry.frame(in: .named("scrollView")).maxY
                        )
                }
                .frame(height: 1)
            }
            .padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "scrollView")
        .background(Color.clear)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .offset(y: dragOffset)
        .onPreferenceChange(BottomReachedPreferenceKey.self) { maxY in
            // Detect when scrolled to bottom
            let screenHeight = UIScreen.main.bounds.height
            isAtBottom = maxY <= screenHeight + 50  // 50pt buffer
        }
        .simultaneousGesture(
            isAnswered && isAtBottom ?
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Detect upward swipe (negative translation.height)
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    // If swiped up past threshold, advance to next question
                    if value.translation.height < -swipeThreshold {
                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()

                        // Animate indicator upward and fade out independently
                        withAnimation(.easeOut(duration: 0.25)) {
                            indicatorOffset = -100  // Move up 100pt
                            indicatorOpacity = 0.0  // Fade out
                        }

                        // Animate card sliding up off screen
                        withAnimation(.easeInOut(duration: 0.3)) {
                            dragOffset = -UIScreen.main.bounds.height
                        }

                        // Call completion after animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onSwipeComplete()
                        }
                    } else {
                        // Not past threshold, spring back to original position
                        withAnimation(.spring()) {
                            dragOffset = 0
                            indicatorOffset = 0
                            indicatorOpacity = 1.0
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
        .onAppear {
            // Handle case where view loads with already-answered question (e.g., after refresh)
            if isAnswered {
                showSwipeHint = true
            }
        }
        .overlay(alignment: .bottom) {
            // Pull-to-advance indicator - show when at bottom
            if isAnswered && isAtBottom {
                PullToAdvanceIndicator(dragOffset: dragOffset, threshold: swipeThreshold)
                    .offset(y: indicatorOffset)  // Independent upward animation
                    .opacity(indicatorOpacity)   // Fade out animation
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                            .foregroundColor(AppTheme.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppTheme.black.opacity(AppTheme.strongOpacity * 2.67))
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

// MARK: - Bottom Detection

private struct BottomReachedPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Pull Indicator

private struct PullToAdvanceIndicator: View {
    let dragOffset: CGFloat
    let threshold: CGFloat

    private var shouldTrigger: Bool {
        abs(dragOffset) >= threshold
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.selectableTint)

            Text(shouldTrigger ? "RELEASE TO CONTINUE" : "PULL TO CONTINUE")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.selectableTint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.bgPrimary.opacity(0.9))
        )
        .padding(.bottom, 16)
    }
}

// MARK: - Preview

#Preview("Question Card - Unanswered") {
    @Previewable @State var isAnswered = false
    @Previewable @State var wasCorrect: Bool? = nil

    let sampleQuestion = ReviewQuestion(
        question_type: "mc_definition",
        word: "serendipity",
        question_text: "What does 'serendipity' mean?",
        options: [
            QuestionOption(id: "1", text: "A fortunate accident"),
            QuestionOption(id: "2", text: "A planned event"),
            QuestionOption(id: "3", text: "A sad occurrence"),
            QuestionOption(id: "4", text: "A regular routine")
        ],
        correct_answer: "A fortunate accident",
        sentence: nil,
        sentence_translation: nil,
        show_definition: false,
        audio_url: nil,
        evaluation_threshold: nil,
        video_id: nil,
        show_word_before_video: nil,
        audio_transcript: nil
    )

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        QuestionCardView(
            question: sampleQuestion,
            definition: nil,
            word: "serendipity",
            learningLanguage: "en",
            nativeLanguage: "zh",
            isAnswered: $isAnswered,
            wasCorrect: $wasCorrect,
            onImmediateFeedback: { _ in },
            onAnswer: { _, _ in
                isAnswered = true
            },
            onSwipeComplete: { }
        )
    }
}

#Preview("Question Card - Answered") {
    @Previewable @State var isAnswered = true
    @Previewable @State var wasCorrect: Bool? = true

    let sampleQuestion = ReviewQuestion(
        question_type: "mc_definition",
        word: "serendipity",
        question_text: "What does 'serendipity' mean?",
        options: [
            QuestionOption(id: "1", text: "A fortunate accident"),
            QuestionOption(id: "2", text: "A planned event"),
            QuestionOption(id: "3", text: "A sad occurrence"),
            QuestionOption(id: "4", text: "A regular routine")
        ],
        correct_answer: "A fortunate accident",
        sentence: nil,
        sentence_translation: nil,
        show_definition: false,
        audio_url: nil,
        evaluation_threshold: nil,
        video_id: nil,
        show_word_before_video: nil,
        audio_transcript: nil
    )

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        QuestionCardView(
            question: sampleQuestion,
            definition: nil,
            word: "serendipity",
            learningLanguage: "en",
            nativeLanguage: "zh",
            isAnswered: $isAnswered,
            wasCorrect: $wasCorrect,
            onImmediateFeedback: { _ in },
            onAnswer: { _, _ in },
            onSwipeComplete: { }
        )
    }
}
