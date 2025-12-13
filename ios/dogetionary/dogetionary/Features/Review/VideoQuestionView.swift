//
//  VideoQuestionView.swift
//  dogetionary
//
//  Video multiple-choice question view
//

import SwiftUI
import AVKit
import Combine

struct VideoQuestionView: View {
    let question: ReviewQuestion
    let onAnswer: (String) -> Void

    @State private var videoURL: URL?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showWord = false
    @State private var player: AVPlayer?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack(spacing: 20) {
            // Word display (conditional based on show_word_before_video and answer state)
            if (question.show_word_before_video == true || showWord) {
                Text(question.word)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.top)
            }

            // Video player or loading state
            ZStack {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading video...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 250)
                } else if let error = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text("Video unavailable")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(height: 250)
                    .padding()
                } else if let player = player {
                    VideoPlayer(player: player)
                        .frame(height: 250)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                        .onAppear {
                            // Auto-play video when it appears
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 250)
                        .cornerRadius(12)
                }
            }

            // Audio transcript display (if available)
            if let audio_transcript = question.audio_transcript, !audio_transcript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {

                    HighlightedTranscriptText(transcript: audio_transcript, word: question.word)
                        .font(.body)
                        .foregroundColor(AppTheme.bodyText)
                        .padding(12)
                }
                .padding(.horizontal)
            }

            // Question text
            Text(question.question_text)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 8)
                .foregroundStyle(AppTheme.bodyText)

            // Multiple choice options
            MultipleChoiceOptionsView(
                options: question.options ?? [],
                correctAnswer: question.correct_answer,
                feedbackDelay: 0.5,
                optionButtonStyle: .idBadgeAndText,
                onImmediateFeedback: { answerId in
                    // Show word after answering
                    showWord = true
                    // Pause video after selection
                    player?.pause()
                },
                onAnswer: onAnswer
            )
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            // Cleanup player
            player?.pause()
            player = nil
        }
    }

    // MARK: - Helper Methods

    private func loadVideo() {
        guard let videoId = question.video_id else {
            loadError = "No video ID provided"
            isLoading = false
            return
        }

        // Fetch video (will use cache if available, or wait for sequential download)
        VideoService.shared.fetchVideo(videoId: videoId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        loadError = error.localizedDescription
                        isLoading = false
                        print("❌ VideoQuestionView: Error loading video \(videoId): \(error)")
                        print("   Error domain: \((error as NSError).domain)")
                        print("   Error code: \((error as NSError).code)")
                        print("   Error userInfo: \((error as NSError).userInfo)")
                    }
                },
                receiveValue: { [self] url in
                    videoURL = url

                    // Verify file exists and check size
                    let fileManager = FileManager.default
                    if fileManager.fileExists(atPath: url.path) {
                        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                           let fileSize = attributes[.size] as? Int64 {
                            print("✓ VideoQuestionView: Video file exists - \(fileSize) bytes at \(url.path)")
                        } else {
                            print("⚠️ VideoQuestionView: Video file exists but can't read attributes at \(url.path)")
                        }
                    } else {
                        print("❌ VideoQuestionView: Video file does NOT exist at \(url.path)")
                    }

                    // Create player
                    let newPlayer = AVPlayer(url: url)
                    player = newPlayer
                    isLoading = false

                    print("✓ VideoQuestionView: Created AVPlayer for video \(videoId)")
                    print("   File: \(url.lastPathComponent)")
                    print("   Full path: \(url.path)")
                    print("   Player status: \(newPlayer.status.rawValue) (0=unknown, 1=ready, 2=failed)")

                    // Observe player status changes
                    newPlayer.publisher(for: \.status)
                        .sink { status in
                            print("   Player status changed to: \(status.rawValue)")
                            if status == .failed {
                                if let error = newPlayer.error {
                                    print("   ❌ AVPlayer failed with error: \(error)")
                                    print("      Error domain: \((error as NSError).domain)")
                                    print("      Error code: \((error as NSError).code)")
                                    print("      Error description: \(error.localizedDescription)")
                                }
                            } else if status == .readyToPlay {
                                print("   ✓ AVPlayer ready to play")
                            }
                        }
                        .store(in: &cancellables)

                    // Observe current item status
                    if let currentItem = newPlayer.currentItem {
                        currentItem.publisher(for: \.status)
                            .sink { itemStatus in
                                print("   Player item status changed to: \(itemStatus.rawValue)")
                                if itemStatus == .failed {
                                    if let error = currentItem.error {
                                        print("   ❌ AVPlayerItem failed with error: \(error)")
                                        print("      Error domain: \((error as NSError).domain)")
                                        print("      Error code: \((error as NSError).code)")
                                        print("      Error description: \(error.localizedDescription)")
                                    }
                                }
                            }
                            .store(in: &cancellables)
                    }
                }
            )
            .store(in: &cancellables)
    }
}

// MARK: - Highlighted Transcript Text

struct HighlightedTranscriptText: View {
    let transcript: String
    let word: String

    var body: some View {
        Text(highlightedText())
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func highlightedText() -> AttributedString {
        var attributedString = AttributedString(transcript)

        // Case-insensitive search for the word in the transcript
        let lowercaseTranscript = transcript.lowercased()
        let lowercaseWord = word.lowercased()

        // Find all occurrences of the word (whole word match)
        var searchRange = lowercaseTranscript.startIndex

        while let range = lowercaseTranscript.range(of: lowercaseWord, range: searchRange..<lowercaseTranscript.endIndex) {
            // Check if it's a whole word match (not part of another word)
            let beforeChar = range.lowerBound > lowercaseTranscript.startIndex ?
                lowercaseTranscript[lowercaseTranscript.index(before: range.lowerBound)] : " "
            let afterChar = range.upperBound < lowercaseTranscript.endIndex ?
                lowercaseTranscript[range.upperBound] : " "

            let isWholeWord = !beforeChar.isLetter && !beforeChar.isNumber &&
                              !afterChar.isLetter && !afterChar.isNumber

            if isWholeWord {
                // Highlight this occurrence
                let startIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: lowercaseTranscript.distance(from: lowercaseTranscript.startIndex, to: range.lowerBound))
                let endIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: lowercaseTranscript.distance(from: lowercaseTranscript.startIndex, to: range.upperBound))

                let attributedRange = startIndex..<endIndex
                attributedString[attributedRange].foregroundColor = AppTheme.selectableTint
                attributedString[attributedRange].font = .body.weight(.bold)
            }

            // Move to next position
            searchRange = range.upperBound
        }

        return attributedString
    }
}

// MARK: - Preview

struct VideoQuestionView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            AppTheme.verticalGradient2.ignoresSafeArea()

            VideoQuestionView(
                question: ReviewQuestion(
                    question_type: "video_mc",
                    word: "diagnosis",
                    question_text: "What does 'diagnosis' mean?",
                    options: [
                        QuestionOption(id: "A", text: "the identification of a disease or condition through examination"),
                        QuestionOption(id: "B", text: "the treatment plan for a medical condition"),
                        QuestionOption(id: "C", text: "the prevention of illness through vaccination"),
                        QuestionOption(id: "D", text: "the recovery process after surgery")
                    ],
                    correct_answer: "A",
                    sentence: nil,
                    sentence_translation: nil,
                    show_definition: nil,
                    audio_url: nil,
                    evaluation_threshold: nil,
                    video_id: 1,
                    show_word_before_video: false,
                    audio_transcript: "After reviewing the patient's symptoms and test results, the doctor was able to make an accurate diagnosis of the condition. Early diagnosis is crucial for effective treatment and better outcomes."
                ),
                onAnswer: { answer in
                    print("Selected: \(answer)")
                }
            )
        }
    }
}
