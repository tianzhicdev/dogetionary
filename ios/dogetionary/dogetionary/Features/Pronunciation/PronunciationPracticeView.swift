//
//  PronunciationPracticeView.swift
//  dogetionary
//
//  Created for pronunciation practice feature
//

import SwiftUI
import os.log

struct PronunciationPracticeView: View {
    private static let logger = Logger(subsystem: "com.dogetionary.app", category: "PronunciationPractice")
    let originalText: String
    let source: String
    let wordId: String?

    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var originalAudioPlayer = AudioPlayer()
    @StateObject private var recordedAudioPlayer = AudioPlayer()

    @State private var isProcessing = false
    @State private var result: PronunciationResult?
    @State private var recordedAudioURL: URL?
    @State private var showingPractice = false

    var body: some View {
        Button(action: {
            showingPractice.toggle()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.caption)
                Text("Practice")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.warningColor.opacity(0.15))
            .foregroundColor(AppTheme.warningColor)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingPractice, onDismiss: {
            // Ensure proper cleanup when sheet is dismissed
            audioRecorder.stopRecording()
            originalAudioPlayer.stopAudio()
            recordedAudioPlayer.stopAudio()
            isProcessing = false
        }) {
            PronunciationPracticeSheet(
                originalText: originalText,
                source: source,
                wordId: wordId,
                audioRecorder: audioRecorder,
                originalAudioPlayer: originalAudioPlayer,
                recordedAudioPlayer: recordedAudioPlayer,
                isProcessing: $isProcessing,
                result: $result,
                recordedAudioURL: $recordedAudioURL,
                showingPractice: $showingPractice
            )
            .interactiveDismissDisabled(false)
        }
    }
}

struct PronunciationPracticeSheet: View {
    private static let logger = Logger(subsystem: "com.dogetionary.app", category: "PronunciationSheet")

    let originalText: String
    let source: String
    let wordId: String?

    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var originalAudioPlayer: AudioPlayer
    @ObservedObject var recordedAudioPlayer: AudioPlayer

    @Binding var isProcessing: Bool
    @Binding var result: PronunciationResult?
    @Binding var recordedAudioURL: URL?
    @Binding var showingPractice: Bool

    @State private var evaluationState: PronunciationEvaluationState?
    @State private var hasRecorded = false

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.verticalGradient2
                    .ignoresSafeArea()

                PronunciationUICore(
                    displayContent: .plainText(originalText),
                    audioSource: .fetchOnDemand(text: originalText, language: UserManager.shared.learningLanguage),
                    behavior: .practiceDefault,
                    callbacks: PronunciationCallbacks(
                        onPlayReference: playReferenceAudio,
                        onStartRecording: startRecording,
                        onStopRecording: stopRecordingAndEvaluate,
                        onPlayRecorded: playRecordedAudio
                    ),
                    audioRecorder: audioRecorder,
                    referencePlayer: originalAudioPlayer,
                    recordedPlayer: recordedAudioPlayer,
                    evaluationState: evaluationState,
                    isProcessing: isProcessing,
                    hasRecorded: hasRecorded,
                    isDisabled: false
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing:
                    Button {
                        stopAllAudio()
                        showingPractice = false
                    } label: {
                        Text("DONE")
                            .font(.headline)
                            .foregroundColor(AppTheme.selectableTint)
                            .padding(8)
                            .cornerRadius(10)
                    }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onChange(of: result) { _, newResult in
            // Convert PronunciationResult to PronunciationEvaluationState
            if let newResult = newResult {
                evaluationState = PronunciationEvaluationState(
                    score: newResult.similarityScore,
                    isPassed: newResult.result,
                    transcription: newResult.recognizedText,
                    feedback: newResult.feedback
                )
            }
        }
    }

    // MARK: - Callback Implementations

    private func playReferenceAudio() {
        // Stop any other audio
        recordedAudioPlayer.stopAudio()

        // Fetch and play original audio
        DictionaryService.shared.fetchAudioForText(originalText, language: UserManager.shared.learningLanguage) { audioData in
            DispatchQueue.main.async {
                if let audioData = audioData {
                    self.originalAudioPlayer.playAudio(from: audioData)
                }
            }
        }
    }

    private func startRecording() {
        // Stop any playing audio
        originalAudioPlayer.stopAudio()
        recordedAudioPlayer.stopAudio()

        // Track analytics
        AnalyticsManager.shared.track(action: .pronunciationPractice, metadata: [
            "action": "start_recording",
            "source": source,
            "text": originalText
        ])

        audioRecorder.startRecording()
    }

    private func stopRecordingAndEvaluate(_ audioData: Data) {
        audioRecorder.stopRecording()
        hasRecorded = true

        // Save the recorded audio URL for playback
        recordedAudioURL = audioRecorder.recordingURL

        // Evaluate pronunciation
        evaluatePronunciation()
    }

    private func playRecordedAudio() {
        guard let url = recordedAudioURL else { return }

        // Stop other audio
        originalAudioPlayer.stopAudio()

        // Read the recorded audio file and play it
        do {
            let audioData = try Data(contentsOf: url)
            recordedAudioPlayer.playAudio(from: audioData)
        } catch {
            Self.logger.error("Failed to read recorded audio file: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Evaluation Logic

    private func evaluatePronunciation() {
        guard let audioData = audioRecorder.audioData else { return }

        isProcessing = true

        DictionaryService.shared.practicePronunciation(
            originalText: originalText,
            audioData: audioData,
            metadata: ["source": source, "word_id": wordId ?? ""]
        ) { result in
            DispatchQueue.main.async {
                isProcessing = false

                switch result {
                case .success(let pronunciationResult):
                    self.result = pronunciationResult

                    AnalyticsManager.shared.track(action: .pronunciationPractice, metadata: [
                        "action": "completed",
                        "source": self.source,
                        "text": self.originalText,
                        "result": pronunciationResult.result,
                        "similarity_score": pronunciationResult.similarityScore
                    ])

                case .failure(let error):
                    Self.logger.error("Pronunciation practice failed: \(error.localizedDescription, privacy: .public)")

                    AnalyticsManager.shared.track(action: .pronunciationPractice, metadata: [
                        "action": "failed",
                        "source": self.source,
                        "text": self.originalText,
                        "error": error.localizedDescription
                    ])
                }
            }
        }
    }

    // MARK: - Helpers

    private func stopAllAudio() {
        originalAudioPlayer.stopAudio()
        recordedAudioPlayer.stopAudio()
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        }
    }
}


struct PronunciationResult: Equatable {
    let result: Bool
    let similarityScore: Double
    let recognizedText: String
    let feedback: String
}
