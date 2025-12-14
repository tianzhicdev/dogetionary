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
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationView {
            SavedWordsListView(
                savedWords: $savedWords,
                isLoading: isLoading,
                errorMessage: errorMessage,
                onRefresh: { await loadSavedWords() },
                onDelete: { word in await deleteSavedWord(word) },
                onToggleKnown: { word in await toggleKnownStatus(word) }
            )
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            Task {
                await loadSavedWords()
            }
        }
        .onChange(of: appState.shouldRefreshSavedWords) { _, shouldRefresh in
            if shouldRefresh {
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
                        // Sort: known words at bottom, then by next_review_date ascending
                        self.savedWords = words.sorted { word1, word2 in
                            // Known words go to the bottom
                            if word1.is_known != word2.is_known {
                                return !word1.is_known // non-known words first
                            }

                            // Within same known status, sort by next_review_date
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

    @MainActor
    private func deleteSavedWord(_ word: SavedWord) async {
        DictionaryService.shared.unsaveWord(wordID: word.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Remove word from local array
                    self.savedWords.removeAll { $0.id == word.id }

                    // Notify other views that word was deleted
                    AppState.shared.markWordUnsaved(word.word)

                    // Track deletion analytics
                    AnalyticsManager.shared.track(action: .savedDeleteWord, metadata: [
                        "word": word.word,
                        "word_id": word.id
                    ])
                case .failure(let error):
                    self.errorMessage = "Failed to delete word: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func toggleKnownStatus(_ word: SavedWord) async {
        let newKnownStatus = !word.is_known
        DictionaryService.shared.toggleExcludeFromPractice(
            word: word.word,
            excluded: newKnownStatus,
            learningLanguage: word.learning_language,
            nativeLanguage: word.native_language
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Update local state
                    if let index = self.savedWords.firstIndex(where: { $0.id == word.id }) {
                        self.savedWords[index].is_known = newKnownStatus
                    }

                    // Re-sort to move known words to bottom
                    self.savedWords.sort { word1, word2 in
                        if word1.is_known != word2.is_known {
                            return !word1.is_known
                        }
                        guard let date1 = word1.next_review_date else { return false }
                        guard let date2 = word2.next_review_date else { return true }
                        let formatter = ISO8601DateFormatter()
                        guard let d1 = formatter.date(from: date1),
                              let d2 = formatter.date(from: date2) else { return false }
                        return d1 < d2
                    }

                    // Track analytics
                    AnalyticsManager.shared.track(
                        action: newKnownStatus ? .savedMarkKnown : .savedMarkLearning,
                        metadata: ["word": word.word, "word_id": word.id]
                    )
                case .failure(let error):
                    self.errorMessage = "Failed to update word: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct SavedWordsListView: View {
    @Binding var savedWords: [SavedWord]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () async -> Void
    let onDelete: (SavedWord) async -> Void
    let onToggleKnown: (SavedWord) async -> Void

    @State private var filterText = ""

    private var filteredWords: [SavedWord] {
        if filterText.isEmpty {
            return savedWords
        } else {
            return savedWords.filter { $0.word.lowercased().contains(filterText.lowercased()) }
        }
    }

    var body: some View {
        ZStack {
            // Soft blue gradient background
            AppTheme.verticalGradient2
                .ignoresSafeArea()

            Group {
                if isLoading {
                    ProgressView("LOADING SAVED WORDS...")
                        .tint(AppTheme.accentCyan)
                        .foregroundColor(AppTheme.smallTitleText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if savedWords.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: AppTheme.emptyStateIconSize))
                            .foregroundColor(AppTheme.accentCyan)

                        Text("NO SAVED WORDS")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.smallTitleText)

                        Text("WORDS YOU SAVE WILL APPEAR HERE")
                            .font(.body)
                            .foregroundColor(AppTheme.smallTextColor1)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: AppTheme.emptyStateIconSize))
                            .foregroundColor(AppTheme.selectableTint)
                        Text(errorMessage.uppercased())
                            .foregroundColor(AppTheme.selectableTint)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Filter text bar

                        HStack {
                            TextField("", text: $filterText)
                                .font(.title2)
                                .foregroundColor(AppTheme.textFieldUserInput)
                            if !filterText.isEmpty {
                                Button(action: {
                                    filterText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(AppTheme.selectableTint)
                                        .font(.title3)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical, 4)
                        .background(AppTheme.textFieldBackgroundColor)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(AppTheme.textFieldBorderColor, lineWidth: 2)
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        // Word list
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredWords) { savedWord in
                                    NavigationLink(destination: WordDetailView(savedWord: savedWord)
                                        .onAppear {
                                            // Track saved word view details when navigation happens
                                            AnalyticsManager.shared.track(action: .savedViewDetails, metadata: [
                                                "word": savedWord.word,
                                                "review_count": savedWord.review_count,
                                                "is_overdue": isOverdue(savedWord.next_review_date ?? "")
                                            ])
                                        }
                                    ) {
                                        SavedWordRow(
                                            savedWord: savedWord,
                                            onToggleKnown: { Task { await onToggleKnown(savedWord) } },
                                            onDelete: { Task { await onDelete(savedWord) } }
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                        }
                    }
                }
            }
        }
        .refreshable {
            await onRefresh()
        }
    }

    private func isOverdue(_ dateString: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            return date < Date()
        }
        return false
    }
}


struct SavedWordRow: View {
    let savedWord: SavedWord
    var onToggleKnown: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @ObservedObject private var userManager = UserManager.shared

    var body: some View {
        HStack(spacing: 10) {
            // Word name with test badges
            HStack(spacing: 6) {
                Text(savedWord.word)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.bodyText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Show test labels only if user has enabled tests
                testLabels
            }

            Spacer(minLength: 8)

            // Review counts - compact inline
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(AppTheme.selectableTint)
                    Text("\(savedWord.incorrect_reviews)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.smallTextColor1)
                }

                HStack(spacing: 2) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(AppTheme.accentCyan)
                    Text("\(savedWord.correct_reviews)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.smallTextColor1)
                }
            }

            // 7-level progress indicator
            WordProgressBar(progressLevel: savedWord.word_progress_level)

            // Action menu button
            if onToggleKnown != nil || onDelete != nil {
                Menu {
                    if let onToggleKnown = onToggleKnown {
                        Button {
                            onToggleKnown()
                        } label: {
                            if savedWord.is_known {
                                Label("INCLUDE IN PRACTICE", systemImage: "book.fill")
                            } else {
                                Label("EXCLUDE FROM PRACTICE", systemImage: "xmark.circle.fill")
                            }
                        }
                    }

                    if let onDelete = onDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("DELETE", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.accentCyan)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.clear)
    }

    @ViewBuilder
    private var testLabels: some View {
        HStack(spacing: 4) {
            if userManager.toeflEnabled && (savedWord.is_toefl == true) {
                Text("TOEFL")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(AppTheme.bgPrimary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(AppTheme.accentCyan)
                    .cornerRadius(4)
            }

            if userManager.ieltsEnabled && (savedWord.is_ielts == true) {
                Text("IELTS")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(AppTheme.bgPrimary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(AppTheme.electricYellow)
                    .cornerRadius(4)
            }

            if userManager.tianzEnabled && (savedWord.is_tianz == true) {
                Text("TIANZ")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(AppTheme.bgPrimary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(AppTheme.selectableTint)
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - 7-Level Progress Indicator

struct WordProgressBar: View {
    let progressLevel: Int  // 1-7 scale from backend

    // Gradient color based on progress level
    private var progressColor: LinearGradient {
        return LinearGradient(
            colors: [AppTheme.selectableTint, AppTheme.neonPurple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var emptyColor: Color {
        AppTheme.bgPrimary
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                let isFilled = (index + 1) <= progressLevel

                Capsule()
                    .fill(isFilled ? AnyShapeStyle(progressColor) : AnyShapeStyle(emptyColor))
                    .frame(width: 4, height: index < progressLevel ? 14 : 10)
            }
        }
        .frame(height: 14)
    }
}

#Preview {
    SavedWordsView()
}
