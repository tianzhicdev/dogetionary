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

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Search bar with clear button and search button
                HStack(spacing: 12) {
                    HStack {
                        TextField("Enter an English word", text: $searchText)
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
            .navigationTitle("Dogetionary")
            .contentShape(Rectangle())
            .onTapGesture {
                // Dismiss keyboard when tapping outside text field
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    
    private func searchWord() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        DictionaryService.shared.searchWord(searchText) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let definitions):
                    self.definitions = definitions
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.definitions = []
                }
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
                    // Save button
                    Button(action: {
                        if isSaved {
                            // Could implement unsave functionality here
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
                    
                    // Audio play button
                    if let audioData = definition.audioData {
                        Button(action: {
                            if audioPlayer.isPlaying {
                                audioPlayer.stopAudio()
                            } else {
                                audioPlayer.playAudio(from: audioData)
                            }
                        }) {
                            Image(systemName: audioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
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
                                Text("Example: \(example)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
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
        }
    }
    
    private func saveWord() {
        isSaving = true
        
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
}

#Preview {
    SearchView()
        .modelContainer(for: Item.self, inMemory: true)
}