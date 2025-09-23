//
//  AIIllustrationView.swift
//  dogetionary
//
//  Created by biubiu on 9/12/25.
//

import SwiftUI

struct AIIllustrationView: View {
    let word: String
    let language: String
    let definition: Definition?
    @Binding var illustration: IllustrationResponse?
    @Binding var isGenerating: Bool
    @Binding var error: String?
    @State private var showFullscreen = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
//            HStack {
//                Image(systemName: "photo.artframe")
//                    .foregroundColor(.blue)
//                Text("AI Illustration")
//                    .font(.headline)
//                    .foregroundColor(.blue)
//                Spacer()
//            }
//            
            if let illustration = illustration {
                // Show generated illustration - image only
                VStack(spacing: 8) {
                    if let imageData = Data(base64Encoded: illustration.image_data),
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .onTapGesture {
                                showFullscreen = true
                            }
                    }

                }
            } else if isGenerating {
                // Show loading state
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Generating AI illustration...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("This may take a moment")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
            } else {
                // Auto-generate on first appearance - no button needed
                EmptyView()
            }
            
            if let error = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .onAppear {
            // Try to load existing illustration, if not found, auto-generate
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
        // Track dictionary illustration generation
        AnalyticsManager.shared.track(action: .dictionaryIllustration, metadata: [
            "word": word,
            "language": language
        ])

        isGenerating = true
        error = nil

        DictionaryService.shared.generateIllustration(word: word, language: language) { result in
            DispatchQueue.main.async {
                self.isGenerating = false

                switch result {
                case .success(let illustrationResponse):
                    self.illustration = illustrationResponse
                    self.error = nil
                case .failure(let illustrationError):
                    self.error = "Failed to generate illustration: \(illustrationError.localizedDescription)"
                }
            }
        }
    }
}

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
                        Text(word)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        if let phonetic = phonetic {
                            Text(phonetic)
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // First definition
                    if let firstDefinition = firstDefinition {
                        Text(firstDefinition)
                            .font(.title3)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .padding(.horizontal)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(16)
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
