//
//  ThemeConstants.swift
//  dogetionary
//
//  App-wide theme constants for consistent styling
//  Based on ScheduleView design system
//

import SwiftUI

struct AppTheme {
    // MARK: - Colors

    /// Primary blue for accents and highlights
    static let primaryBlue = Color(red: 0.3, green: 0.4, blue: 0.9)

    /// Light blue for backgrounds and secondary elements
    static let lightBlue = Color(red: 0.95, green: 0.97, blue: 1.0)

    /// Very light blue for nested backgrounds
    static let veryLightBlue = Color(red: 0.98, green: 0.99, blue: 1.0)

    /// Accent purple for TODAY badge
    static let accentPurple = Color(red: 0.5, green: 0.45, blue: 1.0)

    // Category colors (New, Test, Custom)
    static let newWordColor = Color(red: 1.0, green: 0.6, blue: 0.4) // Orange
    static let testPracticeColor = Color(red: 0.4, green: 0.8, blue: 0.6) // Green
    static let customPracticeColor = Color(red: 0.5, green: 0.7, blue: 1.0) // Blue

    // Category background colors
    static let newWordBackground = Color(red: 1.0, green: 0.95, blue: 0.9)
    static let testPracticeBackground = Color(red: 0.9, green: 0.98, blue: 0.95)
    static let customPracticeBackground = Color(red: 0.95, green: 0.97, blue: 1.0)

    // Category text colors
    static let newWordTextColor = Color(red: 0.8, green: 0.4, blue: 0.2)
    static let testPracticeTextColor = Color(red: 0.2, green: 0.6, blue: 0.4)
    static let customPracticeTextColor = Color(red: 0.3, green: 0.5, blue: 0.9)

    // MARK: - Gradients

    /// Main background gradient (light blue to white)
    static let backgroundGradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Primary gradient for highlighted elements (blue to purple)
    static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.4, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.4, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Secondary gradient for subtle backgrounds
    static let secondaryGradient = LinearGradient(
        colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color(red: 0.92, green: 0.95, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Card Styling

    static let cardBackground = Color.white
    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let cardShadowColor = Color.black.opacity(0.05)
    static let cardShadowRadius: CGFloat = 8
    static let cardSpacing: CGFloat = 16

    // MARK: - Badge Styling

    static let badgeCornerRadius: CGFloat = 6
    static let badgeHorizontalPadding: CGFloat = 8
    static let badgeVerticalPadding: CGFloat = 4
    static let badgeOpacity: Double = 0.15

    // MARK: - Section Styling

    static let sectionCornerRadius: CGFloat = 10
    static let sectionPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 12

    // MARK: - Typography

    static let largeTitleFont = Font.system(size: 24, weight: .bold)
    static let titleFont = Font.system(size: 17, weight: .semibold)
    static let bodyFont = Font.system(size: 15)
    static let captionFont = Font.system(size: 13, weight: .semibold)
    static let smallCaptionFont = Font.system(size: 12)
    static let badgeLabelFont = Font.system(size: 11, weight: .medium)
    static let badgeCountFont = Font.system(size: 12, weight: .bold)
    static let tinyBadgeFont = Font.system(size: 9, weight: .bold)

    // MARK: - Empty State Styling

    static let emptyStateIconSize: CGFloat = 48
    static let emptyStateCircleSize: CGFloat = 100

    // MARK: - Helper Views

    /// Create a badge with consistent ScheduleView styling
    static func taskBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(badgeCountFont)
            Text(label)
                .font(badgeLabelFont)
        }
        .foregroundColor(color)
        .padding(.horizontal, badgeHorizontalPadding)
        .padding(.vertical, badgeVerticalPadding)
        .background(color.opacity(badgeOpacity))
        .cornerRadius(badgeCornerRadius)
    }

    /// Create a section with consistent ScheduleView styling
    static func section(label: String, count: Int, content: String, backgroundColor: Color, textColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(captionFont)
                    .foregroundColor(.secondary)
                Text("(\(count))")
                    .font(smallCaptionFont)
                    .foregroundColor(.secondary)
            }

            Text(content)
                .font(bodyFont)
                .foregroundColor(textColor)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(sectionPadding)
        .background(backgroundColor)
        .cornerRadius(sectionCornerRadius)
    }

    /// Create a card container with consistent ScheduleView styling
    static func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(cardBackground)
            .cornerRadius(cardCornerRadius)
            .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: 2)
    }

    /// Create an empty state view with consistent ScheduleView styling
    static func emptyState(icon: String, title: String, message: String, iconColor: Color = primaryBlue) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(lightBlue)
                    .frame(width: emptyStateCircleSize, height: emptyStateCircleSize)

                Image(systemName: icon)
                    .font(.system(size: 50))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
