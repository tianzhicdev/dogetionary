//
//  VideoQuestionView.swift
//  dogetionary
//
//  Video multiple-choice question view
//

import SwiftUI
import AVKit

struct VideoQuestionView: View {
    let question: ReviewQuestion
    let onAnswer: (String) -> Void

    // MARK: - Layout Constants (adjust these to tune padding/margins)
    private let videoHeight: CGFloat = 250                // Video player height
    private let transcriptInnerPadding: CGFloat = 12     // Transcript text padding
    private let transcriptHorizontalPadding: CGFloat = 16 // Transcript container horizontal padding
    private let questionHorizontalPadding: CGFloat = 16   // Question text horizontal padding
    private let questionTopPadding: CGFloat = 8           // Question text top padding
    private let optionsHorizontalPadding: CGFloat = 16    // Options horizontal padding
    private let outerPadding: CGFloat = 16                // Outer container padding (adds horizontal space for video)
    private let vStackSpacing: CGFloat = 16                // Spacing between elements in VStack
    private let feedbackDelay: TimeInterval = 0           // Delay before showing definition (seconds)

    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showWord = false

    var body: some View {
        VStack(spacing: vStackSpacing) {

            // Video metadata at the top
            if let metadata = question.video_metadata {
                VideoMetadataView(metadata: metadata)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
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
                    .frame(height: videoHeight)
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
                    .frame(height: videoHeight)
                    .padding()
                } else if let player = player, let videoId = question.video_id {
                    LoopingVideoPlayer(player: player, videoId: videoId)
                        .frame(height: videoHeight)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                }
            }

            // Audio transcript display (if available)
            if let audio_transcript = question.audio_transcript, !audio_transcript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {

                    HighlightedTranscriptText(transcript: audio_transcript, word: question.word)
                        .font(.body)
                        .foregroundColor(AppTheme.bodyText)
                        .padding(transcriptInnerPadding)
                }
                .padding(.horizontal, transcriptHorizontalPadding)
            }

            // Question text
            Text(question.question_text)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .foregroundColor(AppTheme.smallTitleText)
                .padding(.horizontal, questionHorizontalPadding)
                .padding(.top, questionTopPadding)

            // Multiple choice options
            MultipleChoiceOptionsView(
                options: question.options ?? [],
                correctAnswer: question.correct_answer,
                feedbackDelay: feedbackDelay,
                optionButtonStyle: .textOnly,
                questionType: question.question_type,
                onImmediateFeedback: { answerId in
                    // Show word after answering
                    showWord = true
                    // Pause video after selection
                    player?.pause()
                },
                onAnswer: onAnswer
            )
            .padding(.horizontal, optionsHorizontalPadding)

            Spacer()
        }
        .padding(outerPadding)
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            // Just pause when leaving (keep player in pool for reuse)
            player?.pause()
        }
    }

    // MARK: - Helper Methods

    private func loadVideo() {
        guard let videoId = question.video_id else {
            loadError = "No video ID provided"
            isLoading = false
            return
        }

        // With Option B implementation, videos are GUARANTEED to be downloaded before
        // questions are added to queue. Just get the pre-created player.
        if let preCreatedPlayer = AVPlayerManager.shared.getPlayer(videoId: videoId) {
            print("✓ VideoQuestionView: Using pre-created player for video \(videoId)")
            player = preCreatedPlayer
            isLoading = false
            return
        }

        // Fallback: Player not found (should not happen with Option B, but handle gracefully)
        // This could only happen if:
        // 1. Video download failed but question was added to queue anyway
        // 2. Player was removed from pool unexpectedly
        print("⚠️ VideoQuestionView: Player not found for video \(videoId), attempting recovery...")

        let state = VideoService.shared.getDownloadState(videoId: videoId)
        switch state {
        case .cached(let url, _, _):
            // Video is cached but player missing - create now
            print("VideoQuestionView: Creating player for cached video \(videoId)")
            let newPlayer = AVPlayer(url: url)
            newPlayer.isMuted = false
            newPlayer.automaticallyWaitsToMinimizeStalling = false
            player = newPlayer
            isLoading = false

        default:
            // Video not ready - this is an error state with Option B
            loadError = "Video not ready (unexpected state)"
            isLoading = false
            print("❌ VideoQuestionView: Video \(videoId) not ready - this should not happen with Option B")
        }
    }
}

// MARK: - Highlighted Transcript Text

struct HighlightedTranscriptText: View {
    let transcript: String
    let word: String

    @State private var selectedWord: String?
    @State private var showDefinition = false
    @State private var definition: Definition?
    @State private var isLoadingDefinition = false

    var body: some View {
        Text(highlightedText())
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { url in
                handleWordTap(url: url)
                return .handled
            })
            .sheet(isPresented: $showDefinition) {
                NavigationView {
                    ZStack {
                        AppTheme.verticalGradient2.ignoresSafeArea()

                        if isLoadingDefinition {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Loading...")
                                    .foregroundColor(AppTheme.bodyText)
                            }
                        } else if let definition = definition {
                            ScrollView {
                                DefinitionCard(definition: definition)
                                    .padding()
                            }
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 50))
                                    .foregroundColor(.secondary)
                                Text("No definition found")
                                    .foregroundColor(AppTheme.bodyText)
                            }
                        }
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Close") {
                                showDefinition = false
                            }
                            .foregroundColor(AppTheme.selectableTint)
                        }
                    }
                }
            }
    }

    private func highlightedText() -> AttributedString {
        var attributedString = AttributedString()

        // Tokenize the transcript into words and non-words
        let tokens = tokenize(text: transcript)

        // Case-insensitive word to highlight
        let lowercaseWord = word.lowercased()

        for token in tokens {
            var tokenAttr = AttributedString(token.text)

            // Set default color to bodyText
            tokenAttr.foregroundColor = AppTheme.bodyText

            // Make word-tokens clickable and check if they should be highlighted
            if token.isWord {
                let cleanWord = token.text.trimmingCharacters(in: .punctuationCharacters)
                tokenAttr.link = URL(string: "word://\(cleanWord)")

                // Check if this is the target word to highlight
                if cleanWord.lowercased() == lowercaseWord {
                    tokenAttr.foregroundColor = AppTheme.selectableTint
                    tokenAttr.font = .body.weight(.bold)
                }
            }

            attributedString.append(tokenAttr)
        }

        return attributedString
    }

    private func tokenize(text: String) -> [Token] {
        var tokens: [Token] = []
        var currentWord = ""

        for char in text {
            if char.isLetter || char.isNumber || char == "-" || char == "'" {
                currentWord.append(char)
            } else {
                if !currentWord.isEmpty {
                    tokens.append(Token(text: currentWord, isWord: true))
                    currentWord = ""
                }
                tokens.append(Token(text: String(char), isWord: false))
            }
        }

        if !currentWord.isEmpty {
            tokens.append(Token(text: currentWord, isWord: true))
        }

        return tokens
    }

    private func handleWordTap(url: URL) {
        guard url.scheme == "word",
              let word = url.host else {
            return
        }

        let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
        selectedWord = cleanWord
        isLoadingDefinition = true
        definition = nil
        showDefinition = true

        // Load definition from API
        DictionaryService.shared.searchWord(
            cleanWord,
            learningLanguage: "en",
            nativeLanguage: "zh"
        ) { result in
            DispatchQueue.main.async {
                isLoadingDefinition = false
                switch result {
                case .success(let defs):
                    definition = defs.first
                case .failure:
                    definition = nil
                }
            }
        }
    }

    private struct Token {
        let text: String
        let isWord: Bool
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
                    audio_transcript: "After reviewing the patient's symptoms and test results, the doctor was able to make an accurate diagnosis of the condition. Early diagnosis is crucial for effective treatment and better outcomes.",
                    video_metadata: VideoMetadata(
                        movie_title: "Medical Drama",
                        movie_year: 2024,
                        title: nil
                    ),
                    quote: nil,
                    quote_source: nil,
                    quote_translation: nil
                ),
                onAnswer: { answer in
                    print("Selected: \(answer)")
                }
            )
        }
    }
}
