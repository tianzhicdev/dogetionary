//
//  WordDefinitionSheet.swift
//  dogetionary
//
//  Sheet view that displays word definition from dictionary API
//

import SwiftUI

struct WordDefinitionSheet: View {
    let word: String

    @Environment(\.dismiss) private var dismiss

    @State private var definition: Definition? = nil
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            ZStack {
                AppTheme.verticalGradient2.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isLoading {
                            loadingView
                        } else if let error = errorMessage {
                            errorView(message: error)
                        } else if definition == nil {
                            notFoundView
                        } else if let definition = definition {
                            definitionView(definition)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(word.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.selectableTint)
                }
            }
        }
        .onAppear {
            loadDefinition()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .padding()

            Text("Looking up '\(word)'...")
                .font(.headline)
                .foregroundColor(AppTheme.bodyText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("Error")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.smallTitleText)

            Text(message)
                .font(.body)
                .foregroundColor(AppTheme.bodyText)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                loadDefinition()
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.selectableTint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private var notFoundView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Definition Found")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.smallTitleText)

            Text("Could not find a definition for '\(word)'")
                .font(.body)
                .foregroundColor(AppTheme.bodyText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private func definitionView(_ definition: Definition) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Phonetic if available
            if let phonetic = definition.phonetic, !phonetic.isEmpty {
                Text(phonetic)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Translations if available
            if !definition.translations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Translations:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(definition.translations.joined(separator: ", "))
                        .font(.body)
                        .foregroundColor(AppTheme.bodyText)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemBackground).opacity(0.7))
                )
            }

            // Meanings
            ForEach(Array(definition.meanings.enumerated()), id: \.offset) { _, meaning in
                VStack(alignment: .leading, spacing: 12) {
                    // Part of speech
                    Text(meaning.partOfSpeech)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.selectableTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppTheme.selectableTint.opacity(0.1))
                        )

                    // Definitions for this part of speech
                    ForEach(Array(meaning.definitions.enumerated()), id: \.offset) { idx, def in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(idx + 1). \(def.definition)")
                                .font(.body)
                                .foregroundColor(AppTheme.bodyText)

                            // Example if available
                            if let example = def.example, !example.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "quote.opening")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.selectableTint)

                                    Text(example)
                                        .font(.callout)
                                        .italic()
                                        .foregroundColor(AppTheme.bodyText.opacity(0.8))
                                }
                                .padding(.leading, 8)
                            }
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground).opacity(0.7))
                )
            }
        }
    }

    // MARK: - Helper Methods

    private func loadDefinition() {
        isLoading = true
        errorMessage = nil

        // Use default language values - the API will return appropriate results
        DictionaryService.shared.searchWord(
            word,
            learningLanguage: "en",
            nativeLanguage: "zh"
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let defs):
                    definition = defs.first
                    isLoading = false
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Preview

// Note: Preview disabled because AppState has private initializer
// To test, run the app and tap on any word in a question
