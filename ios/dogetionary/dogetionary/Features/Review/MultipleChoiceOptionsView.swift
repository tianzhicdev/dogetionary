//
//  MultipleChoiceOptionsView.swift
//  dogetionary
//
//  Reusable options rendering component for multiple choice questions
//  Handles option selection, feedback timing, and answer submission
//

import SwiftUI

struct MultipleChoiceOptionsView: View {
    let options: [QuestionOption]
    let correctAnswer: String?
    let feedbackDelay: TimeInterval  // 0.5 for video, 1.2 for MC/FillBlank
    let optionButtonStyle: OptionButton.DisplayStyle
    let onImmediateFeedback: ((String) -> Void)?
    let onAnswer: (String) -> Void

    @State private var selectedAnswer: String? = nil
    @State private var showFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            // Options
            ForEach(options) { option in
                OptionButton(
                    option: option,
                    style: optionButtonStyle,
                    isSelected: selectedAnswer == option.id,
                    isCorrect: option.id == correctAnswer,
                    correctAnswer: correctAnswer,
                    showFeedback: showFeedback,
                    onTap: {
                        handleOptionTap(option.id)
                    }
                )
                .disabled(showFeedback)
            }

            // Submit button (only show when answer is selected but not yet submitted)
            if selectedAnswer != nil && !showFeedback {
                Button(action: {
                    submitAnswer()
                }) {
                    Text("Submit Answer")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.selectableTint)
                        )
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Helper Methods

    private func handleOptionTap(_ answerId: String) {
        // Just select the option, don't submit yet
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedAnswer = answerId
        }
    }

    private func submitAnswer() {
        guard let answer = selectedAnswer else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showFeedback = true
        }

        // Call immediate feedback callback right away
        onImmediateFeedback?(answer)

        // Delay before calling onAnswer to show feedback and correct answer
        DispatchQueue.main.asyncAfter(deadline: .now() + feedbackDelay) {
            onAnswer(answer)
        }
    }
}

// MARK: - Preview

#Preview("Multiple Choice Options - ID Badge Style") {
    let options = [
        QuestionOption(id: "A", text: "Lasting for a very short time"),
        QuestionOption(id: "B", text: "Eternal and unchanging"),
        QuestionOption(id: "C", text: "Related to physical objects"),
        QuestionOption(id: "D", text: "Mysterious and unknown")
    ]

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            MultipleChoiceOptionsView(
                options: options,
                correctAnswer: "A",
                feedbackDelay: 1.2,
                optionButtonStyle: .idBadgeAndText,
                onImmediateFeedback: { answer in
                    print("Immediate feedback: \(answer)")
                },
                onAnswer: { answer in
                    print("Final answer: \(answer)")
                }
            )
            .padding()
        }
    }
}

#Preview("Multiple Choice Options - Text Only Style") {
    let options = [
        QuestionOption(id: "A", text: "beautiful"),
        QuestionOption(id: "B", text: "careful"),
        QuestionOption(id: "C", text: "wonderful"),
        QuestionOption(id: "D", text: "delightful")
    ]

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack {
            MultipleChoiceOptionsView(
                options: options,
                correctAnswer: "A",
                feedbackDelay: 1.2,
                optionButtonStyle: .textOnly,
                onImmediateFeedback: { answer in
                    print("Immediate feedback: \(answer)")
                },
                onAnswer: { answer in
                    print("Final answer: \(answer)")
                }
            )
            .padding()
        }
    }
}
