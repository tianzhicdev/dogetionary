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
                            .foregroundColor(isExcluded ? AppTheme.bgPrimary : AppTheme.selectableTint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isExcluded ? AppTheme.panelFill : AppTheme.selectableTint.opacity(0.15))
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
        .background(Color.clear)
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
                                .foregroundStyle(AppTheme.gradient1)

                            Text("next")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(AppTheme.gradient1)

                            Image(systemName: "chevron.left")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(AppTheme.gradient1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(AppTheme.accentCyan.opacity(0.15))
                                .shadow(color: .black.opacity(0.3), radius: 8, x: -4, y: 0)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppTheme.accentCyan.opacity(0.5), lineWidth: 2)
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
        evaluation_threshold: nil
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
        evaluation_threshold: nil
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
