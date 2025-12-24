//
//  EnhancedQuestionView.swift
//  dogetionary
//
//  Created by Claude Code on 12/5/25.
//  Router view for different question types
//

import SwiftUI

struct EnhancedQuestionView: View {
    let question: ReviewQuestion
    let onImmediateFeedback: ((Bool) -> Void)?
    let onAnswer: (Bool) -> Void

    var body: some View {
        VStack {
            switch question.question_type {
            case "mc_definition", "mc_word", "mc_def_native":
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

            case "pronounce_sentence":
                PronounceSentenceQuestionView(
                    question: question,
                    onImmediateFeedback: onImmediateFeedback,
                    onAnswer: onAnswer
                )

            case "video_mc":
                VideoQuestionView(
                    question: question,
                    onAnswer: { selectedAnswer in
                        let isCorrect = selectedAnswer == question.correct_answer
                        onImmediateFeedback?(isCorrect)
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

// MARK: - Preview

#Preview("Enhanced Question - Multiple Choice") {
    let sampleQuestion = ReviewQuestion(
        question_type: "mc_definition",
        word: "ubiquitous",
        question_text: "What does 'ubiquitous' mean?",
        options: [
            QuestionOption(id: "A", text: "Present everywhere"),
            QuestionOption(id: "B", text: "Very rare"),
            QuestionOption(id: "C", text: "Extremely large"),
            QuestionOption(id: "D", text: "Ancient")
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

        EnhancedQuestionView(
            question: sampleQuestion,
            onImmediateFeedback: { _ in },
            onAnswer: { _ in }
        )
    }
}

#Preview("Enhanced Question - Fill In Blank") {
    let sampleQuestion = ReviewQuestion(
        question_type: "fill_blank",
        word: "magnificent",
        question_text: "Fill in the blank",
        options: [
            QuestionOption(id: "A", text: "magnificent"),
            QuestionOption(id: "B", text: "terrible"),
            QuestionOption(id: "C", text: "small"),
            QuestionOption(id: "D", text: "quick")
        ],
        correct_answer: "A",
        sentence: "The view from the mountain was absolutely _____.",
        sentence_translation: "山上的景色真是太壮丽了。",
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

        EnhancedQuestionView(
            question: sampleQuestion,
            onImmediateFeedback: { _ in },
            onAnswer: { _ in }
        )
    }
}
