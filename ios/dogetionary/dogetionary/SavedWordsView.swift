//
//  SavedWordsView.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI

struct SavedWordsView: View {
    @State private var savedWords: [SavedWord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading saved words...")
                        .padding()
                } else if savedWords.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No Saved Words")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Words you save will appear here")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List(savedWords) { savedWord in
                        NavigationLink(destination: WordDetailView(savedWord: savedWord)) {
                            SavedWordRow(savedWord: savedWord)
                        }
                    }
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("Saved Words")
            .refreshable {
                await loadSavedWords()
            }
            .onAppear {
                Task {
                    await loadSavedWords()
                }
            }
        }
    }
    
    @MainActor
    private func loadSavedWords() async {
        isLoading = true
        errorMessage = nil
        
        await withCheckedContinuation { continuation in
            DictionaryService.shared.getSavedWords { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success(let words):
                        // Sort by next_review_date ascending (soonest first)
                        self.savedWords = words.sorted { word1, word2 in
                            // Handle nil values - put words without reviews at the end
                            guard let date1 = word1.next_review_date else { return false }
                            guard let date2 = word2.next_review_date else { return true }
                            
                            // Parse dates and compare
                            let formatter = ISO8601DateFormatter()
                            guard let d1 = formatter.date(from: date1),
                                  let d2 = formatter.date(from: date2) else { return false }
                            
                            return d1 < d2
                        }
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
}

struct SavedWordRow: View {
    let savedWord: SavedWord
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(savedWord.word)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                HStack {
                    if let nextReviewDate = savedWord.next_review_date {
                        Text("Next review \(formatDateOnly(nextReviewDate))")
                            .font(.caption)
                            .foregroundColor(isOverdue(nextReviewDate) ? .red : .secondary)
                    } else {
                        Text("No reviews yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(savedWord.review_count) review\(savedWord.review_count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
    
    private func formatDateOnly(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .none
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    private func isOverdue(_ dateString: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            return date < Date()
        }
        return false
    }
}

#Preview {
    SavedWordsView()
}
