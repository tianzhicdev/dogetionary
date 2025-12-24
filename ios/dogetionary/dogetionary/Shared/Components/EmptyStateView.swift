//
//  EmptyStateView.swift
//  dogetionary
//
//  Reusable empty state component for consistent UI across the app
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let action: (() -> Void)?
    let actionLabel: String?

    /// Creates an empty state view with icon, title, and message
    /// - Parameters:
    ///   - icon: SF Symbol name for the icon
    ///   - title: Title text (will be uppercased)
    ///   - message: Description message (will be uppercased)
    ///   - action: Optional action closure for a button
    ///   - actionLabel: Label for the action button (required if action is provided)
    init(
        icon: String,
        title: String,
        message: String,
        action: (() -> Void)? = nil,
        actionLabel: String? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
        self.actionLabel = actionLabel
    }

    var body: some View {
        VStack(spacing: AppTheme.spacingL) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: AppTheme.emptyStateIconSize))
                .foregroundColor(AppTheme.accentCyan)

            // Title
            Text(title.uppercased())
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.smallTitleText)

            // Message
            Text(message.uppercased())
                .font(.subheadline)
                .foregroundColor(AppTheme.smallTextColor1)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Optional action button
            if let action = action, let actionLabel = actionLabel {
                Button(action: action) {
                    Text(actionLabel.uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, AppTheme.spacingL)
                        .padding(.vertical, AppTheme.spacingM)
                        .background(AppTheme.selectableTint)
                        .cornerRadius(AppTheme.cornerRadiusM)
                }
                .padding(.top, AppTheme.spacingM)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Empty State Variants") {
    VStack(spacing: 40) {
        // No action
        EmptyStateView(
            icon: "calendar.badge.plus",
            title: "No Schedule Yet",
            message: "Create a schedule to start practicing"
        )
        .frame(height: 200)
        .background(AppTheme.bgPrimary)

        // With action
        EmptyStateView(
            icon: "clock",
            title: "No Practice Yet",
            message: "This word hasn't been practiced yet",
            action: { print("Action tapped") },
            actionLabel: "Start Practice"
        )
        .frame(height: 250)
        .background(AppTheme.bgPrimary)
    }
    .background(AppTheme.verticalGradient2)
}
