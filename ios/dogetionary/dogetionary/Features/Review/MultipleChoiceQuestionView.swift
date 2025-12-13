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
            MultipleChoiceOptionsView(
                options: question.options ?? [],
                correctAnswer: question.correct_answer,
                feedbackDelay: 1.2,
                optionButtonStyle: .idBadgeAndText,
                onImmediateFeedback: onImmediateFeedback,
                onAnswer: onAnswer
            )
            .padding(.horizontal)
        }
        .padding(.vertical, 32)
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
        audio_transcript: nil
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

