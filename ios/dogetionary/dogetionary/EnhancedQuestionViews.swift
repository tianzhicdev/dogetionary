//
//  EnhancedQuestionViews.swift
//  dogetionary
//
//  Created for Enhanced Review System
//

import SwiftUI

// MARK: - Multiple Choice Question View

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
                .foregroundStyle(AppTheme.primaryGradient)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.infoColor.opacity(AppTheme.subtleOpacity), Color.purple.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: AppTheme.infoColor.opacity(AppTheme.mediumOpacity), radius: 8, y: 4)

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

    var shadowColor: Color {
        if showFeedback && isSelected {
            return isCorrect ? AppTheme.successColor.opacity(AppTheme.veryStrongOpacity) : AppTheme.errorColor.opacity(AppTheme.veryStrongOpacity)
        } else if shouldShowAsCorrect {
            return AppTheme.successColor.opacity(AppTheme.strongOpacity)
        } else if isSelected {
            return AppTheme.infoColor.opacity(AppTheme.strongOpacity)
        }
        return Color.clear
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                // Option ID (A, B, C, D) with gradient circle
                Text(option.id)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(backgroundGradient)
                            .shadow(color: shadowColor, radius: 6, y: 3)
                    )

                // Option Text
                Text(option.text)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Check mark for selected or correct answer
                if showFeedback && (isSelected || shouldShowAsCorrect) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.title3)
                        .shadow(color: Color.black.opacity(AppTheme.strongOpacity), radius: 2, y: 1)
                }
            }
            .padding()
            .background(backgroundGradient)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        borderGradient != nil ?
                            AnyShapeStyle(borderGradient!) :
                            AnyShapeStyle(Color.clear),
                        lineWidth: 3
                    )
            )
            .shadow(color: shadowColor, radius: 10, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Fill in the Blank Question View

struct FillInBlankQuestionView: View {
    let question: ReviewQuestion
    let onImmediateFeedback: ((String) -> Void)?
    let onAnswer: (String) -> Void

    @State private var selectedAnswer: String? = nil
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 24) {
            // Question Text with gradient
//            Text(question.question_text)
//                .font(.title3)
//                .fontWeight(.bold)
//                .multilineTextAlignment(.center)
//                .foregroundStyle(
//                    LinearGradient(
//                        colors: [Color(red: 0.3, green: 0.4, blue: 0.95), Color(red: 0.6, green: 0.3, blue: 0.9)],
//                        startPoint: .leading,
//                        endPoint: .trailing
//                    )
//                )
//                .padding(.horizontal)

            // Sentence with blank - enhanced with colorful gradient background
            if let sentence = question.sentence {
                Text(sentence)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.primaryGradient)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppTheme.secondaryGradient)
                            .shadow(color: AppTheme.infoColor.opacity(AppTheme.mediumHighOpacity), radius: 8, y: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [AppTheme.infoColor.opacity(AppTheme.strongOpacity), Color.purple.opacity(AppTheme.strongOpacity)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .padding(.horizontal)
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
            return isCorrect ? AppTheme.successColor.opacity(AppTheme.veryStrongOpacity) : AppTheme.errorColor.opacity(AppTheme.veryStrongOpacity)
        } else if shouldShowAsCorrect {
            return AppTheme.successColor.opacity(AppTheme.strongOpacity)
        } else if isSelected {
            return AppTheme.infoColor.opacity(AppTheme.strongOpacity)
        }
        return Color.clear
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                // Option Text (word)
                Text(option.text)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)

                // Check mark for selected or correct answer
                if showFeedback && (isSelected || shouldShowAsCorrect) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.title3)
                        .shadow(color: Color.black.opacity(AppTheme.strongOpacity), radius: 2, y: 1)
                }
            }
            .padding()
            .background(backgroundGradient)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        borderGradient != nil ?
                            AnyShapeStyle(borderGradient!) :
                            AnyShapeStyle(Color.clear),
                        lineWidth: 3
                    )
            )
            .shadow(color: shadowColor, radius: 10, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Enhanced Question Router View

struct EnhancedQuestionView: View {
    let question: ReviewQuestion
    let onImmediateFeedback: ((Bool) -> Void)?
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack {
            switch question.question_type {
            case "mc_definition", "mc_word":
                MultipleChoiceQuestionView(
                    question: question,
                    onImmediateFeedback: { selectedAnswer in
                        let isCorrect = selectedAnswer == question.correct_answer
                        onImmediateFeedback?(isCorrect)
                    },
                    onAnswer: { selectedAnswer in
                        let isCorrect = selectedAnswer == question.correct_answer
                        onAnswer(isCorrect)
                    }
                )

            case "fill_blank":
                FillInBlankQuestionView(
                    question: question,
                    onImmediateFeedback: { selectedAnswer in
                        let isCorrect = selectedAnswer == question.correct_answer
                        onImmediateFeedback?(isCorrect)
                    },
                    onAnswer: { selectedAnswer in
                        let isCorrect = selectedAnswer == question.correct_answer
                        onAnswer(isCorrect)
                    }
                )

            default:
                // Recognition type removed - will be handled by definition view
                Text("Loading...")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
