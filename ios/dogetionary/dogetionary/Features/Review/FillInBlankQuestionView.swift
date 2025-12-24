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

    // MARK: - Layout Constants (adjust these to tune padding/margins)
    private let sentencePadding: CGFloat = 16           // Sentence text padding
    private let optionsHorizontalPadding: CGFloat = 16  // Options horizontal padding
    private let containerVerticalPadding: CGFloat = 32  // Outer container vertical padding
    private let feedbackDelay: TimeInterval = 0         // Delay before showing definition (seconds)

    var body: some View {
        VStack(spacing: 24) {
            // Sentence with blank - enhanced with colorful gradient background
            if let sentence = question.sentence {
                Text(sentence)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(AppTheme.bigTitleText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(sentencePadding)
            }

            // Options
            MultipleChoiceOptionsView(
                options: question.options ?? [],
                correctAnswer: question.correct_answer,
                feedbackDelay: feedbackDelay,
                optionButtonStyle: .textOnly,
                questionType: question.question_type,
                onImmediateFeedback: onImmediateFeedback,
                onAnswer: onAnswer
            )
            .padding(.horizontal, optionsHorizontalPadding)
        }
        .padding(.vertical, containerVerticalPadding)
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
        evaluation_threshold: nil,
        video_id: nil,
        show_word_before_video: nil,
        audio_transcript: nil,
        video_metadata: nil
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

