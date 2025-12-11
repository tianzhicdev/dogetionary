//
//  PronounceSentenceQuestionView.swift
//  dogetionary
//
//  Wrapper around PronunciationUICore for review flow
//

import SwiftUI
import AVFoundation
import os.log

struct PronounceSentenceQuestionView: View {
    private static let logger = Logger(subsystem: "com.shojin.app", category: "PronounceSentence")
    let question: ReviewQuestion
    let onImmediateFeedback: ((Bool) -> Void)?
    let onAnswer: (Bool) -> Void

    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var referenceAudioPlayer = AudioPlayer()
    @StateObject private var recordedAudioPlayer = AudioPlayer()

    @State private var hasRecorded = false
    @State private var isSubmitting = false
    @State private var evaluationState: PronunciationEvaluationState?
    @State private var hasAnswered = false

    var body: some View {
        PronunciationUICore(
            displayContent: .highlightedSentence(
                sentence: question.sentence ?? "",
                highlight: question.word,
                translation: question.sentence_translation
            ),
            audioSource: .preloaded(Data()),  // Not used directly, handled in callbacks
            behavior: .reviewDefault,
            callbacks: PronunciationCallbacks(
                onPlayReference: playReferenceAudio,
                onStartRecording: startRecording,
                onStopRecording: stopRecordingAndEvaluate,
                onPlayRecorded: playRecordedAudio
            ),
            audioRecorder: audioRecorder,
            referencePlayer: referenceAudioPlayer,
            recordedPlayer: recordedAudioPlayer,
            evaluationState: evaluationState,
            isProcessing: isSubmitting,
            hasRecorded: hasRecorded,
            isDisabled: hasAnswered || question.audio_url == nil
        )
        .onAppear {
            // Auto-play reference audio on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playReferenceAudio()
            }
        }
    }

    // MARK: - Callback Implementations

    private func playReferenceAudio() {
        guard let audioUrl = question.audio_url else { return }

        // Stop any other audio
        recordedAudioPlayer.stopAudio()

        // Extract base64 data from data URI (format: data:audio/mpeg;base64,...)
        if let base64Data = extractBase64Data(from: audioUrl),
           let audioData = Data(base64Encoded: base64Data) {
            referenceAudioPlayer.playAudio(from: audioData)
        }
    }

    private func startRecording() {
        // Stop any playing audio
        referenceAudioPlayer.stopAudio()
        recordedAudioPlayer.stopAudio()

        audioRecorder.startRecording()
    }

    private func stopRecordingAndEvaluate(_ audioData: Data) {
        audioRecorder.stopRecording()
        hasRecorded = true

        // Auto-evaluate immediately after recording stops
        evaluatePronunciation()
    }

    private func playRecordedAudio() {
        guard let audioData = audioRecorder.audioData else { return }

        // Stop other audio
        referenceAudioPlayer.stopAudio()

        recordedAudioPlayer.playAudio(from: audioData)
    }

    // MARK: - Evaluation Logic

    private func evaluatePronunciation() {
        guard let audioData = audioRecorder.audioData,
              let sentence = question.sentence else { return }

        isSubmitting = true

        // Use practice API (not review API) for evaluation only
        let metadata: [String: Any] = [
            "word": question.word,
            "question_type": "pronounce_sentence",
            "source": "review"
        ]

        DictionaryService.shared.practicePronunciation(
            originalText: sentence,
            audioData: audioData,
            metadata: metadata
        ) { result in
            DispatchQueue.main.async {
                isSubmitting = false

                switch result {
                case .success(let practiceResult):
                    // Hard-coded threshold: 0.8 (80%)
                    let threshold = 0.8
                    let passed = practiceResult.similarityScore >= threshold

                    // Convert to evaluation state for display
                    evaluationState = PronunciationEvaluationState(
                        score: practiceResult.similarityScore,
                        isPassed: passed,
                        transcription: practiceResult.recognizedText,
                        feedback: practiceResult.feedback
                    )

                    hasAnswered = true

                    // Immediate feedback (triggers mini curve animation)
                    onImmediateFeedback?(passed)

                    // Trigger showing definition in parent
                    onAnswer(passed)

                case .failure(let error):
                    Self.logger.error("Error evaluating pronunciation: \(error.localizedDescription, privacy: .public)")
                    // TODO: Show error message in UI
                }
            }
        }
    }

    // MARK: - Helpers

    private func extractBase64Data(from dataUri: String) -> String? {
        // Format: data:audio/mpeg;base64,ACTUALBASE64DATA
        let components = dataUri.components(separatedBy: ",")
        guard components.count > 1 else { return nil }
        return components[1]
    }
}

#Preview {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        PronounceSentenceQuestionView(
            question: ReviewQuestion(
                question_type: "pronounce_sentence",
                word: "ephemeral",
                question_text: "Pronounce this sentence:",
                options: nil,
                correct_answer: nil,
                sentence: "The beauty of cherry blossoms is ephemeral, lasting only a few weeks.",
                sentence_translation: "樱花的美丽是短暂的，只持续几周。",
                show_definition: nil,
                audio_url: "data:audio/mpeg;base64,",
                evaluation_threshold: AppConstants.Validation.pronunciationThreshold,
                video_id: nil,
                show_word_before_video: nil,
        transcript: nil
            ),
            onImmediateFeedback: { passed in
                // Preview: Immediate feedback callback
            },
            onAnswer: { passed in
                // Preview: Final answer callback
            }
        )
    }
}
