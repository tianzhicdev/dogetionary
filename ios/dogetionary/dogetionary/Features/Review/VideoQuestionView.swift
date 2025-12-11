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

            // Question text
            Text(question.question_text)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 8)

            // Multiple choice options
            VStack(spacing: 12) {
                ForEach(question.options ?? [], id: \.id) { option in
                    Button(action: {
                        handleAnswer(option.id)
                    }) {
                        HStack {
                            // Option label (A, B, C, D)
                            Text(option.id)
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(optionColor(for: option.id))
                                .clipShape(Circle())

                            // Option text
                            Text(option.text)
                                .font(.body)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)

                            Spacer()

                            // Selection indicator
                            if selectedAnswer == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedAnswer == option.id ? Color.green.opacity(0.1) : Color(.systemGray6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedAnswer == option.id ? Color.green : Color.clear, lineWidth: 2)
                        )
                    }
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

    private func optionColor(for optionId: String) -> Color {
        if selectedAnswer == optionId {
            return .green
        }

        switch optionId {
        case "A": return .blue
        case "B": return .purple
        case "C": return .orange
        case "D": return .pink
        default: return .gray
        }
    }

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

// MARK: - Preview

struct VideoQuestionView_Previews: PreviewProvider {
    static var previews: some View {
        VideoQuestionView(
            question: ReviewQuestion(
                question_type: "video_mc",
                word: "abdominal",
                question_text: "Watch the video. What does 'abdominal' mean?",
                options: [
                    QuestionOption(id: "A", text: "relating to the abdomen"),
                    QuestionOption(id: "B", text: "relating to the chest"),
                    QuestionOption(id: "C", text: "relating to the head"),
                    QuestionOption(id: "D", text: "relating to the arms")
                ],
                correct_answer: "A",
                sentence: nil,
                sentence_translation: nil,
                show_definition: nil,
                audio_url: nil,
                evaluation_threshold: nil,
                video_id: 12,
                show_word_before_video: false
            ),
            onAnswer: { answer in
                print("Selected: \(answer)")
            }
        )
    }
}
