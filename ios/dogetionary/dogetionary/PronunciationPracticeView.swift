//
//  PronunciationPracticeView.swift
//  dogetionary
//
//  Created for pronunciation practice feature
//

import SwiftUI

struct PronunciationPracticeView: View {
    let originalText: String
    let source: String
    let wordId: String?

    @StateObject private var audioRecorder = AudioRecorder()
    @State private var isProcessing = false
    @State private var result: PronunciationResult?
    @State private var showingResult = false
    @State private var showingRecordingModal = false

    var body: some View {
        Button(action: {
            showingRecordingModal = true
        }) {
            Image(systemName: "mic.circle.fill")
                .font(.title3)
                .foregroundColor(.orange)
        }
        .disabled(isProcessing)
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingRecordingModal) {
            RecordingModalView(
                originalText: originalText,
                source: source,
                wordId: wordId,
                audioRecorder: audioRecorder,
                isProcessing: $isProcessing,
                result: $result,
                showingResult: $showingResult,
                showingModal: $showingRecordingModal
            )
        }
        .alert("Pronunciation Result", isPresented: $showingResult) {
            Button("OK") {
                result = nil
            }
        } message: {
            if let result = result {
                Text(result.result ? "Great pronunciation! 🎉" : "Keep practicing! \(result.feedback)")
            }
        }
    }
}

struct RecordingModalView: View {
    let originalText: String
    let source: String
    let wordId: String?
    @ObservedObject var audioRecorder: AudioRecorder
    @Binding var isProcessing: Bool
    @Binding var result: PronunciationResult?
    @Binding var showingResult: Bool
    @Binding var showingModal: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

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

                if isProcessing {
                    // Processing state
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("Analyzing your pronunciation...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                } else if audioRecorder.isRecording {
                    // Recording state
                    VStack(spacing: 20) {
                        // Volume visualization
                        VolumeVisualizerView(volume: audioRecorder.currentVolume)

                        Text("Recording...")
                            .font(.headline)
                            .foregroundColor(.red)

                        // Stop recording button
                        Button(action: {
                            stopRecordingAndProcess()
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } else {
                    // Ready to record state
                    VStack(spacing: 20) {
                        Text("Tap to start recording")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        // Start recording button
                        Button(action: {
                            startRecording()
                        }) {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Pronunciation Practice")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    if audioRecorder.isRecording {
                        audioRecorder.stopRecording()
                    }
                    showingModal = false
                }
            )
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

    private func stopRecordingAndProcess() {
        audioRecorder.stopRecording()

        guard let audioData = audioRecorder.audioData else {
            return
        }

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
                    self.showingModal = false
                    self.showingResult = true

                    AnalyticsManager.shared.track(action: .pronunciationPractice, metadata: [
                        "action": "completed",
                        "source": self.source,
                        "text": self.originalText,
                        "result": pronunciationResult.result,
                        "similarity_score": pronunciationResult.similarityScore
                    ])

                case .failure(let error):
                    print("Pronunciation practice failed: \(error)")
                    self.showingModal = false

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
}

struct VolumeVisualizerView: View {
    let volume: Float

    var body: some View {
        VStack(spacing: 16) {
            // Circular volume indicator
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: CGFloat(volume))
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [.green, .yellow, .red]),
                            startPoint: .bottom,
                            endPoint: .top
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.1), value: volume)

                Image(systemName: "mic.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.primary)
            }

            // Volume bars
            HStack(spacing: 4) {
                ForEach(0..<20, id: \.self) { index in
                    Rectangle()
                        .fill(volume > Float(index) * 0.05 ? .green : .gray.opacity(0.3))
                        .frame(width: 3, height: CGFloat(8 + index * 2))
                        .animation(.easeInOut(duration: 0.1), value: volume)
                }
            }
        }
    }
}

struct PronunciationResult {
    let result: Bool
    let similarityScore: Double
    let recognizedText: String
    let feedback: String
}