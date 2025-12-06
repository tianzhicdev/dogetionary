//
//  FullscreenWordCardView.swift
//  dogetionary
//
//  Created by Claude Code on 12/6/25.
//

import SwiftUI

/// Fullscreen modal view for displaying word with illustration
/// Triggered when user taps on illustration thumbnail in DefinitionCard
struct FullscreenWordCardView: View {
    let word: String
    let phonetic: String?
    let firstDefinition: String?
    let illustration: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                
                AppTheme.verticalGradient2.ignoresSafeArea()
            VStack(spacing: 24) {
                // Main illustration
                Image(uiImage: illustration)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 400)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 10)
                
                // Word card content
                VStack(spacing: 16) {
                    // Word and pronunciation
                    VStack(spacing: 8) {
                        Text(word)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(AppTheme.bigTitleText)
                        
                        if let phonetic = phonetic {
                            Text(phonetic)
                                .font(.title2)
                                .foregroundColor(AppTheme.smallTitleText)
                        }
                    }
                    
                    // First definition
                    if let firstDefinition = firstDefinition {
                        Text(firstDefinition)
                            .font(.title3)
                            .foregroundColor(AppTheme.bodyText)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .padding(.horizontal)
                    }
                }
                .padding()

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("DONE")
                            .font(.headline)
                            .foregroundColor(AppTheme.selectableTint)
                    }
                }
            }
        }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Preview

#Preview("With Phonetic and Definition") {
    FullscreenWordCardView(
        word: "serendipity",
        phonetic: "/ˌser.ənˈdɪp.ə.ti/",
        firstDefinition: "The occurrence of events by chance in a happy or beneficial way",
        illustration: createSampleIllustration()
    )
}

#Preview("Without Phonetic") {
    FullscreenWordCardView(
        word: "adventure",
        phonetic: nil,
        firstDefinition: "An unusual and exciting, typically hazardous, experience or activity",
        illustration: createSampleIllustration()
    )
}

#Preview("Minimal - No Definition") {
    FullscreenWordCardView(
        word: "ephemeral",
        phonetic: "/ɪˈfem.ər.əl/",
        firstDefinition: nil,
        illustration: createSampleIllustration()
    )
}

#Preview("Long Definition") {
    FullscreenWordCardView(
        word: "antidisestablishmentarianism",
        phonetic: "/ˌæn.ti.dɪ.sɪˌstæb.lɪʃ.mənˈteə.ri.ə.nɪ.zəm/",
        firstDefinition: "Opposition to the disestablishment of the Church of England - originally a political position in 19th century England, now typically used as an example of a very long word",
        illustration: createSampleIllustration()
    )
}

// MARK: - Preview Helper

/// Creates a sample illustration for preview purposes
private func createSampleIllustration() -> UIImage {
    let size = CGSize(width: 400, height: 400)
    let renderer = UIGraphicsImageRenderer(size: size)

    return renderer.image { context in
        // Gradient background
        let colors = [
            UIColor(AppTheme.accentCyan).cgColor,
            UIColor(AppTheme.neonPurple).cgColor,
            UIColor(AppTheme.accentPink).cgColor
        ]

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0.0, 0.5, 1.0]
        )!

        context.cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size.width, y: size.height),
            options: []
        )

        // Add some decorative circles
        UIColor(AppTheme.electricYellow).withAlphaComponent(0.3).setFill()
        let circle1 = CGRect(x: 50, y: 50, width: 100, height: 100)
        context.cgContext.fillEllipse(in: circle1)

        UIColor(AppTheme.accentCyan).withAlphaComponent(0.2).setFill()
        let circle2 = CGRect(x: 250, y: 200, width: 120, height: 120)
        context.cgContext.fillEllipse(in: circle2)

        // Add text "Sample Illustration"
        let text = "SAMPLE\nILLUSTRATION"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 32),
            .foregroundColor: UIColor.white.withAlphaComponent(0.8)
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        attributedString.draw(in: textRect)
    }
}
