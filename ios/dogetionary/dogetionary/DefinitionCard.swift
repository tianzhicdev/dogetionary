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
            HStack {
                Text(definition.word)
                    .font(.title2)
                    .fontWeight(.bold)

                if let phonetic = definition.phonetic {
                    Text(phonetic)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

            }
            HStack(spacing: 12) {
                // Save/Unsave toggle button
                Button(action: {
                    if isSaved {
                        // Unsave the existing saved word (regardless of its language pair)
                        unsaveWord()
                    } else {
                        // Save with current language settings
                        saveWord()
                    }
                }) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.title3)
                        .foregroundColor(isSaved ? AppTheme.infoColor : .secondary)
                }
                .disabled(isSaving || isCheckingStatus)
                .buttonStyle(PlainButtonStyle())

                // Audio play button - always show
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

            // Show language pair from definition (always available)
            HStack(spacing: 4) {
                Text(definition.learning_language.uppercased())
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.infoColor.opacity(AppTheme.lightOpacity))
                    .foregroundColor(AppTheme.infoColor)
                    .cornerRadius(4)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(definition.native_language.uppercased())
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.successColor.opacity(AppTheme.lightOpacity))
                    .foregroundColor(AppTheme.successColor)
                    .cornerRadius(4)
            }
            .padding(.bottom, 8)

            // Show translations if available
            if !definition.translations.isEmpty {
                Text(definition.translations.joined(separator: " • "))
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.bottom, 8)
            }

            // V4: Register + Frequency + Connotation badges
            HStack(spacing: 8) {
                if let register = definition.register {
                    RegisterBadge(register: register)
                }
                if let frequency = definition.frequency {
                    FrequencyBadge(frequency: frequency)
                }
                if let connotation = definition.connotation {
                    ConnotationBadge(connotation: connotation)
                }
            }
            .padding(.bottom, definition.register != nil || definition.frequency != nil || definition.connotation != nil ? 8 : 0)

            // V4: Tags pills
            if !definition.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(definition.tags, id: \.self) { tag in
                            TagPill(tag: tag)
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            // AI Illustration Section
            AIIllustrationView(
                word: definition.word,
                language: userManager.learningLanguage,
                definition: definition,
                illustration: $illustration,
                isGenerating: $isGeneratingIllustration,
                error: $illustrationError
            )
            .padding(.bottom, 8)

            // V4: Collapsible sections before main definitions
            if !definition.collocations.isEmpty {
                CollapsibleSection(title: "Common Collocations", icon: "text.append") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(definition.collocations, id: \.self) { collocation in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4))
                                    .foregroundColor(AppTheme.infoColor)
                                    .padding(.top, 6)
                                Text(collocation)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }

            if !definition.wordFamily.isEmpty {
                CollapsibleSection(title: "Word Family", icon: "link") {
                    VStack(spacing: 6) {
                        ForEach(definition.wordFamily) { entry in
                            HStack {
                                Text(entry.word)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(entry.part_of_speech)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.lightBlue)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
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

            // V4: Confusables section
            if !definition.confusables.isEmpty {
                InfoSection(title: "Common Confusions", icon: "exclamationmark.triangle", color: AppTheme.warningColor) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(definition.confusables, id: \.self) { confusable in
                            Text(confusable)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 8)
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

            // V4: Famous Quotes section
            if !definition.famousQuotes.isEmpty {
                CollapsibleSection(title: "Famous Quotes", icon: "quote.bubble") {
                    VStack(spacing: 10) {
                        ForEach(definition.famousQuotes) { quote in
                            QuoteCard(quote: quote)
                        }
                    }
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
