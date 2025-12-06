//
//  MultipleChoiceQuestionView.swift
//  dogetionary
//
//  Created by Claude Code on 12/5/25.
//

import SwiftUI

struct MultipleChoiceQuestionView: View {
    let question: ReviewQuestion
    let onImmediateFeedback: ((String) -> Void)?
    let onAnswer: (String) -> Void

    @State private var selectedAnswer: String? = nil
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 24) {
            // Question Text with gradient
            Text(question.question_text)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.gradient1)
                .padding(.horizontal)
                .padding(.vertical, 8)

            // Options
            VStack(spacing: 12) {
                ForEach(question.options ?? []) { option in
                    MultipleChoiceOptionButton(
                        option: option,
                        isSelected: selectedAnswer == option.id,
                        isCorrect: option.id == question.correct_answer,
                        correctAnswer: question.correct_answer,
                        showFeedback: showFeedback,
                        onTap: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedAnswer = option.id
                                showFeedback = true
                            }

                            // Call immediate feedback callback right away
                            onImmediateFeedback?(option.id)

                            // Delay before calling onAnswer to show feedback and correct answer
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                let isCorrect = option.id == question.correct_answer
                                onAnswer(option.id)
                            }
                        }
                    )
                    .disabled(showFeedback)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 32)
    }
}

struct MultipleChoiceOptionButton: View {
    let option: QuestionOption
    let isSelected: Bool
    let isCorrect: Bool
    let correctAnswer: String?
    let showFeedback: Bool
    let onTap: () -> Void

    // Show this option as correct if user was wrong and this is the correct answer
    var shouldShowAsCorrect: Bool {
        showFeedback && !isSelected && isCorrect
    }

    var backgroundGradient: LinearGradient {
        return AppTheme.feedbackGradient(
            isCorrect: isCorrect,
            isSelected: isSelected,
            showFeedback: showFeedback,
            shouldShowAsCorrect: shouldShowAsCorrect
        )
    }

    var borderGradient: LinearGradient? {
        return AppTheme.feedbackBorderGradient(
            isCorrect: isCorrect,
            isSelected: isSelected,
            showFeedback: showFeedback
        )
    }


    var body: some View {
        Button(action: onTap) {
            HStack {
                // Option ID (A, B, C, D) with gradient circle
                Text(option.id)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.selectableTint)
                    .frame(width: 32, height: 32)


                // Option Text
                Text(option.text)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.smallTitleText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Check mark for selected or correct answer
                if showFeedback && (isSelected || shouldShowAsCorrect) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(AppTheme.selectableTint)
                        .font(.title3)
                        .shadow(color: AppTheme.black.opacity(0.6), radius: 2, y: 1)
                }
            }
            .padding()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview("Multiple Choice - Not Answered") {
    let sampleQuestion = ReviewQuestion(
        question_type: "mc_definition",
        word: "ephemeral",
        question_text: "What does 'ephemeral' mean?",
        options: [
            QuestionOption(id: "A", text: "Lasting for a very short time"),
            QuestionOption(id: "B", text: "Eternal and unchanging"),
            QuestionOption(id: "C", text: "Related to physical objects"),
            QuestionOption(id: "D", text: "Mysterious and unknown")
        ],
        correct_answer: "A",
        sentence: nil,
        sentence_translation: nil,
        show_definition: false,
        audio_url: nil,
        evaluation_threshold: nil
    )

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        MultipleChoiceQuestionView(
            question: sampleQuestion,
            onImmediateFeedback: { _ in },
            onAnswer: { _ in }
        )
    }
}

#Preview("Multiple Choice Option - Selected Correct") {
    @Previewable @State var showFeedback = true

    let sampleOption = QuestionOption(id: "A", text: "Lasting for a very short time")

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            MultipleChoiceOptionButton(
                option: sampleOption,
                isSelected: true,
                isCorrect: true,
                correctAnswer: "A",
                showFeedback: showFeedback,
                onTap: { }
            )
            .padding()
        }
    }
}

#Preview("Multiple Choice Option - Selected Wrong") {
    @Previewable @State var showFeedback = true

    let sampleOption = QuestionOption(id: "B", text: "Eternal and unchanging")

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            MultipleChoiceOptionButton(
                option: sampleOption,
                isSelected: true,
                isCorrect: false,
                correctAnswer: "A",
                showFeedback: showFeedback,
                onTap: { }
            )
            .padding()
        }
    }
}
