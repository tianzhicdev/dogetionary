//
//  ThemeConstants.swift
//  dogetionary
//
//  App-wide theme constants for consistent styling
//  Based on ScheduleView design system
//

import SwiftUI


struct AppTheme {
    
    // approved colors
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let silver = Color(red: 0.75, green: 0.75, blue: 0.77)
    static let bronze = Color(red: 0.80, green: 0.50, blue: 0.20)
    static let shinyGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 1.0, blue: 0.85),   // warm white
            Color(red: 1.0, green: 0.95, blue: 0.4),   // bright yellow
            Color(red: 1.0, green: 1.0, blue: 0.9),    // highlight
            Color(red: 1.0, green: 0.92, blue: 0.3),   // yellow
            Color(red: 1.0, green: 1.0, blue: 0.85)    // warm white
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    
    static let bgPrimary = Color(red: 0.05, green: 0.08, blue: 0.13)       // #0D1520
     
     // Panel Fill
     static let panelFill = Color(red: 0.10, green: 0.23, blue: 0.29)       // #1A3A4A
     
     // Cyan Accent
     static let accentCyan = Color(red: 0.0, green: 0.81, blue: 1.0)        // #00CFFF
     
     // Pink Accent
     static let accentPink = Color(red: 1.0, green: 0.0, blue: 0.67)        // #FF00AA
//    
    // Accents
    static let neonPurple = Color(red: 0.62, green: 0.0, blue: 1.0)       // #9D00FF
    static let electricYellow = Color(red: 0.94, green: 1.0, blue: 0.0)
    


    
    static let verticalGradient2 = LinearGradient(
        colors: [bgPrimary, Color(red: 0.09, green: 0.13, blue: 0.24)],
        startPoint: .center,
        endPoint: .bottomTrailing
    )
    
    static let gradient1 = LinearGradient(colors: [accentCyan, accentCyan], startPoint: .leading, endPoint: .trailing)
    
    
    
    static let bigTitleText = accentCyan
    static let smallTextColor1 = electricYellow
    static let smallTitleText = electricYellow
    static let bodyText = accentCyan
    static let textFieldBorderColor = accentCyan
    static let textFieldUserInput = accentCyan
    static let textFieldBackgroundColor = Color.black
    static let selectableTint = accentPink
    static let bigButtonBackground1 = accentCyan
    static let bigButtonForeground1 = white
    
    static let buttonBackground1 = accentPink
    static let buttonForeground1 = white
    
    // end approved colors
    
    
    
    
    // MARK: - Basic Colors

    static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.4, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.4, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
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
    
    
    static let systemText = Color(red: 0.3, green: 0.4, blue: 0.9)

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



    // MARK: - Onboarding Gradients

    /// Onboarding page title/button gradients (one per page)
    /// These use system color aliases for consistent theming
    static let onboardingPageGradients: [LinearGradient] = [
        // Page 0 - Learning Language Selection (Blue/Cyan)
        LinearGradient(
            colors: [systemBlue, systemCyan],
            startPoint: .leading,
            endPoint: .trailing
        ),
        // Page 1 - Native Language Selection (Green/Mint)
        LinearGradient(
            colors: [systemGreen, systemMint],
            startPoint: .leading,
            endPoint: .trailing
        ),
        // Page 2 - Test Preparation (Purple/Pink)
        LinearGradient(
            colors: [systemPurple, systemPink],
            startPoint: .leading,
            endPoint: .trailing
        ),
        // Page 3 - Study Duration (Orange/Yellow)
        LinearGradient(
            colors: [systemOrange, systemYellow],
            startPoint: .leading,
            endPoint: .trailing
        ),
        // Page 4 - Username Entry (Indigo/Purple)
        LinearGradient(
            colors: [systemIndigo, systemPurple],
            startPoint: .leading,
            endPoint: .trailing
        ),
        // Page 5 - Schedule Preview (Pink/Red)
        LinearGradient(
            colors: [systemPink, systemRed],
            startPoint: .leading,
            endPoint: .trailing
        ),
        // Page 6 - Declaration (Purple/Blue)
        LinearGradient(
            colors: [systemPurple, systemBlue],
            startPoint: .leading,
            endPoint: .trailing
        ),
        // Page 7 - Search Word (Teal/Blue)
        LinearGradient(
            colors: [systemTeal, systemBlue],
            startPoint: .leading,
            endPoint: .trailing
        )
    ]

    /// Onboarding page background gradients (one per page)
    /// These use system color aliases for consistent theming
    static let onboardingBackgroundGradients: [LinearGradient] = [
        // Page 0 - Learning Language (Blue/Cyan background)
        LinearGradient(
            colors: [systemBlue.opacity(0.3), systemCyan.opacity(0.2), white],
            startPoint: .top,
            endPoint: .bottom
        ),
        // Page 1 - Native Language (Green/Mint background)
        LinearGradient(
            colors: [systemGreen.opacity(0.3), systemMint.opacity(0.2), white],
            startPoint: .top,
            endPoint: .bottom
        ),
        // Page 2 - Test Preparation (Purple/Pink background)
        LinearGradient(
            colors: [systemPurple.opacity(0.3), systemPink.opacity(0.2), white],
            startPoint: .top,
            endPoint: .bottom
        ),
        // Page 3 - Study Duration (Orange/Yellow background)
        LinearGradient(
            colors: [systemOrange.opacity(0.3), systemYellow.opacity(0.2), white],
            startPoint: .top,
            endPoint: .bottom
        ),
        // Page 4 - Username Entry (Indigo/Purple background)
        LinearGradient(
            colors: [systemIndigo.opacity(0.3), systemPurple.opacity(0.2), white],
            startPoint: .top,
            endPoint: .bottom
        ),
        // Page 5 - Schedule Preview (Pink/Red background)
        LinearGradient(
            colors: [systemPink.opacity(0.3), systemRed.opacity(0.2), white],
            startPoint: .top,
            endPoint: .bottom
        ),
        // Page 6 - Declaration (Purple/Blue background)
        LinearGradient(
            colors: [systemPurple.opacity(0.3), systemBlue.opacity(0.2), white],
            startPoint: .top,
            endPoint: .bottom
        ),
        // Page 7 - Search Word (Teal/Blue background)
        LinearGradient(
            colors: [systemTeal.opacity(0.3), systemBlue.opacity(0.2), white],
            startPoint: .top,
            endPoint: .bottom
        )
    ]

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

    /// Gradients for test types using system color aliases
    static let testTypeGradients: [TestType: LinearGradient] = [
        .toeflBeginner: LinearGradient(
            colors: [systemGreen, systemMint],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .toeflIntermediate: LinearGradient(
            colors: [systemTeal, systemCyan],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .toeflAdvanced: LinearGradient(
            colors: [systemBlue, systemPurple],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .ieltsBeginner: LinearGradient(
            colors: [systemOrange, systemYellow],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .ieltsIntermediate: LinearGradient(
            colors: [systemPink, systemRed],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .ieltsAdvanced: LinearGradient(
            colors: [systemPurple, systemIndigo],
            startPoint: .leading,
            endPoint: .trailing
        ),
        .tianz: LinearGradient(
            colors: [systemIndigo, systemPurple],
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

    // MARK: - Basic Colors (Semantic Wrappers)


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
    
    
    static let bronzeTextColor = white

    /// Default rank text color
    static let defaultRankTextColor = Color(red: 0.5, green: 0.5, blue: 0.55)

    // MARK: - Leaderboard Colors

    struct Leaderboard {
        /// Text color for user names in leaderboard
        static let currentUserNameTextColor = Color.primary
        static let userNameTextColor = Color.primary
        static let scoreTextColor = Color.primary
        
        static let rowBackgroundColor = Color.white
        
        
        struct you {
            static let foreground = Color.primary
            static let background = Color.secondary
        }
        
    }

    /// Leaderboard colors namespace
    static let leaderboard = Leaderboard.self

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

    // MARK: - Corner Radius Scale

    /// No corner radius (sharp corners)
    static let cornerRadiusNone: CGFloat = 0

    /// Extra small corner radius (micro elements, decorative accents)
    static let cornerRadiusXS: CGFloat = 4

    /// Small corner radius (badges, pills, compact elements)
    static let cornerRadiusS: CGFloat = 8

    /// Medium corner radius (text inputs, secondary cards)
    static let cornerRadiusM: CGFloat = 12

    /// Base/standard corner radius (primary buttons, cards) - THE DEFAULT
    static let cornerRadiusBase: CGFloat = 16

    /// Large corner radius (prominent containers)
    static let cornerRadiusL: CGFloat = 20

    /// Extra large corner radius (circular/pill-shaped elements)
    static let cornerRadiusXL: CGFloat = 24

    /// Maximum corner radius (perfect circles when width == height)
    static let cornerRadiusCircle: CGFloat = 50

    // MARK: - Spacing Scale

    /// Extra small spacing (4pt) - tight spacing, micro gaps
    static let spacingXS: CGFloat = 4

    /// Small spacing (8pt) - compact layouts
    static let spacingS: CGFloat = 8

    /// Medium spacing (12pt) - comfortable spacing
    static let spacingM: CGFloat = 12

    /// Base/standard spacing (16pt) - THE DEFAULT
    static let spacingBase: CGFloat = 16

    /// Large spacing (20pt) - generous spacing
    static let spacingL: CGFloat = 20

    /// Extra large spacing (24pt) - prominent separation
    static let spacingXL: CGFloat = 24

    /// Extra extra large spacing (32pt) - major section breaks
    static let spacingXXL: CGFloat = 32

    // MARK: - Shadow Presets

    /// Subtle shadow - for small elements, minimal elevation
    static let shadowSubtle = (
        color: Color.black.opacity(0.05),
        radius: CGFloat(4),
        x: CGFloat(0),
        y: CGFloat(2)
    )

    /// Medium shadow - for buttons, cards, standard elevation
    static let shadowMedium = (
        color: Color.black.opacity(0.1),
        radius: CGFloat(8),
        x: CGFloat(0),
        y: CGFloat(4)
    )

    /// Strong shadow - for interactive elements, prominent elevation
    static let shadowStrong = (
        color: Color.black.opacity(0.2),
        radius: CGFloat(10),
        x: CGFloat(0),
        y: CGFloat(5)
    )

    // MARK: - Border Width Scale

    /// Thin border (1pt) - subtle outlines
    static let borderWidthThin: CGFloat = 1

    /// Medium border (2pt) - standard borders
    static let borderWidthMedium: CGFloat = 2

    /// Thick border (3pt) - prominent outlines, selected states
    static let borderWidthThick: CGFloat = 3

    // MARK: - Card Styling

    static let cardBackground = Color.white
    static let cardCornerRadius: CGFloat = 16  // Alias for cornerRadiusBase
    static let cardPadding: CGFloat = 16
    static let cardShadowColor = Color.black.opacity(0.05)
    static let cardShadowRadius: CGFloat = 8
    static let cardSpacing: CGFloat = 16

    // MARK: - Badge Styling

    static let badgeCornerRadius: CGFloat = 6  // Alias for cornerRadiusS - 2
    static let badgeHorizontalPadding: CGFloat = 8
    static let badgeVerticalPadding: CGFloat = 4
    static let badgeOpacity: Double = 0.15

    // MARK: - Section Styling

    static let sectionCornerRadius: CGFloat = 10  // Custom value between S and M
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

    // MARK: - Button Styling

    /// Primary button - gradient background, prominent style
    static let primaryButtonCornerRadius: CGFloat = 16
    static let primaryButtonPaddingVertical: CGFloat = 16
    static let primaryButtonPaddingHorizontal: CGFloat = 24
    static let primaryButtonGradient = primaryGradient
    static let primaryButtonShadow = shadowStrong
    static let primaryButtonFont = Font.headline

    /// Secondary button - subtle background, softer style
    static let secondaryButtonCornerRadius: CGFloat = 16
    static let secondaryButtonBackground = lightBlue
    static let secondaryButtonShadow = shadowMedium
    static let secondaryButtonPaddingVertical: CGFloat = 12
    static let secondaryButtonPaddingHorizontal: CGFloat = 20
    static let secondaryButtonFont = Font.body

    /// Icon button (circular, like FAB)
    static let iconButtonSize: CGFloat = 56
    static let iconButtonCornerRadius: CGFloat = 28  // Half of size for perfect circle
    static let iconButtonShadow = shadowMedium
    static let iconButtonIconSize: CGFloat = 20

    /// Floating menu item styling
    static let menuItemCornerRadius: CGFloat = 24
    static let menuItemWidth: CGFloat = 200
    static let menuItemHeight: CGFloat = 48
    static let menuItemShadow = shadowSubtle
    static let menuItemPaddingHorizontal: CGFloat = 16
    static let menuItemPaddingVertical: CGFloat = 12

    /// Question option button (for review/practice)
    static let optionButtonCornerRadius: CGFloat = 16
    static let optionButtonBorderWidth: CGFloat = 3
    static let optionButtonShadow = shadowStrong
    static let optionButtonPadding: CGFloat = 16

    // MARK: - Empty State Styling

    static let emptyStateIconSize: CGFloat = 48
    static let emptyStateCircleSize: CGFloat = 100

    // MARK: - Debug Color Overrides (Developer Mode Only)

    /// Color overrides for live testing (only active when DebugConfig.showColorPlayground = true)
    /// These are persisted in UserDefaults to survive app restarts during theme experimentation
    private static let debugPrimaryColorKey = "debugPrimaryColor"
    private static let debugAccentColorKey = "debugAccentColor"
    private static let debugBackgroundColorKey = "debugBackgroundColor"

    /// Get primary color with optional debug override
    static func getPrimaryColor() -> Color {
        if DebugConfig.showColorPlayground, let colorData = UserDefaults.standard.data(forKey: debugPrimaryColorKey) {
            if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
                return Color(color)
            }
        }
        return primaryBlue
    }

    /// Get accent color with optional debug override
    static func getAccentColor() -> Color {
        if DebugConfig.showColorPlayground, let colorData = UserDefaults.standard.data(forKey: debugAccentColorKey) {
            if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
                return Color(color)
            }
        }
        return accentPurple
    }

    /// Get background color with optional debug override
    static func getBackgroundColor() -> Color {
        if DebugConfig.showColorPlayground, let colorData = UserDefaults.standard.data(forKey: debugBackgroundColorKey) {
            if let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: colorData) {
                return Color(color)
            }
        }
        return lightBlue
    }

    /// Save debug color override
    static func setDebugPrimaryColor(_ color: Color) {
        let uiColor = UIColor(color)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: debugPrimaryColorKey)
        }
    }

    /// Save debug accent color override
    static func setDebugAccentColor(_ color: Color) {
        let uiColor = UIColor(color)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: debugAccentColorKey)
        }
    }

    /// Save debug background color override
    static func setDebugBackgroundColor(_ color: Color) {
        let uiColor = UIColor(color)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: false) {
            UserDefaults.standard.set(data, forKey: debugBackgroundColorKey)
        }
    }

    /// Reset all debug color overrides to defaults
    static func resetDebugColors() {
        UserDefaults.standard.removeObject(forKey: debugPrimaryColorKey)
        UserDefaults.standard.removeObject(forKey: debugAccentColorKey)
        UserDefaults.standard.removeObject(forKey: debugBackgroundColorKey)
    }

    /// Export current color settings as Swift code (for copy-paste into ThemeConstants)
    static func exportDebugColorsAsCode() -> String {
        let primary = getPrimaryColor()
        let accent = getAccentColor()
        let background = getBackgroundColor()

        return """
        // Generated from Color Playground
        static let primaryBlue = Color(red: \(primary), green: \(primary), blue: \(primary))
        static let accentPurple = Color(red: \(accent), green: \(accent), blue: \(accent))
        static let lightBlue = Color(red: \(background), green: \(background), blue: \(background))
        """
    }

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
    
    struct smallBadge {
        static let cornerRadius: CGFloat = 2
    }
    
    struct motto {
        static let foreground = black
    }
    

}

struct ScoreStar: View {
    var body: some View {
        Image("score_star")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
    }
}
