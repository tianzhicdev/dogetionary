//
//  PronunciationUICore.swift
//  dogetionary
//
//  Shared core UI for pronunciation practice and review
//

import SwiftUI
import os.log

// MARK: - Configuration Types

/// How to display the text to pronounce
enum PronunciationDisplayContent {
    case plainText(String)
    case highlightedSentence(sentence: String, highlight: String, translation: String?)
}

/// Where audio comes from
enum PronunciationAudioSource {
    case preloaded(Data)
    case fetchOnDemand(text: String, language: String)
}

/// How to display evaluation results
enum PronunciationEvaluationStyle {
    case compact    // Simple display for review flow
    case detailed   // Rich display for practice flow
}

/// Behavior configuration
struct PronunciationBehaviorConfig {
    let autoPlay: Bool
    let showVolumeIndicator: Bool

    static let reviewDefault = PronunciationBehaviorConfig(autoPlay: true, showVolumeIndicator: true)
    static let practiceDefault = PronunciationBehaviorConfig(autoPlay: false, showVolumeIndicator: true)
}

/// Evaluation state to display
struct PronunciationEvaluationState {
    let score: Double           // 0.0 to 1.0
    let isPassed: Bool
    let transcription: String
    let feedback: String
}

/// Callbacks for wrapper to implement
struct PronunciationCallbacks {
    let onPlayReference: () -> Void
    let onStartRecording: () -> Void
    let onStopRecording: (Data) -> Void
    let onPlayRecorded: () -> Void
}

// MARK: - Core UI Component

struct PronunciationUICore: View {
    private static let logger = Logger(subsystem: "com.dogetionary.app", category: "PronunciationUICore")

    // Configuration
    let displayContent: PronunciationDisplayContent
    let audioSource: PronunciationAudioSource
    let evaluationStyle: PronunciationEvaluationStyle
    let behavior: PronunciationBehaviorConfig
    let callbacks: PronunciationCallbacks

    // Audio state (managed by wrapper, observed here)
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var referencePlayer: AudioPlayer
    @ObservedObject var recordedPlayer: AudioPlayer

    // Evaluation state (set by wrapper)
    let evaluationState: PronunciationEvaluationState?

    // UI state
    let isProcessing: Bool
    let hasRecorded: Bool
    let isDisabled: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Display content (text with optional highlighting)
            displayView

            // Audio control buttons
            audioControlsView

            // Volume indicator when recording
            if behavior.showVolumeIndicator && audioRecorder.isRecording {
                volumeMeterView
            }

            // Processing indicator
            if isProcessing {
                processingView
            }

            // Evaluation results
            if let state = evaluationState {
                evaluationResultView(state)
            }
        }
        .padding()
    }

    // MARK: - Subviews

    private var displayView: some View {
        Group {
            switch displayContent {
            case .plainText(let text):
                VStack(spacing: 8) {
                    Text("PRONOUNCE THIS:")
                        .font(.headline)
                        .foregroundColor(AppTheme.selectableTint)

                    Text(text)
                        .font(.title2)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .foregroundColor(AppTheme.bigTitleText)
                }

            case .highlightedSentence(let sentence, let highlight, let translation):
                VStack(spacing: 12) {
                    Text("PRONOUNCE THIS SENTENCE:")
                        .font(.headline)
                        .foregroundColor(AppTheme.selectableTint)

                    Text(attributedSentence(sentence: sentence, highlightWord: highlight))
                        .font(.title2)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .foregroundColor(AppTheme.bigTitleText)

                    if let translation = translation {
                        Text(translation)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.smallTitleText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
        }
    }

    private var audioControlsView: some View {
        HStack(spacing: 30) {
            // Play reference audio button
            Button(action: callbacks.onPlayReference) {
                VStack {
                    Image(systemName: referencePlayer.isPlaying ? "stop.circle.fill" : "speaker.wave.2.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(AppTheme.buttonBackgroundBlue)

                    Text(referencePlayer.isPlaying ? "STOP" : "LISTEN")
                        .font(.caption)
                        .foregroundColor(AppTheme.buttonBackgroundBlue)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDisabled)

            // Record button
            Button(action: handleRecordButton) {
                VStack {
                    Image(systemName: audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(AppTheme.buttonBackgroundRed)

                    Text(audioRecorder.isRecording ? "STOP" : "RECORD")
                        .font(.caption)
                        .foregroundColor(AppTheme.buttonBackgroundRed)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDisabled || isProcessing)

            // Play recorded audio button
            if hasRecorded {
                Button(action: callbacks.onPlayRecorded) {
                    VStack {
                        Image(systemName: recordedPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(AppTheme.buttonBackgroundGreen)

                        Text(recordedPlayer.isPlaying ? "STOP" : "REPLAY")
                            .font(.caption)
                            .foregroundColor(AppTheme.buttonBackgroundGreen)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 8)
    }

    private var volumeMeterView: some View {
        VStack(spacing: 8) {
            Text("RECORDING...")
                .font(.caption)
                .foregroundColor(AppTheme.selectableTint)

            // Simple volume meter
            ProgressView(value: min(Double(audioRecorder.currentVolume), 1.0))
                .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.selectableTint))
                .frame(width: 200)
        }
    }

    private var processingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.accentCyan))
            Text("EVALUATING...")
                .font(.caption)
                .foregroundColor(AppTheme.smallTitleText)
        }
        .padding(.vertical, 12)
    }

    private func evaluationResultView(_ state: PronunciationEvaluationState) -> some View {
        Group {
            switch evaluationStyle {
            case .compact:
                compactResultView(state)
            case .detailed:
                detailedResultView(state)
            }
        }
    }

    private func compactResultView(_ state: PronunciationEvaluationState) -> some View {
        VStack(spacing: 12) {
            // Score percentage
            Text("\(Int(state.score * 100))%")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(AppTheme.smallTitleText)

            // Pass/Try Again indicator
            Text(state.isPassed ? "GREAT JOB!" : "KEEP PRACTICING!")
                .font(.headline)
                .foregroundColor(AppTheme.smallTitleText)

            // What user said (transcription)
            if !state.transcription.isEmpty {
                VStack(spacing: 4) {
                    Text("YOU SAID:")
                        .font(.caption)
                        .foregroundColor(AppTheme.bodyText)

                    Text("\"\(state.transcription)\"")
                        .font(.body)
                        .italic()
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundColor(AppTheme.bodyText)
                }
            }

            // Feedback
            if !state.feedback.isEmpty {
                Text(state.feedback.uppercased())
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppTheme.bodyText)
                    .padding(.horizontal)
            }
        }
        .padding()
    }

    private func detailedResultView(_ state: PronunciationEvaluationState) -> some View {
        VStack(spacing: 16) {
            // Header with icon
            HStack {
                Image(systemName: state.isPassed ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.title2)
                    .foregroundColor(state.isPassed ? AppTheme.accentCyan : AppTheme.electricYellow)

                Text("YOUR PRONUNCIATION")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.smallTitleText)

                Spacer()
            }

            VStack(spacing: 12) {
                // Accuracy score with visual indicator
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ACCURACY")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppTheme.smallTextColor1)

                        HStack {
                            Text("\(Int(state.score * 100))%")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(state.isPassed ? AppTheme.accentCyan : AppTheme.electricYellow)

                            // Visual progress bar
                            ProgressView(value: state.score, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle(tint: state.isPassed ? AppTheme.accentCyan : AppTheme.electricYellow))
                                .frame(height: 8)
                                .cornerRadius(4)
                        }
                    }
                    Spacer()
                }

                Divider()
                    .background(AppTheme.accentCyan.opacity(0.3))

                // What you said
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOU SAID")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(AppTheme.smallTextColor1)

                        Text("\"\(state.transcription)\"")
                            .font(.body)
                            .italic()
                            .foregroundColor(AppTheme.bodyText)
                    }
                    Spacer()
                }

                Divider()
                    .background(AppTheme.accentCyan.opacity(0.3))

                // Feedback
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.feedback.uppercased())
                            .font(.body)
                            .foregroundColor(AppTheme.bodyText)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(AppTheme.bgPrimary)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(AppTheme.accentCyan.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func handleRecordButton() {
        if audioRecorder.isRecording {
            callbacks.onStopRecording(audioRecorder.audioData ?? Data())
        } else {
            callbacks.onStartRecording()
        }
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
                attributedString[attrRange].foregroundColor = AppTheme.selectableTint
                attributedString[attrRange].font = .title2.bold()
            }
        }

        return attributedString
    }
}

#Preview("Plain Text - Compact Results") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        PronunciationUICore(
            displayContent: .plainText("ephemeral"),
            audioSource: .fetchOnDemand(text: "ephemeral", language: "en"),
            evaluationStyle: .compact,
            behavior: .practiceDefault,
            callbacks: PronunciationCallbacks(
                onPlayReference: {},
                onStartRecording: {},
                onStopRecording: { _ in },
                onPlayRecorded: {}
            ),
            audioRecorder: AudioRecorder(),
            referencePlayer: AudioPlayer(),
            recordedPlayer: AudioPlayer(),
            evaluationState: PronunciationEvaluationState(
                score: 0.85,
                isPassed: true,
                transcription: "ephemeral",
                feedback: "Good pronunciation!"
            ),
            isProcessing: false,
            hasRecorded: true,
            isDisabled: false
        )
    }
}

#Preview("Highlighted Sentence - Detailed Results") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        PronunciationUICore(
            displayContent: .highlightedSentence(
                sentence: "The beauty of cherry blossoms is ephemeral.",
                highlight: "ephemeral",
                translation: "樱花的美丽是短暂的。"
            ),
            audioSource: .preloaded(Data()),
            evaluationStyle: .detailed,
            behavior: .reviewDefault,
            callbacks: PronunciationCallbacks(
                onPlayReference: {},
                onStartRecording: {},
                onStopRecording: { _ in },
                onPlayRecorded: {}
            ),
            audioRecorder: AudioRecorder(),
            referencePlayer: AudioPlayer(),
            recordedPlayer: AudioPlayer(),
            evaluationState: PronunciationEvaluationState(
                score: 0.92,
                isPassed: true,
                transcription: "The beauty of cherry blossoms is ephemeral",
                feedback: "Excellent pronunciation! Your intonation was clear."
            ),
            isProcessing: false,
            hasRecorded: true,
            isDisabled: false
        )
    }
}
