//
//  QuoteQuestionView.swift
//  dogetionary
//
//  Quote-based multiple choice question view
//  Shows a famous quote with translation and tests word meaning in context
//

import SwiftUI

struct QuoteQuestionView: View {
    let question: ReviewQuestion
    let onAnswer: (String) -> Void

    // Layout constants
    private let quoteInnerPadding: CGFloat = 16
    private let quoteHorizontalPadding: CGFloat = 16
    private let questionHorizontalPadding: CGFloat = 16
    private let questionTopPadding: CGFloat = 12
    private let optionsHorizontalPadding: CGFloat = 16
    private let vStackSpacing: CGFloat = 16
    private let feedbackDelay: TimeInterval = 0

    var body: some View {
        VStack(spacing: vStackSpacing) {

            // Quote display section
            VStack(alignment: .leading, spacing: 12) {
                // Quote in English with quotation marks
                if let quote = question.quote {
                    Text("\"\(quote)\"")
                        .font(.title3)
                        .italic()
                        .foregroundColor(AppTheme.bodyText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Quote source attribution
                if let source = question.quote_source {
                    Text("— \(source)")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.smallTitleText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // Divider
                Divider()
                    .background(AppTheme.bodyText.opacity(0.3))

                // Quote translation in native language
                if let translation = question.quote_translation {
                    Text(translation)
                        .font(.body)
                        .foregroundColor(AppTheme.bodyText.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(quoteInnerPadding)
            .background(AppTheme.bodyText.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, quoteHorizontalPadding)

            // Question text
            Text(question.question_text)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(AppTheme.smallTitleText)
                .padding(.horizontal, questionHorizontalPadding)
                .padding(.top, questionTopPadding)

            // Multiple choice options
            MultipleChoiceOptionsView(
                options: question.options ?? [],
                correctAnswer: question.correct_answer,
                feedbackDelay: feedbackDelay,
                optionButtonStyle: .textOnly,
                questionType: question.question_type,
                onImmediateFeedback: nil,
                onAnswer: onAnswer
            )
            .padding(.horizontal, optionsHorizontalPadding)

            Spacer()
        }
        .padding(.top, 16)
    }
}

// MARK: - Preview

#Preview("Quote Question") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        QuoteQuestionView(
            question: ReviewQuestion(
                question_type: "mc_quote",
                word: "resilient",
                question_text: "What does 'resilient' mean in this quote?",
                options: [
                    QuestionOption(
                        id: "A",
                        text: "able to recover quickly from difficulties",
                        text_native: "能够从困难中快速恢复"
                    ),
                    QuestionOption(
                        id: "B",
                        text: "stubborn and unwilling to change",
                        text_native: "固执且不愿改变"
                    )
                ],
                correct_answer: "A",
                sentence: nil,
                sentence_translation: nil,
                show_definition: nil,
                audio_url: nil,
                evaluation_threshold: nil,
                video_id: nil,
                show_word_before_video: nil,
                audio_transcript: nil,
                video_metadata: nil,
                quote: "Despite countless setbacks, she remained resilient and never gave up on her dreams.",
                quote_source: "Maya Angelou",
                quote_translation: "尽管经历了无数次挫折，她依然坚韧不拔，从未放弃自己的梦想。"
            ),
            onAnswer: { answer in
                print("Selected: \(answer)")
            }
        )
    }
}
