//
//  ClickableTextView.swift
//  dogetionary
//
//  Reusable component that makes words in text tappable for definition lookup
//

import SwiftUI

struct ClickableTextView: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    let alignment: TextAlignment

    @State private var selectedWord: String?
    @State private var showDefinition = false
    @State private var definition: Definition?
    @State private var isLoadingDefinition = false

    init(
        text: String,
        font: Font = .body,
        foregroundColor: Color = .primary,
        alignment: TextAlignment = .leading
    ) {
        self.text = text
        self.font = font
        self.foregroundColor = foregroundColor
        self.alignment = alignment
    }

    var body: some View {
        Text(makeAttributedString())
            .font(font)
            .foregroundColor(foregroundColor)
            .multilineTextAlignment(alignment)
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
                    .navigationTitle(selectedWord?.capitalized ?? "")
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

    // MARK: - Helper Methods

    private func makeAttributedString() -> AttributedString {
        var result = AttributedString()

        // Split text into tokens (words + punctuation + spaces)
        let tokens = tokenize(text: text)

        for token in tokens {
            var tokenAttr = AttributedString(token.text)

            // Set default foreground color
            tokenAttr.foregroundColor = foregroundColor

            // Make word-tokens tappable with custom URL scheme
            if token.isWord {
                let cleanWord = token.text.trimmingCharacters(in: .punctuationCharacters)
                tokenAttr.link = URL(string: "word://\(cleanWord)")
            }

            result.append(tokenAttr)
        }

        return result
    }

    private func tokenize(text: String) -> [Token] {
        var tokens: [Token] = []
        var currentWord = ""

        for char in text {
            if char.isLetter || char.isNumber || char == "-" || char == "'" {
                // Part of a word
                currentWord.append(char)
            } else {
                // Punctuation or whitespace
                if !currentWord.isEmpty {
                    tokens.append(Token(text: currentWord, isWord: true))
                    currentWord = ""
                }
                tokens.append(Token(text: String(char), isWord: false))
            }
        }

        // Don't forget last word
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

        // Clean up the word (remove any remaining punctuation)
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

    // MARK: - Supporting Types

    private struct Token {
        let text: String
        let isWord: Bool
    }
}

// MARK: - Preview

#Preview("Clickable Text - Question") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack(spacing: 20) {
            ClickableTextView(
                text: "What does 'diagnosis' mean in medical context?",
                font: .title3,
                foregroundColor: AppTheme.bodyText,
                alignment: .center
            )
            .padding()

            ClickableTextView(
                text: "Early diagnosis is crucial for effective treatment and better outcomes.",
                font: .body,
                foregroundColor: AppTheme.bodyText,
                alignment: .leading
            )
            .padding()
        }
    }
}
