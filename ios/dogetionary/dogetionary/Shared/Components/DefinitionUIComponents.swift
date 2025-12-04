//
//  DefinitionUIComponents.swift
//  dogetionary
//
//  V4 UI components for enhanced vocabulary learning features
//

import SwiftUI

// MARK: - Register Badge

struct RegisterBadge: View {
    let register: String

    private var color: Color {
        switch register.lowercased() {
        case "formal":
            return AppTheme.infoColor
        case "neutral":
            return Color.purple
        case "informal":
            return AppTheme.warningColor
        case "slang":
            return AppTheme.errorColor
        case "literary":
            return Color.indigo
        case "technical":
            return Color.teal
        default:
            return Color.gray
        }
    }

    var body: some View {
        Text(register.capitalized)
            .font(AppTheme.badgeLabelFont)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(6)
    }
}

// MARK: - Frequency Badge

struct FrequencyBadge: View {
    let frequency: String

    private var color: Color {
        switch frequency.lowercased() {
        case "very_common":
            return AppTheme.successColor
        case "common":
            return AppTheme.yellowGreen
        case "uncommon":
            return AppTheme.warningColor
        case "rare":
            return AppTheme.errorColor
        default:
            return Color.gray
        }
    }

    private var displayText: String {
        switch frequency.lowercased() {
        case "very_common":
            return "Very Common"
        case "common":
            return "Common"
        case "uncommon":
            return "Uncommon"
        case "rare":
            return "Rare"
        default:
            return frequency.capitalized
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(displayText)
                .font(AppTheme.badgeLabelFont)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(AppTheme.lightOpacity))
        .cornerRadius(6)
    }
}

// MARK: - Connotation Badge

struct ConnotationBadge: View {
    let connotation: String

    private var color: Color {
        switch connotation.lowercased() {
        case "positive":
            return AppTheme.successColor
        case "negative":
            return AppTheme.errorColor
        case "neutral":
            return Color.gray
        default:
            return Color.gray
        }
    }

    private var icon: String {
        switch connotation.lowercased() {
        case "positive":
            return "hand.thumbsup.fill"
        case "negative":
            return "hand.thumbsdown.fill"
        case "neutral":
            return "minus.circle.fill"
        default:
            return "circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(connotation.capitalized)
                .font(AppTheme.badgeLabelFont)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(AppTheme.lightOpacity))
        .cornerRadius(6)
    }
}

// MARK: - Tag Pill

struct TagPill: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(AppTheme.badgeLabelFont)
            .foregroundColor(AppTheme.infoColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.lightBlue)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.infoColor.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Collapsible Section

struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @State private var isExpanded = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.infoColor)

                    Text(title)
                        .font(AppTheme.titleFont)
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                content
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(AppTheme.veryLightBlue)
        .cornerRadius(10)
    }
}

// MARK: - Synonym/Antonym Row

struct SynonymAntonymRow: View {
    let title: String
    let words: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: title == "Synonyms" ? "equal.circle.fill" : "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(color)

                Text(title)
                    .font(AppTheme.captionFont)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(words, id: \.self) { word in
                        Text(word)
                            .font(AppTheme.bodyFont)
                            .foregroundColor(color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(color.opacity(AppTheme.lightOpacity))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Info Section

struct InfoSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)

                Text(title)
                    .font(AppTheme.captionFont)
                    .foregroundColor(.secondary)
            }

            content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(AppTheme.subtleOpacity))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quote Card

struct QuoteCard: View {
    let quote: FamousQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.infoColor.opacity(0.6))
                    .padding(.top, 2)

                Text(quote.quote)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundColor(.primary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Text("— \(quote.source)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(AppTheme.veryLightBlue)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.infoColor.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // Badges
            HStack(spacing: 8) {
                RegisterBadge(register: "formal")
                FrequencyBadge(frequency: "very_common")
                ConnotationBadge(connotation: "positive")
            }

            // Tags
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    TagPill(tag: "business")
                    TagPill(tag: "academic")
                    TagPill(tag: "formal")
                }
            }

            // Collapsible Section
            CollapsibleSection(title: "Word Family", icon: "link") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("persuade (verb)")
                    Text("persuasion (noun)")
                    Text("persuasive (adjective)")
                }
            }

            // Synonyms
            SynonymAntonymRow(title: "Synonyms", words: ["convince", "influence", "sway"], color: AppTheme.successColor)

            // Info Section
            InfoSection(title: "Common Confusions", icon: "exclamationmark.triangle", color: AppTheme.warningColor) {
                Text("Often confused with 'prosecute' which means to bring legal action.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Quote Card
            QuoteCard(quote: FamousQuote(quote: "The art of persuasion consists as much in that of pleasing as in that of convincing.", source: "Blaise Pascal"))
        }
        .padding()
    }
}
