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
    @State private var selectedAnswer: String?
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
            VStack(spacing: 12) {
                ForEach(question.options ?? [], id: \.id) { option in
                    Button(action: {
                        handleAnswer(option.id)
                    }) {
                        HStack {
                            // Option ID (A, B, C, D) matching MultipleChoiceQuestionView
                            Text(option.id)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(AppTheme.selectableTint)
                                .frame(width: 32, height: 32)

                            // Option text
                            Text(option.text)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(AppTheme.smallTitleText)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Selection indicator
                            if selectedAnswer == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppTheme.selectableTint)
                                    .font(.title3)
                                    .shadow(color: AppTheme.black.opacity(0.6), radius: 2, y: 1)
                            }
                        }
                        .padding()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selectedAnswer != nil)  // Disable after selection
                }
            }
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

    private func handleAnswer(_ answerId: String) {
        selectedAnswer = answerId
        showWord = true  // Reveal word after answering

        // Pause video after selection
        player?.pause()

        // Delay to show selection, then submit answer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onAnswer(answerId)
        }
    }

    private func loadVideo() {
        guard let videoId = question.video_id else {
            loadError = "No video ID provided"
            isLoading = false
            return
        }

        VideoService.shared.fetchVideo(videoId: videoId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        loadError = error.localizedDescription
                        isLoading = false
                        print("VideoQuestionView: Error loading video \(videoId): \(error)")
                    }
                },
                receiveValue: { [self] url in
                    videoURL = url
                    player = AVPlayer(url: url)
                    isLoading = false
                    print("VideoQuestionView: Loaded video \(videoId) from \(url.lastPathComponent)")
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
