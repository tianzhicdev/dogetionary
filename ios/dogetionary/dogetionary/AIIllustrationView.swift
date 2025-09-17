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
    @Binding var illustration: IllustrationResponse?
    @Binding var isGenerating: Bool
    @Binding var error: String?
    
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
