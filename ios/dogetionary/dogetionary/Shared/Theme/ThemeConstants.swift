//
//  ThemeConstants.swift
//  dogetionary
//
//  App-wide theme constants for consistent styling
//  Based on ScheduleView design system
//

import SwiftUI

struct AppTheme {
    // MARK: - Basic Colors

    
    
    
    /// Pure white color
    static let white = Color.white

    /// Pure black color
    static let black = Color.black

    /// Clear/transparent color
    static let clear = Color.clear

    /// Light gray (opacity 0.3)
    static let lightGray = Color.gray.opacity(0.3)

    /// Medium gray (opacity 0.5)
    static let mediumGray = Color.gray.opacity(0.5)

    /// Dark gray (opacity 0.7)
    static let darkGray = Color.gray.opacity(0.7)

    /// Disabled gray (opacity 0.6)
    static let disabledGray = Color.gray.opacity(0.6)

    // MARK: - System Colors

    /// System blue color
    static let systemBlue = Color.blue

    /// System purple color
    static let systemPurple = Color.purple

    /// System cyan color
    static let systemCyan = Color.cyan

    /// System pink color
    static let systemPink = Color.pink

    /// System indigo color
    static let systemIndigo = Color.indigo

    /// System teal color
    static let systemTeal = Color.teal

    /// System mint color
    static let systemMint = Color.mint

    /// System yellow color
    static let systemYellow = Color.yellow

    /// System orange color
    static let systemOrange = Color.orange

    /// System green color
    static let systemGreen = Color.green

    /// System red color
    static let systemRed = Color.red

    // MARK: - Colors

    /// Primary blue for accents and highlights
    static let primaryBlue = Color(red: 0.3, green: 0.4, blue: 0.9)

    /// Light blue for backgrounds and secondary elements
    static let lightBlue = Color(red: 0.95, green: 0.97, blue: 1.0)

    /// Medium light blue for calendar dates
    static let mediumLightBlue = Color(red: 0.92, green: 0.95, blue: 1.0)

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

    // MARK: - Feedback State Gradients

    /// Vibrant green gradient for correct answers
    static let feedbackCorrectGradient = LinearGradient(
        colors: [Color(red: 0.3, green: 0.85, blue: 0.5), Color(red: 0.2, green: 0.75, blue: 0.6)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Red-orange gradient for incorrect answers
    static let feedbackIncorrectGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.45, blue: 0.4), Color(red: 1.0, green: 0.6, blue: 0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Blue-cyan gradient for selected state
    static let feedbackSelectedGradient = LinearGradient(
        colors: [Color(red: 0.4, green: 0.7, blue: 1.0), Color(red: 0.3, green: 0.85, blue: 0.95)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle purple-blue gradient for default/unselected state
    static let feedbackDefaultGradient = LinearGradient(
        colors: [Color(red: 0.92, green: 0.93, blue: 0.98), Color(red: 0.90, green: 0.92, blue: 0.96)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle green gradient for unselected correct answer
    static let feedbackUnselectedCorrectGradient = LinearGradient(
        colors: [Color(red: 0.7, green: 0.95, blue: 0.75), Color(red: 0.6, green: 0.9, blue: 0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Green border gradient for correct answer
    static let borderCorrectGradient = LinearGradient(
        colors: [Color(red: 0.2, green: 0.8, blue: 0.4), Color(red: 0.3, green: 0.9, blue: 0.5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Red border gradient for incorrect answer
    static let borderIncorrectGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.3, blue: 0.3), Color(red: 1.0, green: 0.5, blue: 0.2)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Blue border gradient for selected state
    static let borderSelectedGradient = LinearGradient(
        colors: [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.4, green: 0.8, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Test Type Gradients

    /// Gradients for test types
    static let testTypeGradients: [TestType: LinearGradient] = [
        .toeflBeginner: LinearGradient(
            colors: [Color.green, Color.mint],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .toeflIntermediate: LinearGradient(
            colors: [Color.teal, Color.cyan],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .toeflAdvanced: LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .ieltsBeginner: LinearGradient(
            colors: [Color.orange, Color.yellow],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .ieltsIntermediate: LinearGradient(
            colors: [Color.pink, Color.red],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .ieltsAdvanced: LinearGradient(
            colors: [Color.purple, Color.indigo],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .tianz: LinearGradient(
            colors: [Color.indigo, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    ]

    // MARK: - State Colors

    /// Success color (green)
    static let successColor = Color.green

    /// Error color (red)
    static let errorColor = Color.red

    /// Warning color (orange)
    static let warningColor = Color.orange

    /// Info color (blue)
    static let infoColor = Color.blue

    /// Yellow-green color for progress indicators
    static let yellowGreen = Color(red: 0.6, green: 0.85, blue: 0.4)

    // MARK: - Medal/Rank Colors

    /// Gold gradient for 1st place
    static let goldGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.88, blue: 0.4), Color(red: 1.0, green: 0.75, blue: 0.2)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Silver gradient for 2nd place
    static let silverGradient = LinearGradient(
        colors: [Color(red: 0.85, green: 0.85, blue: 0.88), Color(red: 0.65, green: 0.65, blue: 0.70)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Bronze gradient for 3rd place
    static let bronzeGradient = LinearGradient(
        colors: [Color(red: 0.9, green: 0.65, blue: 0.45), Color(red: 0.7, green: 0.45, blue: 0.25)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Default rank gradient
    static let defaultRankGradient = LinearGradient(
        colors: [Color(red: 0.92, green: 0.93, blue: 0.95), Color(red: 0.85, green: 0.86, blue: 0.88)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Gold text color for 1st place
    static let goldTextColor = Color(red: 0.7, green: 0.5, blue: 0.1)

    /// Silver text color for 2nd place
    static let silverTextColor = Color(red: 0.4, green: 0.4, blue: 0.45)

    /// Default rank text color
    static let defaultRankTextColor = Color(red: 0.5, green: 0.5, blue: 0.55)

    // MARK: - Opacity Constants

    /// Subtle opacity (0.05) - for very light shadows
    static let subtleOpacity: Double = 0.05

    /// Light opacity (0.1) - for light backgrounds
    static let lightOpacity: Double = 0.1

    /// Medium opacity (0.15) - for medium shadows
    static let mediumOpacity: Double = 0.15

    /// Medium-high opacity (0.2) - for prominent backgrounds
    static let mediumHighOpacity: Double = 0.2

    /// Strong opacity (0.3) - for strong shadows
    static let strongOpacity: Double = 0.3

    /// Very strong opacity (0.4) - for very strong shadows
    static let veryStrongOpacity: Double = 0.4

    // MARK: - Shadow Colors

    /// Subtle shadow (black with 0.05 opacity)
    static let subtleShadowColor = Color.black.opacity(subtleOpacity)

    /// Medium shadow (blue with 0.15 opacity)
    static let mediumShadowColor = Color.blue.opacity(mediumOpacity)

    /// Strong shadow (black with 0.3 opacity)
    static let strongShadowColor = Color.black.opacity(strongOpacity)

    /// Depth shadow (purple with 0.2 opacity)
    static let depthShadowColor = Color.purple.opacity(mediumHighOpacity)

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

    // MARK: - Gradient Helper Functions

    /// Returns appropriate feedback gradient based on answer state
    static func feedbackGradient(
        isCorrect: Bool,
        isSelected: Bool,
        showFeedback: Bool,
        shouldShowAsCorrect: Bool = false
    ) -> LinearGradient {
        if showFeedback && isSelected {
            return isCorrect ? feedbackCorrectGradient : feedbackIncorrectGradient
        } else if shouldShowAsCorrect {
            return feedbackUnselectedCorrectGradient
        } else if isSelected {
            return feedbackSelectedGradient
        } else {
            return feedbackDefaultGradient
        }
    }

    /// Returns appropriate feedback border gradient based on answer state
    static func feedbackBorderGradient(
        isCorrect: Bool,
        isSelected: Bool,
        showFeedback: Bool
    ) -> LinearGradient? {
        if showFeedback && isSelected {
            return isCorrect ? borderCorrectGradient : borderIncorrectGradient
        } else if isSelected {
            return borderSelectedGradient
        }
        return nil
    }

    /// Returns gradient for a specific test type
    static func testTypeGradient(_ testType: TestType) -> LinearGradient {
        return testTypeGradients[testType] ?? primaryGradient
    }

    // MARK: - Onboarding Gradients

    /// Gradients for onboarding page backgrounds (8 pages total)
    static let onboardingBackgroundGradients: [LinearGradient] = [
        // Page 0: Learning Language (blue-cyan)
        LinearGradient(colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.white],
                      startPoint: .topLeading, endPoint: .bottomTrailing),
        // Page 1: Native Language (green-mint)
        LinearGradient(colors: [Color.green.opacity(0.3), Color.mint.opacity(0.2), Color.white],
                      startPoint: .topLeading, endPoint: .bottomTrailing),
        // Page 2: Test Prep (purple-pink)
        LinearGradient(colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.2), Color.white],
                      startPoint: .topLeading, endPoint: .bottomTrailing),
        // Page 3: Study Duration (orange-yellow)
        LinearGradient(colors: [Color.orange.opacity(0.3), Color.yellow.opacity(0.2), Color.white],
                      startPoint: .topLeading, endPoint: .bottomTrailing),
        // Page 4: Username (indigo-purple)
        LinearGradient(colors: [Color.indigo.opacity(0.3), Color.purple.opacity(0.2), Color.white],
                      startPoint: .topLeading, endPoint: .bottomTrailing),
        // Page 5: Schedule Preview (pink-red)
        LinearGradient(colors: [Color.pink.opacity(0.3), Color.red.opacity(0.2), Color.white],
                      startPoint: .topLeading, endPoint: .bottomTrailing),
        // Page 6: Declaration (purple-blue)
        LinearGradient(colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.2), Color.white],
                      startPoint: .topLeading, endPoint: .bottomTrailing),
        // Page 7: Search Word (teal-blue)
        LinearGradient(colors: [Color.teal.opacity(0.3), Color.blue.opacity(0.2), Color.white],
                      startPoint: .topLeading, endPoint: .bottomTrailing)
    ]

    /// Gradients for onboarding page elements (buttons, titles, etc.)
    static let onboardingPageGradients: [LinearGradient] = [
        // Page 0: Learning Language (blue-cyan)
        LinearGradient(colors: [Color.blue, Color.cyan],
                      startPoint: .leading, endPoint: .trailing),
        // Page 1: Native Language (green-mint)
        LinearGradient(colors: [Color.green, Color.mint],
                      startPoint: .leading, endPoint: .trailing),
        // Page 2: Test Prep (purple-pink)
        LinearGradient(colors: [Color.purple, Color.pink],
                      startPoint: .leading, endPoint: .trailing),
        // Page 3: Study Duration (orange-yellow)
        LinearGradient(colors: [Color.orange, Color.yellow],
                      startPoint: .leading, endPoint: .trailing),
        // Page 4: Username (indigo-purple)
        LinearGradient(colors: [Color.indigo, Color.purple],
                      startPoint: .leading, endPoint: .trailing),
        // Page 5: Schedule Preview (pink-red)
        LinearGradient(colors: [Color.pink, Color.red],
                      startPoint: .leading, endPoint: .trailing),
        // Page 6: Declaration (purple-blue)
        LinearGradient(colors: [Color.purple, Color.blue],
                      startPoint: .leading, endPoint: .trailing),
        // Page 7: Search Word (teal-blue)
        LinearGradient(colors: [Color.teal, Color.blue],
                      startPoint: .leading, endPoint: .trailing)
    ]
}
