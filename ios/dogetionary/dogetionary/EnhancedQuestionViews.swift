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
    let onAnswer: (String) -> Void

    @State private var selectedAnswer: String? = nil
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 24) {
            // Question Text
            Text(question.question_text)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

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
                            selectedAnswer = option.id
                            showFeedback = true

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

    var backgroundColor: Color {
        if showFeedback && isSelected {
            return isCorrect ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
        } else if shouldShowAsCorrect {
            return Color.green.opacity(0.15)
        } else if isSelected {
            return Color.blue.opacity(0.1)
        } else {
            return Color.gray.opacity(0.1)
        }
    }

    var borderColor: Color {
        if showFeedback && isSelected {
            return isCorrect ? Color.green : Color.red
        } else if shouldShowAsCorrect {
            return Color.green
        } else if isSelected {
            return Color.blue
        } else {
            return Color.clear
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                // Option ID (A, B, C, D)
                Text(option.id)
                    .font(.headline)
                    .foregroundColor(
                        showFeedback && isSelected ? (isCorrect ? .green : .red) :
                        shouldShowAsCorrect ? .green : .blue
                    )
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(
                                showFeedback && isSelected ? (isCorrect ? Color.green.opacity(0.2) : Color.red.opacity(0.2)) :
                                shouldShowAsCorrect ? Color.green.opacity(0.2) : Color.blue.opacity(0.1)
                            )
                    )

                // Option Text
                Text(option.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Check mark for selected or correct answer
                if showFeedback && (isSelected || shouldShowAsCorrect) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isCorrect ? .green : .red)
                        .font(.title3)
                }
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Fill in the Blank Question View

struct FillInBlankQuestionView: View {
    let question: ReviewQuestion
    let onAnswer: (String) -> Void

    @State private var selectedAnswer: String? = nil
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 24) {
            // Question Text
            Text(question.question_text)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Sentence with blank
            if let sentence = question.sentence {
                Text(sentence)
                    .font(.title2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal)
            }

            // Translation (if available)
            if let translation = question.sentence_translation {
                Text(translation)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
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
                            selectedAnswer = option.id
                            showFeedback = true

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

    var backgroundColor: Color {
        if showFeedback && isSelected {
            return isCorrect ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
        } else if shouldShowAsCorrect {
            return Color.green.opacity(0.15)
        } else if isSelected {
            return Color.blue.opacity(0.1)
        } else {
            return Color.gray.opacity(0.1)
        }
    }

    var borderColor: Color {
        if showFeedback && isSelected {
            return isCorrect ? Color.green : Color.red
        } else if shouldShowAsCorrect {
            return Color.green
        } else if isSelected {
            return Color.blue
        } else {
            return Color.clear
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack {
                // Option Text (word)
                Text(option.text)
                    .font(.headline)
                    .foregroundColor(
                        showFeedback && isSelected ? (isCorrect ? .green : .red) :
                        shouldShowAsCorrect ? .green : .primary
                    )
                    .frame(maxWidth: .infinity)

                // Check mark for selected or correct answer
                if showFeedback && (isSelected || shouldShowAsCorrect) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isCorrect ? .green : .red)
                        .font(.title3)
                }
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Enhanced Question Router View

struct EnhancedQuestionView: View {
    let question: ReviewQuestion
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack {
            switch question.question_type {
            case "mc_definition", "mc_word":
                MultipleChoiceQuestionView(question: question) { selectedAnswer in
                    let isCorrect = selectedAnswer == question.correct_answer
                    onAnswer(isCorrect)
                }

            case "fill_blank":
                FillInBlankQuestionView(question: question) { selectedAnswer in
                    let isCorrect = selectedAnswer == question.correct_answer
                    onAnswer(isCorrect)
                }

            default:
                // Recognition type removed - will be handled by definition view
                Text("Loading...")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
