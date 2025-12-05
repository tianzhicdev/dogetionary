//
//  DefinitionCard.swift
//  dogetionary
//
//  Created by biubiu on 9/25/25.
//

import SwiftUI
import os.log

struct DefinitionCard: View {
    private static let logger = Logger(subsystem: "com.dogetionary.app", category: "DefinitionCard")
    let definition: Definition
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var wordAudioData: Data?
    @State private var exampleAudioData: [String: Data] = [:]
    @State private var loadingAudio = false
    @State private var illustration: IllustrationResponse?
    @State private var isGeneratingIllustration = false
    @State private var illustrationError: String?
    @ObservedObject private var userManager = UserManager.shared

    var body: some View {
        ZStack {
            
        VStack(alignment: .leading, spacing: 8) {
            
            // V4: Famous Quote
            if let quote = definition.famousQuote {
                QuoteCard(quote: quote)
                    .padding(.top, 6)
                Spacer()
            }
            
            // Header with word, phonetic, and compact illustration in top right
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.word)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.bigTitleText)
                    
                    if let phonetic = definition.phonetic {
                        Text(phonetic)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.smallTitleText)
                    }
                    
                    HStack(spacing: 12) {
                        // Audio play button
                        Button(action: {
                            if audioPlayer.isPlaying {
                                audioPlayer.stopAudio()
                            } else {
                                playWordAudio()
                            }
                        }) {
                            if loadingAudio {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Loading")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.accentCyan.opacity(0.15))
                                .foregroundColor(AppTheme.accentCyan)
                                .cornerRadius(8)
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: audioPlayer.isPlaying ? "stop.fill" : "play.fill")
                                        .font(.caption)
                                    Text(audioPlayer.isPlaying ? "Stop" : "Play")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.accentCyan.opacity(0.15))
                                .foregroundColor(AppTheme.accentCyan)
                                .cornerRadius(8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(loadingAudio)
                        
                        // Pronunciation practice button
                        PronunciationPracticeView(
                            originalText: definition.word,
                            source: "word",
                            wordId: nil
                        )
                    }
                }
                
                Spacer()
                
                // Compact AI Illustration in top right corner
                CompactIllustrationView(
                    word: definition.word,
                    language: userManager.learningLanguage,
                    definition: definition,
                    illustration: $illustration,
                    isGenerating: $isGeneratingIllustration,
                    error: $illustrationError
                )
                .frame(width: 80, height: 80)
            }
            
            // Show translations if available
            if !definition.translations.isEmpty {
                Text(definition.translations.joined(separator: " • ").uppercased())
                    .font(.body)
                    .foregroundColor(AppTheme.bodyText)
                    .padding(.bottom, 8)
            }
            
            
            ForEach(definition.meanings, id: \.partOfSpeech) { meaning in
                VStack(alignment: .leading, spacing: 4) {
                    Text(meaning.partOfSpeech.uppercased())
                        .font(.headline)
                        .foregroundColor(AppTheme.smallTitleText)
                    
                    ForEach(Array(meaning.definitions.enumerated()), id: \.offset) { index, def in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(def.definition)")
                                .font(.body)
                                .foregroundColor(AppTheme.bodyText)
                            
                            if let example = def.example {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(example)")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.bodyText)
                                        .italic()

                                    HStack(spacing: 8) {
                                        Button(action: {
                                            playExampleAudio(example)
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "play.fill")
                                                    .font(.caption)
                                                Text("Play")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(AppTheme.accentCyan.opacity(0.15))
                                            .foregroundColor(AppTheme.accentCyan)
                                            .cornerRadius(8)
                                        }
                                        .buttonStyle(PlainButtonStyle())

                                        // Pronunciation practice for examples
                                        PronunciationPracticeView(
                                            originalText: example,
                                            source: "example",
                                            wordId: nil
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding(.vertical, 2)
            }
            
            // V4: Synonyms and Antonyms after main definitions
            if !definition.synonyms.isEmpty || !definition.antonyms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !definition.synonyms.isEmpty {
                        SynonymAntonymRow(title: "SYNONYMS", words: definition.synonyms, color: AppTheme.accentCyan)
                    }
                    if !definition.antonyms.isEmpty {
                        SynonymAntonymRow(title: "ANTONYMS", words: definition.antonyms, color: AppTheme.selectableTint)
                    }
                }
                .padding(.top, 8)
            }
            
            // V4: Comment (usage notes)
            if let comment = definition.comment {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(AppTheme.smallTitleText)
                            .font(.caption)
                        Text("USAGE NOTES")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.smallTitleText)
                    }
                    Text(comment)
                        .font(.caption)
                        .foregroundColor(AppTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 6)
            }
            
            // V4: Source (etymology)
            if let source = definition.source {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "book.closed")
                            .foregroundColor(AppTheme.smallTitleText)
                            .font(.caption)
                        Text("WORD ORIGIN")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.smallTitleText)
                    }
                    Text(source)
                        .font(.caption)
                        .foregroundColor(AppTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 6)
            }
            
            // V4: Common Collocations
            if !definition.collocations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "text.append")
                            .foregroundColor(AppTheme.smallTitleText)
                            .font(.caption)
                        Text("COMMON COLLOCATIONS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.smallTitleText)
                    }
                    ForEach(definition.collocations, id: \.self) { collocation in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundColor(AppTheme.selectableTint)
                                .padding(.top, 6)
                            Text(collocation)
                                .font(.caption)
                                .foregroundColor(AppTheme.bodyText)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            
            // V4: Word Family
            if !definition.wordFamily.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(AppTheme.smallTitleText)
                            .font(.caption)
                        Text("WORD FAMILY")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.smallTitleText)
                    }
                    ForEach(definition.wordFamily) { entry in
                        HStack {
                            Text(entry.word)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(AppTheme.bodyText)
                            Spacer()
                            Text(entry.part_of_speech)
                                .font(.caption2)
                                .foregroundColor(AppTheme.bodyText)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            
            // V4: Cognates section
            if let cognates = definition.cognates {
                InfoSection(title: "COGNATES", icon: "globe", color: AppTheme.smallTitleText) {
                    Text(cognates)
                        .font(.caption)
                        .foregroundColor(AppTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
            
        }
        .padding()
        .background(AppTheme.clear)
//        )
        .onAppear {
            loadWordAudioIfNeeded()
        }
    }
    }

    private func loadWordAudioIfNeeded() {
        guard wordAudioData == nil else {
            return
        }

        DictionaryService.shared.fetchAudioForText(definition.word, language: UserManager.shared.learningLanguage) { audioData in
            DispatchQueue.main.async {
                self.wordAudioData = audioData
            }
        }
    }

    private func playWordAudio() {
        // Track dictionary search audio action
        AnalyticsManager.shared.track(action: .dictionarySearchAudio, metadata: [
            "word": definition.word,
            "language": UserManager.shared.learningLanguage
        ])

        if let audioData = wordAudioData {
            audioPlayer.playAudio(from: audioData)
        } else {
            // Fetch audio using text+language directly
            loadingAudio = true
            DictionaryService.shared.fetchAudioForText(definition.word, language: UserManager.shared.learningLanguage) { audioData in
                DispatchQueue.main.async {
                    self.loadingAudio = false
                    if let audioData = audioData {
                        self.wordAudioData = audioData
                        self.audioPlayer.playAudio(from: audioData)
                    }
                }
            }
        }
    }

    private func playExampleAudio(_ text: String) {
        // Track dictionary example audio action
        AnalyticsManager.shared.track(action: .dictionaryExampleAudio, metadata: [
            "word": definition.word,
            "example_text": text,
            "language": UserManager.shared.learningLanguage
        ])

        loadExampleAudio(for: text) { audioData in
            if let audioData = audioData {
                self.audioPlayer.playAudio(from: audioData)
            }
        }
    }

    private func loadExampleAudio(for text: String, completion: @escaping (Data?) -> Void) {
        if let audioData = exampleAudioData[text] {
            completion(audioData)
            return
        }

        // Fetch audio using text+language directly
        DictionaryService.shared.fetchAudioForText(text, language: UserManager.shared.learningLanguage) { audioData in
            DispatchQueue.main.async {
                if let audioData = audioData {
                    self.exampleAudioData[text] = audioData
                }
                completion(audioData)
            }
        }
    }
}

// Compact version of AI Illustration for top-right corner
struct CompactIllustrationView: View {
    private static let logger = Logger(subsystem: "com.dogetionary.app", category: "CompactIllustration")

    let word: String
    let language: String
    let definition: Definition?
    @Binding var illustration: IllustrationResponse?
    @Binding var isGenerating: Bool
    @Binding var error: String?
    @State private var showFullscreen = false

    var body: some View {
        ZStack {
            if let illustration = illustration {
                // Show generated illustration
                if let imageData = Data(base64Encoded: illustration.image_data),
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture {
                            showFullscreen = true
                        }
                }
            } else if isGenerating {
                // Show loading state - invisible, no placeholder
                ProgressView()
                    .scaleEffect(0.7)
                    .opacity(0)  // Hide progress indicator too
            } else {
                // No placeholder - completely invisible while loading
                EmptyView()
            }
        }
        .onAppear {
            loadExistingIllustration()
        }
        .sheet(isPresented: $showFullscreen) {
            if let illustration = illustration,
               let imageData = Data(base64Encoded: illustration.image_data),
               let uiImage = UIImage(data: imageData) {
                FullscreenWordCardView(
                    word: word,
                    phonetic: definition?.phonetic,
                    firstDefinition: definition?.meanings.first?.definitions.first?.definition,
                    illustration: uiImage
                )
            }
        }
    }

    private func loadExistingIllustration() {
        DictionaryService.shared.getIllustration(word: word, language: language) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let illustrationResponse):
                    self.illustration = illustrationResponse
                    self.error = nil
                case .failure(_):
                    // Illustration doesn't exist yet, auto-generate it
                    self.generateIllustration()
                }
            }
        }
    }

    private func generateIllustration() {
        guard !isGenerating else { return }

        isGenerating = true
        error = nil

        DictionaryService.shared.generateIllustration(word: word, language: language) { result in
            DispatchQueue.main.async {
                isGenerating = false

                switch result {
                case .success(let illustrationResponse):
                    self.illustration = illustrationResponse
                    self.error = nil
                case .failure(let err):
                    self.error = "Failed to generate illustration"
                    Self.logger.error("Illustration generation error: \(err.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

// MARK: - Fullscreen Word Card View

struct FullscreenWordCardView: View {
    let word: String
    let phonetic: String?
    let firstDefinition: String?
    let illustration: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Main illustration
                Image(uiImage: illustration)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 10)

                // Word card content
                VStack(spacing: 16) {
                    // Word and pronunciation
                    VStack(spacing: 8) {
                        Text(word.uppercased())
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(AppTheme.electricYellow)

                        if let phonetic = phonetic {
                            Text(phonetic)
                                .font(.title2)
                                .foregroundColor(AppTheme.smallTitleText)
                        }
                    }

                    // First definition
                    if let firstDefinition = firstDefinition {
                        Text(firstDefinition)
                            .font(.title3)
                            .foregroundColor(AppTheme.smallTitleText)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .padding(.horizontal)
                    }
                }
                .padding()
                .background(AppTheme.panelFill)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppTheme.accentCyan.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    // Preview with full V4 schema - comprehensive sample definition
    let sampleDefinition = Definition(
        word: "serendipity",
        phonetic: "/ˌser.ənˈdɪp.ə.ti/",
        learning_language: "en",
        native_language: "zh",
        translations: ["意外发现", "机缘巧合"],
        meanings: [
            Meaning(
                partOfSpeech: "noun",
                definitions: [
                    DefinitionDetail(
                        definition: "The occurrence and development of events by chance in a happy or beneficial way.",
                        example: "A fortunate stroke of serendipity brought the two old friends together after twenty years.",
                        synonyms: nil,
                        antonyms: nil
                    ),
                    DefinitionDetail(
                        definition: "The faculty of making happy and unexpected discoveries by accident.",
                        example: "The scientist's serendipity led to a groundbreaking discovery in medicine.",
                        synonyms: nil,
                        antonyms: nil
                    )
                ]
            )
        ],
        audioData: nil,
        hasWordAudio: true,
        exampleAudioAvailability: [:],
        validWordScore: 0.95,
        suggestion: nil,
        collocations: [
            "pure serendipity",
            "a moment of serendipity",
            "by serendipity",
            "serendipitous discovery"
        ],
        synonyms: ["chance", "luck", "fortune", "coincidence", "accident"],
        antonyms: ["misfortune", "bad luck", "design", "intention", "plan"],
        comment: "Formal register. Often used in academic and literary contexts. The word carries a positive connotation of fortunate accidents. Note: Don't confuse with 'synchronicity' which implies meaningful coincidence rather than happy accident.",
        source: "Coined by Horace Walpole in 1754, from the Persian fairy tale 'The Three Princes of Serendip' (Serendip being an old name for Sri Lanka). The princes were always making discoveries by accident of things they were not seeking.",
        wordFamily: [
            WordFamilyEntry(word: "serendipitous", part_of_speech: "adjective"),
            WordFamilyEntry(word: "serendipitously", part_of_speech: "adverb")
        ],
        cognates: "French: sérendipité, Spanish: serendipia, German: Serendipität, Italian: serendipità",
        famousQuote: FamousQuote(
            quote: "Serendipity is looking in a haystack for a needle and discovering a farmer's daughter.",
            source: "Julius Comroe Jr."
        )
    )

    DefinitionCard(definition: sampleDefinition)
        .padding()
}
