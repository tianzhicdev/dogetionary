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

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Text to practice
                VStack(spacing: 8) {
                    Text("Practice saying:")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text(originalText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Audio controls
                HStack(spacing: 30) {
                    // Play original audio
                    Button(action: playOriginalAudio) {
                        VStack {
                            Image(systemName: originalAudioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(AppTheme.infoColor)

                            Text(originalAudioPlayer.isPlaying ? "Stop" : "Original")
                                .font(.caption)
                                .foregroundColor(AppTheme.infoColor)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Record pronunciation
                    Button(action: handleRecording) {
                        VStack {
                            Image(systemName: audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(audioRecorder.isRecording ? AppTheme.errorColor : AppTheme.warningColor)

                            Text(audioRecorder.isRecording ? "Stop" : "Record")
                                .font(.caption)
                                .foregroundColor(audioRecorder.isRecording ? AppTheme.errorColor : AppTheme.warningColor)
                        }
                    }
                    .disabled(isProcessing)
                    .buttonStyle(PlainButtonStyle())

                    // Play recorded audio (only show if user has recorded)
                    if recordedAudioURL != nil {
                        Button(action: playRecordedAudio) {
                            VStack {
                                Image(systemName: recordedAudioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(AppTheme.successColor)

                                Text(recordedAudioPlayer.isPlaying ? "Stop" : "My Audio")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.successColor)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Volume indicator when recording
                if audioRecorder.isRecording {
                    VStack(spacing: 12) {
                        Text("Recording...")
                            .font(.caption)
                            .foregroundColor(AppTheme.errorColor)

                        // Prettier volume bars
                        HStack(spacing: 3) {
                            ForEach(0..<15, id: \.self) { index in
                                let threshold = Float(index) / 15.0
                                let isActive = audioRecorder.currentVolume > threshold
                                let barHeight: CGFloat = CGFloat(8 + index * 2)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isActive ?
                                          LinearGradient(gradient: Gradient(colors: [.green, .yellow, .red]),
                                                        startPoint: .bottom, endPoint: .top) :
                                          LinearGradient(gradient: Gradient(colors: [.gray.opacity(0.3)]),
                                                        startPoint: .bottom, endPoint: .top))
                                    .frame(width: 4, height: barHeight)
                            }
                        }
                        .frame(height: 40)
                    }
                    .padding()
                }

                // Processing indicator
                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)

                        Text("Analyzing your pronunciation...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                // Evaluation results (inline)
                if let result = result {
                    VStack(spacing: 16) {
                        // Header with icon
                        HStack {
                            Image(systemName: result.result ? "checkmark.circle.fill" : "info.circle.fill")
                                .font(.title2)
                                .foregroundColor(result.result ? .green : .orange)
                            Text("Your Pronunciation")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                        }

                        VStack(spacing: 12) {
                            // Accuracy score with visual indicator
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Accuracy")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)

                                    HStack {
                                        Text("\(Int(result.similarityScore * 100))%")
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundColor(result.result ? .green : .orange)

                                        // Visual progress bar
                                        ProgressView(value: result.similarityScore, total: 1.0)
                                            .progressViewStyle(LinearProgressViewStyle(tint: result.result ? .green : .orange))
                                            .frame(height: 8)
                                            .cornerRadius(4)
                                    }
                                }
                                Spacer()
                            }

                            Divider()

                            // What you said
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("You said")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)

                                    Text("\"\(result.recognizedText)\"")
                                        .font(.body)
                                        .italic()
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                            }

                            Divider()

                            // Feedback without title
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.feedback)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                            }
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                    )
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Pronunciation Practice")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    stopAllAudio()
                    showingPractice = false
                }
            )
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func playOriginalAudio() {
        if originalAudioPlayer.isPlaying {
            originalAudioPlayer.stopAudio()
        } else {
            // Fetch and play original audio
            DictionaryService.shared.fetchAudioForText(originalText, language: UserManager.shared.learningLanguage) { audioData in
                DispatchQueue.main.async {
                    if let audioData = audioData {
                        self.originalAudioPlayer.playAudio(from: audioData)
                    }
                }
            }
        }
    }

    private func handleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
            processRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        AnalyticsManager.shared.track(action: .pronunciationPractice, metadata: [
            "action": "start_recording",
            "source": source,
            "text": originalText
        ])

        audioRecorder.startRecording()
    }

    private func processRecording() {
        guard let audioData = audioRecorder.audioData else { return }

        // Save the recorded audio URL for playback
        recordedAudioURL = audioRecorder.recordingURL

        isProcessing = true

        DictionaryService.shared.practicePronunciation(
            originalText: originalText,
            audioData: audioData,
            metadata: ["source": source, "word_id": wordId ?? ""]
        ) { result in
            DispatchQueue.main.async {
                self.isProcessing = false

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

    private func playRecordedAudio() {
        if recordedAudioPlayer.isPlaying {
            recordedAudioPlayer.stopAudio()
        } else if let url = recordedAudioURL {
            // Read the recorded audio file and play it
            do {
                let audioData = try Data(contentsOf: url)
                recordedAudioPlayer.playAudio(from: audioData)
            } catch {
                // Failed to read recorded audio file
            }
        }
    }

    private func stopAllAudio() {
        originalAudioPlayer.stopAudio()
        recordedAudioPlayer.stopAudio()
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        }
    }
}


struct PronunciationResult {
    let result: Bool
    let similarityScore: Double
    let recognizedText: String
    let feedback: String
}