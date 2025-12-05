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
            return AppTheme.accentCyan
        case "neutral":
            return AppTheme.neonPurple
        case "informal":
            return AppTheme.electricYellow
        case "slang":
            return AppTheme.selectableTint
        case "literary":
            return AppTheme.accentCyan
        case "technical":
            return AppTheme.neonPurple
        default:
            return AppTheme.smallTitleText
        }
    }

    var body: some View {
        Text(register.uppercased())
            .font(AppTheme.badgeLabelFont)
            .foregroundColor(AppTheme.bgPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(4)
    }
}

// MARK: - Frequency Badge

struct FrequencyBadge: View {
    let frequency: String

    private var color: Color {
        switch frequency.lowercased() {
        case "very_common":
            return AppTheme.accentCyan
        case "common":
            return AppTheme.electricYellow
        case "uncommon":
            return AppTheme.selectableTint
        case "rare":
            return AppTheme.neonPurple
        default:
            return AppTheme.smallTitleText
        }
    }

    private var displayText: String {
        switch frequency.lowercased() {
        case "very_common":
            return "VERY COMMON"
        case "common":
            return "COMMON"
        case "uncommon":
            return "UNCOMMON"
        case "rare":
            return "RARE"
        default:
            return frequency.uppercased()
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(displayText)
                .font(AppTheme.badgeLabelFont)
                .foregroundColor(AppTheme.bgPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color)
        .cornerRadius(4)
    }
}

// MARK: - Connotation Badge

struct ConnotationBadge: View {
    let connotation: String

    private var color: Color {
        switch connotation.lowercased() {
        case "positive":
            return AppTheme.accentCyan
        case "negative":
            return AppTheme.selectableTint
        case "neutral":
            return AppTheme.smallTitleText
        default:
            return AppTheme.smallTitleText
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
                .foregroundColor(AppTheme.bgPrimary)
            Text(connotation.uppercased())
                .font(AppTheme.badgeLabelFont)
                .foregroundColor(AppTheme.bgPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color)
        .cornerRadius(4)
    }
}

// MARK: - Tag Pill

struct TagPill: View {
    let tag: String

    var body: some View {
        Text(tag.uppercased())
            .font(AppTheme.badgeLabelFont)
            .foregroundColor(AppTheme.bgPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.accentCyan)
            .cornerRadius(4)
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
                        .foregroundColor(AppTheme.accentCyan)

                    Text(title.uppercased())
                        .font(AppTheme.titleFont)
                        .foregroundColor(AppTheme.smallTitleText)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.selectableTint)
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
        .background(AppTheme.bgPrimary)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(AppTheme.accentCyan.opacity(0.3), lineWidth: 1)
        )
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
                Image(systemName: title == "SYNONYMS" ? "equal.circle.fill" : "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(color)

                Text(title)
                    .font(AppTheme.captionFont)
                    .foregroundColor(AppTheme.smallTitleText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(words, id: \.self) { word in
                        Text(word.uppercased())
                            .font(AppTheme.bodyFont)
                            .foregroundColor(AppTheme.bgPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(color)
                            .cornerRadius(4)
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
                    .foregroundColor(AppTheme.smallTitleText)
            }

            content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.bgPrimary)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(color.opacity(0.3), lineWidth: 1)
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
                    .foregroundColor(AppTheme.smallTitleText)
                    .padding(.top, 2)

                Text(quote.quote)
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .foregroundColor(AppTheme.bodyText)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Text("— \(quote.source)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.smallTextColor1)
            }
        }
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
