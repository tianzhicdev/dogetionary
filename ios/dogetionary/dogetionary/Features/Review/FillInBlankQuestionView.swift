//
//  FillInBlankQuestionView.swift
//  dogetionary
//
//  Created by Claude Code on 12/5/25.
//

import SwiftUI

struct FillInBlankQuestionView: View {
    let question: ReviewQuestion
    let onImmediateFeedback: ((String) -> Void)?
    let onAnswer: (String) -> Void

    @State private var selectedAnswer: String? = nil
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 24) {
            // Sentence with blank - enhanced with colorful gradient background
            if let sentence = question.sentence {
                Text(sentence)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.bigTitleText)
                    .padding()

            }

            // Options
            VStack(spacing: 12) {
                ForEach(question.options ?? []) { option in
                    FillInBlankOptionButton(
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

struct FillInBlankOptionButton: View {
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

    var shadowColor: Color {
        if showFeedback && isSelected {
            return isCorrect ? AppTheme.successColor.opacity(0.8) : AppTheme.errorColor.opacity(0.8)
        } else if shouldShowAsCorrect {
            return AppTheme.successColor.opacity(0.6)
        } else if isSelected {
            return AppTheme.accentCyan.opacity(0.6)
        }
        return AppTheme.clear
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                // Option Text (word)
                Text(option.text)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.smallTitleText)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.clear)

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

#Preview("Fill In Blank - Not Answered") {
    let sampleQuestion = ReviewQuestion(
        question_type: "fill_blank",
        word: "beautiful",
        question_text: "Fill in the blank",
        options: [
            QuestionOption(id: "A", text: "beautiful"),
            QuestionOption(id: "B", text: "careful"),
            QuestionOption(id: "C", text: "wonderful"),
            QuestionOption(id: "D", text: "delightful")
        ],
        correct_answer: "A",
        sentence: "The sunset was absolutely _____ today.",
        sentence_translation: "今天的日落真是太美了。",
        show_definition: false,
        audio_url: nil,
        evaluation_threshold: nil
    )

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        FillInBlankQuestionView(
            question: sampleQuestion,
            onImmediateFeedback: { _ in },
            onAnswer: { _ in }
        )
    }
}

#Preview("Fill In Blank Option - Selected Correct") {
    @Previewable @State var showFeedback = true

    let sampleOption = QuestionOption(id: "A", text: "beautiful")

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            FillInBlankOptionButton(
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

#Preview("Fill In Blank Option - Selected Wrong") {
    @Previewable @State var showFeedback = true

    let sampleOption = QuestionOption(id: "B", text: "careful")

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            FillInBlankOptionButton(
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
