//
//  SectionHeader.swift
//  dogetionary
//
//  Reusable section header component for consistent styling
//

import SwiftUI

struct SectionHeader: View {
    let title: String
    let subtitle: String?
    let action: (() -> Void)?
    let actionLabel: String?

    init(
        _ title: String,
        subtitle: String? = nil,
        action: (() -> Void)? = nil,
        actionLabel: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.actionLabel = actionLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
            HStack {
                Text(title.uppercased())
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.smallTitleText)

                Spacer()

                if let action = action, let actionLabel = actionLabel {
                    Button(action: action) {
                        Text(actionLabel.uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.selectableTint)
                    }
                }
            }

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppTheme.smallTextColor1)
            }
        }
    }
}

// MARK: - Preview

#Preview("Section Headers") {
    VStack(spacing: 30) {
        SectionHeader("Simple Header")

        SectionHeader(
            "Header with Subtitle",
            subtitle: "This is additional information about the section"
        )

        SectionHeader(
            "Header with Action",
            action: { print("Action tapped") },
            actionLabel: "See All"
        )

        SectionHeader(
            "Complete Header",
            subtitle: "With both subtitle and action button",
            action: { print("Action tapped") },
            actionLabel: "View More"
        )
    }
    .padding()
    .background(AppTheme.bgPrimary)
}
