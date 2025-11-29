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
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.3, green: 0.4, blue: 0.95), Color(red: 0.6, green: 0.3, blue: 0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.08), Color.purple.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: Color.blue.opacity(0.15), radius: 8, y: 4)

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
        if showFeedback && isSelected {
            if isCorrect {
                // Vibrant green gradient for correct
                return LinearGradient(
                    colors: [Color(red: 0.3, green: 0.85, blue: 0.5), Color(red: 0.2, green: 0.75, blue: 0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                // Vibrant red-orange gradient for incorrect
                return LinearGradient(
                    colors: [Color(red: 1.0, green: 0.45, blue: 0.4), Color(red: 1.0, green: 0.6, blue: 0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else if shouldShowAsCorrect {
            // Subtle green gradient for unselected correct answer
            return LinearGradient(
                colors: [Color(red: 0.7, green: 0.95, blue: 0.75), Color(red: 0.6, green: 0.9, blue: 0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isSelected {
            // Vibrant blue-cyan gradient for selected
            return LinearGradient(
                colors: [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.3, green: 0.85, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // Subtle purple-blue gradient for default
            return LinearGradient(
                colors: [Color(red: 0.92, green: 0.93, blue: 0.98), Color(red: 0.90, green: 0.92, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var borderGradient: LinearGradient? {
        if showFeedback && isSelected {
            if isCorrect {
                return LinearGradient(
                    colors: [Color(red: 0.2, green: 0.8, blue: 0.4), Color(red: 0.3, green: 0.9, blue: 0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                return LinearGradient(
                    colors: [Color(red: 1.0, green: 0.3, blue: 0.3), Color(red: 1.0, green: 0.5, blue: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else if shouldShowAsCorrect {
            return LinearGradient(
                colors: [Color(red: 0.4, green: 0.85, blue: 0.5), Color(red: 0.5, green: 0.9, blue: 0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isSelected {
            return LinearGradient(
                colors: [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.4, green: 0.8, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return nil
    }

    var shadowColor: Color {
        if showFeedback && isSelected {
            return isCorrect ? Color.green.opacity(0.4) : Color.red.opacity(0.4)
        } else if shouldShowAsCorrect {
            return Color.green.opacity(0.3)
        } else if isSelected {
            return Color.blue.opacity(0.3)
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
                            .fill(
                                showFeedback && isSelected ?
                                    (isCorrect ?
                                        LinearGradient(colors: [Color(red: 0.3, green: 0.85, blue: 0.5), Color(red: 0.2, green: 0.75, blue: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                        LinearGradient(colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 1.0, green: 0.5, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)) :
                                shouldShowAsCorrect ?
                                    LinearGradient(colors: [Color(red: 0.4, green: 0.85, blue: 0.5), Color(red: 0.3, green: 0.75, blue: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                    LinearGradient(colors: [Color(red: 0.4, green: 0.6, blue: 0.95), Color(red: 0.5, green: 0.4, blue: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
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
                        .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
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
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.2, green: 0.3, blue: 0.8), Color(red: 0.4, green: 0.5, blue: 0.95)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 0.9, blue: 1.0),
                                        Color(red: 0.9, green: 0.85, blue: 0.98)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.blue.opacity(0.2), radius: 8, y: 4)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
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
        if showFeedback && isSelected {
            if isCorrect {
                // Vibrant green gradient for correct
                return LinearGradient(
                    colors: [Color(red: 0.3, green: 0.85, blue: 0.5), Color(red: 0.2, green: 0.75, blue: 0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                // Vibrant red-orange gradient for incorrect
                return LinearGradient(
                    colors: [Color(red: 1.0, green: 0.45, blue: 0.4), Color(red: 1.0, green: 0.6, blue: 0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else if shouldShowAsCorrect {
            // Subtle green gradient for unselected correct answer
            return LinearGradient(
                colors: [Color(red: 0.7, green: 0.95, blue: 0.75), Color(red: 0.6, green: 0.9, blue: 0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isSelected {
            // Vibrant blue-cyan gradient for selected
            return LinearGradient(
                colors: [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.3, green: 0.85, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // Subtle purple-blue gradient for default
            return LinearGradient(
                colors: [Color(red: 0.92, green: 0.93, blue: 0.98), Color(red: 0.90, green: 0.92, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var borderGradient: LinearGradient? {
        if showFeedback && isSelected {
            if isCorrect {
                return LinearGradient(
                    colors: [Color(red: 0.2, green: 0.8, blue: 0.4), Color(red: 0.3, green: 0.9, blue: 0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                return LinearGradient(
                    colors: [Color(red: 1.0, green: 0.3, blue: 0.3), Color(red: 1.0, green: 0.5, blue: 0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else if shouldShowAsCorrect {
            return LinearGradient(
                colors: [Color(red: 0.4, green: 0.85, blue: 0.5), Color(red: 0.5, green: 0.9, blue: 0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isSelected {
            return LinearGradient(
                colors: [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.4, green: 0.8, blue: 0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return nil
    }

    var shadowColor: Color {
        if showFeedback && isSelected {
            return isCorrect ? Color.green.opacity(0.4) : Color.red.opacity(0.4)
        } else if shouldShowAsCorrect {
            return Color.green.opacity(0.3)
        } else if isSelected {
            return Color.blue.opacity(0.3)
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
                        .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
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
