//
//  DefinitionCard.swift
//  dogetionary
//
//  Created by biubiu on 9/25/25.
//

import SwiftUI

struct DefinitionCard: View {
    let definition: Definition
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var isSaved = false
    @State private var isSaving = false
    @State private var isCheckingStatus = true
    @State private var savedWordId: Int?
    @State private var wordAudioData: Data?
    @State private var exampleAudioData: [String: Data] = [:]
    @State private var loadingAudio = false
    @State private var illustration: IllustrationResponse?
    @State private var isGeneratingIllustration = false
    @State private var illustrationError: String?
    @ObservedObject private var userManager = UserManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // V4: Famous Quote
            if let quote = definition.famousQuote {
                QuoteCard(quote: quote)
                    .padding(.top, 6)
            }
            
            // Header with word, phonetic, and compact illustration in top right
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.word)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let phonetic = definition.phonetic {
                        Text(phonetic)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 12) {
                        // Save/Unsave toggle button
                        Button(action: {
                            if isSaved {
                                unsaveWord()
                            } else {
                                saveWord()
                            }
                        }) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.title3)
                                .foregroundColor(isSaved ? AppTheme.infoColor : .secondary)
                        }
                        .disabled(isSaving || isCheckingStatus)
                        .buttonStyle(PlainButtonStyle())

                        // Audio play button
                        Button(action: {
                            if audioPlayer.isPlaying {
                                audioPlayer.stopAudio()
                            } else {
                                playWordAudio()
                            }
                        }) {
                            if loadingAudio {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: audioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(AppTheme.infoColor)
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
                Text(definition.translations.joined(separator: " • "))
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.bottom, 8)
            }
            

            ForEach(definition.meanings, id: \.partOfSpeech) { meaning in
                VStack(alignment: .leading, spacing: 4) {
                    Text(meaning.partOfSpeech)
                        .font(.headline)
                        .foregroundColor(AppTheme.infoColor)

                    ForEach(Array(meaning.definitions.enumerated()), id: \.offset) { index, def in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(def.definition)")
                                .font(.body)

                            if let example = def.example {
                                HStack(alignment: .top, spacing: 8) {
                                    Text("Example: \(example)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .italic()

                                    Button(action: {
                                        playExampleAudio(example)
                                    }) {
                                        Image(systemName: "speaker.wave.2")
                                            .font(.title3)
                                            .foregroundColor(AppTheme.infoColor)
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
                        .padding(.leading, 8)
                    }
                }
                .padding(.vertical, 2)
            }

            // V4: Synonyms and Antonyms after main definitions
            if !definition.synonyms.isEmpty || !definition.antonyms.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !definition.synonyms.isEmpty {
                        SynonymAntonymRow(title: "Synonyms", words: definition.synonyms, color: AppTheme.successColor)
                    }
                    if !definition.antonyms.isEmpty {
                        SynonymAntonymRow(title: "Antonyms", words: definition.antonyms, color: AppTheme.errorColor)
                    }
                }
                .padding(.top, 8)
            }
            
            // V4: Comment (usage notes)
            if let comment = definition.comment {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(AppTheme.infoColor)
                            .font(.caption)
                        Text("Usage Notes")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.infoColor)
                    }
                    Text(comment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 6)
            }

            // V4: Source (etymology)
            if let source = definition.source {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "book.closed")
                            .foregroundColor(AppTheme.infoColor)
                            .font(.caption)
                        Text("Word Origin")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.infoColor)
                    }
                    Text(source)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 6)
            }

            // V4: Common Collocations
            if !definition.collocations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "text.append")
                            .foregroundColor(AppTheme.infoColor)
                            .font(.caption)
                        Text("Common Collocations")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.infoColor)
                    }
                    ForEach(definition.collocations, id: \.self) { collocation in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundColor(AppTheme.infoColor)
                                .padding(.top, 6)
                            Text(collocation)
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                            .foregroundColor(AppTheme.infoColor)
                            .font(.caption)
                        Text("Word Family")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.infoColor)
                    }
                    ForEach(definition.wordFamily) { entry in
                        HStack {
                            Text(entry.word)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(entry.part_of_speech)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppTheme.lightBlue)
                                .cornerRadius(3)
                        }
                    }
                }
                .padding(.bottom, 6)
            }

            // V4: Cognates section
            if let cognates = definition.cognates {
                InfoSection(title: "Cognates", icon: "globe", color: AppTheme.infoColor) {
                    Text(cognates)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }

        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            checkIfWordIsSaved()
            loadWordAudioIfNeeded()

        }
        .onReceive(NotificationCenter.default.publisher(for: .wordAutoSaved)) { notification in
            if let autoSavedWord = notification.object as? String,
               autoSavedWord.lowercased() == definition.word.lowercased() {
                // Update bookmark state for auto-saved word
                isSaved = true
            }
        }
    }

    private func saveWord() {
        isSaving = true

        // Track dictionary save action
        AnalyticsManager.shared.track(action: .dictionarySave, metadata: [
            "word": definition.word,
            "language": UserManager.shared.learningLanguage
        ])

        DictionaryService.shared.saveWord(definition.word) { result in
            DispatchQueue.main.async {
                isSaving = false

                switch result {
                case .success(let wordId):
                    isSaved = true
                    savedWordId = wordId
                case .failure(let error):
                    print("Failed to save word: \(error.localizedDescription)")
                }
            }
        }
    }

    private func unsaveWord() {
        guard let wordId = savedWordId else {
            print("Cannot unsave word: no saved word ID available")
            return
        }

        isSaving = true

        DictionaryService.shared.unsaveWord(wordID: wordId) { result in
            DispatchQueue.main.async {
                isSaving = false

                switch result {
                case .success:
                    // Word completely removed from saved words
                    isSaved = false
                    savedWordId = nil

                    // Post notification for SavedWordsView to update
                    NotificationCenter.default.post(name: .wordUnsaved, object: definition.word)
                case .failure(let error):
                    print("Failed to unsave word: \(error.localizedDescription)")
                }
            }
        }
    }

    private func checkIfWordIsSaved() {
        isCheckingStatus = true

        // Use efficient single-word check endpoint instead of fetching all saved words
        DictionaryService.shared.isWordSaved(
            word: definition.word,
            learningLanguage: definition.learning_language,
            nativeLanguage: definition.native_language
        ) { result in
            DispatchQueue.main.async {
                isCheckingStatus = false

                switch result {
                case .success(let (saved, wordId)):
                    isSaved = saved
                    savedWordId = wordId
                case .failure:
                    // If we can't check, assume not saved
                    isSaved = false
                    savedWordId = nil
                }
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
                    print("Illustration generation error: \(err.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    // Preview with sample definition
    let sampleDefinition = Definition(
        word: "apple",
        phonetic: "/ˈæp.əl/",
        learning_language: "en",
        native_language: "zh",
        translations: ["苹果", "苹果公司"],
        meanings: [
            Meaning(
                partOfSpeech: "noun",
                definitions: [
                    DefinitionDetail(
                        definition: "A round fruit with red, green, or yellow skin and a whitish interior that grows on apple trees.",
                        example: "I bought some fresh apples from the market.",
                        synonyms: nil,
                        antonyms: nil
                    )
                ]
            )
        ],
        audioData: nil
    )

    DefinitionCard(definition: sampleDefinition)
        .padding()
}
