//
//  PronounceSentenceQuestionView.swift
//  dogetionary
//
//  Created for pronunciation sentence review feature
//

import SwiftUI
import AVFoundation

struct PronounceSentenceQuestionView: View {
    let question: ReviewQuestion
    let onImmediateFeedback: ((Bool) -> Void)?
    let onAnswer: (Bool) -> Void

    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var referenceAudioPlayer = AudioPlayer()
    @StateObject private var recordedAudioPlayer = AudioPlayer()

    @State private var hasRecorded = false
    @State private var isSubmitting = false
    @State private var evaluationResult: PronunciationEvaluationResult?
    @State private var hasAnswered = false

    var body: some View {
        VStack(spacing: 24) {
            // Instructions
            Text(question.question_text)
                .font(.headline)
                .foregroundColor(.secondary)

            // Sentence display with highlighted word
            sentenceDisplayView

            // Translation
            if let translation = question.sentence_translation {
                Text(translation)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Audio controls
            HStack(spacing: 30) {
                // Play reference audio button
                Button(action: playReferenceAudio) {
                    VStack {
                        Image(systemName: referenceAudioPlayer.isPlaying ? "stop.circle.fill" : "speaker.wave.2.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)

                        Text(referenceAudioPlayer.isPlaying ? "Stop" : "Listen")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(question.audio_url == nil)

                // Record button
                Button(action: handleRecording) {
                    VStack {
                        Image(systemName: audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(audioRecorder.isRecording ? .red : .orange)

                        Text(audioRecorder.isRecording ? "Stop" : "Record")
                            .font(.caption)
                            .foregroundColor(audioRecorder.isRecording ? .red : .orange)
                    }
                }
                .disabled(isSubmitting || hasAnswered)
                .buttonStyle(PlainButtonStyle())

                // Play recorded audio button
                if hasRecorded {
                    Button(action: playRecordedAudio) {
                        VStack {
                            Image(systemName: recordedAudioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.green)

                            Text(recordedAudioPlayer.isPlaying ? "Stop" : "Replay")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 8)

            // Volume indicator when recording
            if audioRecorder.isRecording {
                VStack(spacing: 8) {
                    Text("Recording...")
                        .font(.caption)
                        .foregroundColor(.red)

                    // Simple volume meter
                    ProgressView(value: min(Double(audioRecorder.currentVolume), 1.0))
                        .progressViewStyle(LinearProgressViewStyle(tint: .red))
                        .frame(width: 200)
                }
            }

            // Evaluating indicator
            if isSubmitting {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text("Evaluating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
            }

            // Evaluation results
            if let result = evaluationResult {
                evaluationResultView(result)
            }
        }
        .padding()
        .onAppear {
            // Auto-play reference audio on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playReferenceAudio()
            }
        }
    }

    // MARK: - Subviews

    private var sentenceDisplayView: some View {
        let sentence = question.sentence ?? ""
        let word = question.word

        return Text(attributedSentence(sentence: sentence, highlightWord: word))
            .font(.title2)
            .fontWeight(.medium)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private func attributedSentence(sentence: String, highlightWord: String) -> AttributedString {
        var attributedString = AttributedString(sentence)

        // Find and highlight the target word (case-insensitive)
        let lowercasedSentence = sentence.lowercased()
        let lowercasedWord = highlightWord.lowercased()

        if let range = lowercasedSentence.range(of: lowercasedWord) {
            let startIndex = sentence.distance(from: sentence.startIndex, to: range.lowerBound)
            let endIndex = sentence.distance(from: sentence.startIndex, to: range.upperBound)

            if let attrRange = Range<AttributedString.Index>(
                NSRange(location: startIndex, length: endIndex - startIndex),
                in: attributedString
            ) {
                attributedString[attrRange].foregroundColor = .orange
                attributedString[attrRange].font = .title2.bold()
            }
        }

        return attributedString
    }

    private func evaluationResultView(_ result: PronunciationEvaluationResult) -> some View {
        VStack(spacing: 12) {
            // Score percentage with color
            let scoreColor: Color = result.passed ? .green : .orange

            Text("\(Int(result.similarity_score * 100))%")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(scoreColor)

            // Pass/Try Again indicator
            Text(result.passed ? "Great job!" : "Keep practicing!")
                .font(.headline)
                .foregroundColor(scoreColor)

            // What user said (transcription)
            if !result.recognized_text.isEmpty {
                VStack(spacing: 4) {
                    Text("You said:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\"\(result.recognized_text)\"")
                        .font(.body)
                        .italic()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            // Feedback
            if !result.feedback.isEmpty {
                Text(result.feedback)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Actions

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

    private func handleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
            hasRecorded = true

            // Auto-evaluate immediately after recording stops
            evaluatePronunciation()
        } else {
            // Stop any playing audio
            referenceAudioPlayer.stopAudio()
            recordedAudioPlayer.stopAudio()

            audioRecorder.startRecording()
        }
    }

    private func playRecordedAudio() {
        guard let audioData = audioRecorder.audioData else { return }

        // Stop other audio
        referenceAudioPlayer.stopAudio()

        recordedAudioPlayer.playAudio(from: audioData)
    }

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

                    // Convert to evaluation result for display
                    evaluationResult = PronunciationEvaluationResult(
                        success: true,
                        passed: passed,
                        similarity_score: practiceResult.similarityScore,
                        recognized_text: practiceResult.recognizedText,
                        feedback: practiceResult.feedback,
                        evaluation_threshold: threshold,
                        review_id: 0,  // Not submitted yet, will be submitted on swipe
                        next_interval_days: 0  // Will be calculated on submit
                    )

                    hasAnswered = true

                    // Immediate feedback (triggers mini curve animation)
                    onImmediateFeedback?(passed)

                    // Trigger showing definition in parent
                    onAnswer(passed)

                case .failure(let error):
                    // Show error to user
                    print("Error evaluating pronunciation: \(error)")
                    // TODO: Show error message in UI
                }
            }
        }
    }

    private func extractBase64Data(from dataUri: String) -> String? {
        // Format: data:audio/mpeg;base64,ACTUALBASE64DATA
        let components = dataUri.components(separatedBy: ",")
        guard components.count > 1 else { return nil }
        return components[1]
    }
}

struct PronunciationEvaluationResult: Codable {
    let success: Bool
    let passed: Bool
    let similarity_score: Double
    let recognized_text: String
    let feedback: String
    let evaluation_threshold: Double
    let review_id: Int
    let next_interval_days: Int
}

#Preview {
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
            evaluation_threshold: 0.7
        ),
        onImmediateFeedback: { passed in
            print("Immediate feedback: \(passed)")
        },
        onAnswer: { passed in
            print("Final answer: \(passed)")
        }
    )
}
