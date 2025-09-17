//
//  SearchView.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var searchText = ""
    @State private var definitions: [Definition] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showValidationAlert = false
    @State private var validationSuggestion: String?
    @State private var currentSearchQuery = ""
    @State private var currentWordConfidence: Double = 1.0
    
    private var isSearchActive: Bool {
        return !definitions.isEmpty || errorMessage != nil || isLoading
    }

    var body: some View {
        NavigationView {
            ZStack {
                if isSearchActive {
                    // Active search layout - search bar at top
                    VStack(spacing: 20) {
                        searchBarView()
                            .padding(.horizontal)
                        
                        if isLoading {
                            ProgressView("Searching...")
                                .padding()
                        }
                        
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .padding()
                        }
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(definitions) { definition in
                                    DefinitionCard(definition: definition)
                                }
                            }
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Dismiss keyboard when tapping on results
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                        
                        Spacer()
                    }
                } else {
                    // Landing page layout - centered search bar with logo
                    VStack(spacing: 40) {
                        Spacer()
                        
                        VStack(spacing: 24) {
                            // Centered search bar
                            searchBarView()
                                .padding(.horizontal, 24)
                            
                            // Tagline
                            Text("Every lookup becomes unforgettable")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        Spacer()
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // Dismiss keyboard when tapping outside text field
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .alert("Word Validation", isPresented: $showValidationAlert) {
                if let suggestion = validationSuggestion {
                    // Has suggestion - show suggestion and original options
                    Button(suggestion) {
                        searchSuggestedWord()
                    }
                    Button(currentSearchQuery) {
                        searchOriginalWord()
                    }
                } else {
                    // No suggestion - show cancel and lookup anyway options
                    Button("Cancel", role: .cancel) {
                        cancelSearch()
                    }
                    Button("Lookup anyway") {
                        searchOriginalWord()
                    }
                }
            } message: {
                if let suggestion = validationSuggestion {
                    Text("Hmm, \"\(currentSearchQuery)\" doesn't look quite right. Did you mean \"\(suggestion)\"?")
                } else {
                    Text("We couldn't find \"\(currentSearchQuery)\" in our dictionary. You can still look it up, but the definition might not be accurate.")
                }
            }
        }
    }
    
    @ViewBuilder
    private func searchBarView() -> some View {
        HStack(spacing: 12) {
            HStack {
                TextField("Enter a word", text: $searchText)
                    .font(.title2)
                    .onSubmit {
                        searchWord()
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        definitions = []
                        errorMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            Button(action: {
                searchWord()
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .fontWeight(.medium)
            }
            .disabled(searchText.isEmpty || isLoading)
            .buttonStyle(.borderedProminent)
            .frame(height: 36) // Match text field height
        }
    }
    
    private func searchWord() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let searchQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentSearchQuery = searchQuery

        // Track dictionary search
        AnalyticsManager.shared.track(action: .dictionarySearch, metadata: [
            "query": searchQuery,
            "language": UserManager.shared.learningLanguage
        ])

        isLoading = true
        errorMessage = nil

        // FIRST check validation to determine if we should show definition
        DictionaryService.shared.searchWordV2(searchQuery) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let definitionV2):
                    // Store confidence and suggestion
                    self.currentWordConfidence = definitionV2.validation.confidence
                    self.validationSuggestion = definitionV2.validation.suggested

                    if definitionV2.isValid {
                        // High confidence (≥0.9) - show definition immediately + auto-save
                        self.fetchAndDisplayDefinition(searchQuery, autoSave: true)
                    } else {
                        // Low confidence (<0.9) - show alert, NO definition
                        self.isLoading = false
                        self.showValidationAlert = true

                        // Track validation event
                        AnalyticsManager.shared.track(action: .validationInvalid, metadata: [
                            "original_query": searchQuery,
                            "confidence": definitionV2.validation.confidence,
                            "suggested": definitionV2.validation.suggested ?? "none",
                            "language": UserManager.shared.learningLanguage
                        ])
                    }

                case .failure(_):
                    // Validation service failed - default to showing definition + auto-save
                    self.currentWordConfidence = 1.0
                    self.validationSuggestion = nil
                    self.fetchAndDisplayDefinition(searchQuery, autoSave: true)
                }
            }
        }
    }

    private func fetchAndDisplayDefinition(_ word: String, autoSave: Bool) {
        DictionaryService.shared.searchWord(word) { result in
            DispatchQueue.main.async {
                self.isLoading = false

                switch result {
                case .success(let definitions):
                    self.definitions = definitions

                    // Auto-save only if requested and we have definitions
                    if autoSave, let firstDefinition = definitions.first {
                        self.autoSaveWord(firstDefinition.word)
                    }

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.definitions = []
                }
            }
        }
    }


    private func searchOriginalWord() {
        // Track user choosing original word
        AnalyticsManager.shared.track(action: .validationUseOriginal, metadata: [
            "original_query": currentSearchQuery,
            "suggested": validationSuggestion ?? "none",
            "language": UserManager.shared.learningLanguage
        ])

        showValidationAlert = false
        isLoading = true

        // Fetch and show definition for original word but DON'T auto-save
        fetchAndDisplayDefinition(currentSearchQuery, autoSave: false)
    }

    private func searchSuggestedWord() {
        guard let suggestion = validationSuggestion else { return }

        // Track user accepting suggestion
        AnalyticsManager.shared.track(action: .validationAcceptSuggestion, metadata: [
            "original_query": currentSearchQuery,
            "accepted_suggestion": suggestion,
            "language": UserManager.shared.learningLanguage
        ])

        showValidationAlert = false
        searchText = suggestion
        isLoading = true

        // Fetch and show definition for suggested word AND auto-save it
        fetchAndDisplayDefinition(suggestion, autoSave: true)
    }

    private func cancelSearch() {
        // Track user canceling validation
        AnalyticsManager.shared.track(action: .validationCancel, metadata: [
            "original_query": currentSearchQuery,
            "suggested": validationSuggestion ?? "none",
            "language": UserManager.shared.learningLanguage
        ])

        // Clear everything and return to landing page
        showValidationAlert = false
        searchText = ""
        definitions = []
        errorMessage = nil
        currentSearchQuery = ""
        validationSuggestion = nil
        currentWordConfidence = 1.0
    }

    private func autoSaveWord(_ word: String) {
        // Check if word is already saved to avoid duplicates
        DictionaryService.shared.getSavedWords { result in
            switch result {
            case .success(let savedWords):
                let isAlreadySaved = savedWords.contains { $0.word.lowercased() == word.lowercased() }

                if !isAlreadySaved {
                    // Auto-save the word
                    DictionaryService.shared.saveWord(word) { saveResult in
                        DispatchQueue.main.async {
                            switch saveResult {
                            case .success:
                                // Track auto-save event
                                AnalyticsManager.shared.track(action: .dictionaryAutoSave, metadata: [
                                    "word": word,
                                    "language": UserManager.shared.learningLanguage
                                ])

                                // Notify DefinitionCards to update their bookmark state
                                NotificationCenter.default.post(name: .wordAutoSaved, object: word)

                            case .failure(let error):
                                print("Auto-save failed for word '\(word)': \(error.localizedDescription)")
                            }
                        }
                    }
                }
            case .failure(let error):
                print("Failed to check saved words for auto-save: \(error.localizedDescription)")
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

struct DefinitionCard: View {
    let definition: Definition
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var isSaved = false
    @State private var isSaving = false
    @State private var isCheckingStatus = true
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
                            .foregroundColor(isSaved ? .blue : .secondary)
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
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(loadingAudio)
                }
            }
            
            // Show translations if available
            if !definition.translations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Translations:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Text(definition.translations.joined(separator: " • "))
                        .font(.body)
                        .foregroundColor(.primary)
                }
                .padding(.bottom, 8)
            }
            
            // AI Illustration Section
            AIIllustrationView(
                word: definition.word,
                language: userManager.learningLanguage,
                illustration: $illustration,
                isGenerating: $isGeneratingIllustration,
                error: $illustrationError
            )
            .padding(.bottom, 8)
            
            ForEach(definition.meanings, id: \.partOfSpeech) { meaning in
                VStack(alignment: .leading, spacing: 4) {
                    Text(meaning.partOfSpeech)
                        .font(.headline)
                        .foregroundColor(.blue)
                    
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
                                            .font(.caption2)
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding(.vertical, 2)
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
                case .success:
                    isSaved = true
                case .failure(let error):
                    print("Failed to save word: \(error.localizedDescription)")
                }
            }
        }
    }

    private func unsaveWord() {
        isSaving = true

        DictionaryService.shared.unsaveWord(definition.word) { result in
            DispatchQueue.main.async {
                isSaving = false

                switch result {
                case .success:
                    isSaved = false
                case .failure(let error):
                    print("Failed to unsave word: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func checkIfWordIsSaved() {
        isCheckingStatus = true
        
        DictionaryService.shared.getSavedWords { result in
            DispatchQueue.main.async {
                isCheckingStatus = false
                
                switch result {
                case .success(let savedWords):
                    isSaved = savedWords.contains { $0.word.lowercased() == definition.word.lowercased() }
                case .failure:
                    // If we can't check, assume not saved
                    isSaved = false
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
    SearchView()
        .modelContainer(for: Item.self, inMemory: true)
}
