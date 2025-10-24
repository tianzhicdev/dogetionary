//
//  SearchView.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI

struct SearchView: View {
    @State private var searchText = ""
    @State private var definitions: [Definition] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showValidationAlert = false
    @State private var validationSuggestion: String?
    @State private var currentSearchQuery = ""
    @State private var currentWordConfidence: Double = 1.0
    @State private var pendingDefinitions: [Definition] = [] // Store definition while showing alert
    
    private var isSearchActive: Bool {
        return !definitions.isEmpty || errorMessage != nil || isLoading
    }

    var body: some View {
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
                // Has suggestion - show suggestion and "yes" options
                Button(suggestion) {
                    searchSuggestedWord()
                }
                Button("Yes") {
                    showOriginalDefinition()
                }
                Button("Cancel", role: .cancel) {
                    cancelSearch()
                }
            } else {
                // No suggestion - show "yes" and cancel options
                Button("Yes") {
                    showOriginalDefinition()
                }
                Button("Cancel", role: .cancel) {
                    cancelSearch()
                }
            }
        } message: {
            Text("\"\(currentSearchQuery)\" is likely not a valid word or phrase, are you sure you want to read its definition?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .performSearchFromOnboarding)) { notification in
            if let word = notification.object as? String {
                // Set the search text and perform search
                searchText = word
                searchWord()
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

        // Single merged call to get both definition and validation
        DictionaryService.shared.searchWord(searchQuery) { result in
            DispatchQueue.main.async {
                self.isLoading = false

                switch result {
                case .success(let definitions):
                    guard let definition = definitions.first else {
                        self.errorMessage = "No definition found"
                        return
                    }

                    // Store V3 validation data
                    self.currentWordConfidence = definition.validWordScore
                    self.validationSuggestion = definition.suggestion

                    if definition.isValid {
                        // High confidence (≥0.9) - show definition immediately + auto-save
                        self.definitions = definitions

                        // Auto-save the word
                        self.autoSaveWord(definition.word)

                        // Track successful search
                        AnalyticsManager.shared.track(action: .dictionaryAutoSave, metadata: [
                            "word": definition.word,
                            "confidence": definition.validWordScore,
                            "language": UserManager.shared.learningLanguage
                        ])
                    } else {
                        // Low confidence (<0.9) - store definition and show alert
                        // User can choose to view this definition or search for suggestion
                        self.pendingDefinitions = definitions
                        self.showValidationAlert = true

                        // Track validation event
                        AnalyticsManager.shared.track(action: .validationInvalid, metadata: [
                            "original_query": searchQuery,
                            "confidence": definition.validWordScore,
                            "suggested": definition.suggestion ?? "none",
                            "language": UserManager.shared.learningLanguage
                        ])
                    }

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.definitions = []
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


    private func showOriginalDefinition() {
        // Track user choosing original word
        AnalyticsManager.shared.track(action: .validationUseOriginal, metadata: [
            "original_query": currentSearchQuery,
            "suggested": validationSuggestion ?? "none",
            "language": UserManager.shared.learningLanguage
        ])

        showValidationAlert = false

        // Display the definition we already fetched (no need to ask backend again!)
        self.definitions = pendingDefinitions

        // Do NOT auto-save low-confidence words
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
        pendingDefinitions = []
        errorMessage = nil
        currentSearchQuery = ""
        validationSuggestion = nil
        currentWordConfidence = 1.0
    }

    private func autoSaveWord(_ word: String) {
        // Check if word is already saved with current language pair to avoid duplicates
        DictionaryService.shared.getSavedWords { result in
            switch result {
            case .success(let savedWords):
                let isAlreadySaved = savedWords.contains {
                    $0.word.lowercased() == word.lowercased() &&
                    $0.learning_language == UserManager.shared.learningLanguage &&
                    $0.native_language == UserManager.shared.nativeLanguage
                }

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

}


#Preview {
    SearchView()
}
