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

    // MARK: - Layout Constants (adjust these to tune padding/margins)
    private let questionHorizontalPadding: CGFloat = 16  // Question text horizontal padding
    private let questionVerticalPadding: CGFloat = 8     // Question text vertical padding
    private let optionsHorizontalPadding: CGFloat = 16   // Options horizontal padding
    private let containerVerticalPadding: CGFloat = 32   // Outer container vertical padding
    private let feedbackDelay: TimeInterval = 0          // Delay before showing definition (seconds)

    var body: some View {
        VStack(spacing: 24) {
            // Question Text with clickable words
            ClickableTextView(
                text: question.question_text,
                font: .title2.weight(.bold),
                foregroundColor: AppTheme.smallTitleText,
                alignment: .center
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, questionHorizontalPadding)
            .padding(.vertical, questionVerticalPadding)

            // Options
            MultipleChoiceOptionsView(
                options: question.options ?? [],
                correctAnswer: question.correct_answer,
                feedbackDelay: feedbackDelay,
                optionButtonStyle: .textOnly,
                onImmediateFeedback: onImmediateFeedback,
                onAnswer: onAnswer
            )
            .padding(.horizontal, optionsHorizontalPadding)
        }
        .padding(.vertical, containerVerticalPadding)
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
        evaluation_threshold: nil,
        video_id: nil,
        show_word_before_video: nil,
        audio_transcript: nil,
        video_metadata: nil
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

