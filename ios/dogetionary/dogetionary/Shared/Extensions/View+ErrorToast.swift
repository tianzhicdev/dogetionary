//
//  View+ErrorToast.swift
//  dogetionary
//
//  Auto-dismissing error toast component
//  Displays errors for 5 seconds with slide-in/out animations
//

import SwiftUI

extension View {
    /// Displays an auto-dismissing error toast at the top of the view
    /// - Parameters:
    ///   - message: Optional error message to display
    ///   - onDismiss: Callback invoked when toast dismisses (after 5 seconds or manually)
    /// - Returns: Modified view with error toast overlay
    func errorToast(message: String?, onDismiss: @escaping () -> Void) -> some View {
        self.modifier(ErrorToastModifier(message: message, onDismiss: onDismiss))
    }
}

/// ViewModifier that displays a slide-in error toast with 5-second auto-dismiss
struct ErrorToastModifier: ViewModifier {
    let message: String?
    let onDismiss: () -> Void

    @State private var offset: CGFloat = -100
    @State private var opacity: Double = 0
    @State private var autoDismissTask: DispatchWorkItem?

    private let displayDuration: TimeInterval = 5.0  // 5 seconds as specified
    private let animationInDuration: TimeInterval = 0.4
    private let animationOutDuration: TimeInterval = 0.3

    /// Sanitizes error messages to hide technical details from users
    /// - Parameter rawError: The raw error message from backend/system
    /// - Returns: User-friendly error message
    private func sanitizeErrorMessage(_ rawError: String) -> String {
        // List of patterns that indicate technical/server errors
        let technicalErrorPatterns = [
            "Failed to",
            "Error:",
            "Exception",
            "Internal server error",
            "Network error",
            "decode",
            "encode",
            "nil",
            "Optional",
            "localizedDescription"
        ]

        // Check if error contains technical details
        let containsTechnicalDetails = technicalErrorPatterns.contains { pattern in
            rawError.lowercased().contains(pattern.lowercased())
        }

        if containsTechnicalDetails {
            return "Server error"
        }

        // For specific known user-friendly errors, pass through
        let userFriendlyErrors = [
            "No definition found",
            "Word not found",
            "Network connection failed",
            "Connection failed"
        ]

        let isUserFriendly = userFriendlyErrors.contains { friendly in
            rawError.lowercased().contains(friendly.lowercased())
        }

        if isUserFriendly {
            return rawError
        }

        // Default: generic message
        return "Server error"
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let message = message {
                errorBanner(message: message)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: AppTheme.spacingM) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.selectableTint)

            Text(sanitizeErrorMessage(message).uppercased())
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.smallTitleText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppTheme.spacingBase)
        .padding(.vertical, AppTheme.spacingM)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusM)
                .fill(AppTheme.bgPrimary)
                .shadow(
                    color: AppTheme.selectableTint.opacity(0.3),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
        .padding(.horizontal, AppTheme.spacingBase)
        .padding(.top, AppTheme.spacingS)
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            slideIn()
        }
        .onDisappear {
            // Cancel any pending dismissal when view disappears
            autoDismissTask?.cancel()
            autoDismissTask = nil
        }
    }

    private func slideIn() {
        // Slide in from top with spring animation
        withAnimation(.spring(response: animationInDuration, dampingFraction: 0.7)) {
            offset = 0
            opacity = 1
        }

        // Cancel any existing auto-dismiss task
        autoDismissTask?.cancel()

        // Schedule auto-dismiss after 5 seconds
        let task = DispatchWorkItem {
            self.slideOut()
        }
        autoDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: task)
    }

    private func slideOut() {
        // Cancel any pending dismissal
        autoDismissTask?.cancel()
        autoDismissTask = nil

        // Slide out to top with ease-out animation
        withAnimation(.easeOut(duration: animationOutDuration)) {
            offset = -100
            opacity = 0
        }

        // Trigger callback after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + animationOutDuration) {
            onDismiss()
        }
    }
}

// MARK: - Preview

#Preview("Error Toast") {
    struct ErrorToastPreview: View {
        @State private var errorMessage: String? = nil

        var body: some View {
            VStack(spacing: 20) {
                Text("Error Toast Demo")
                    .font(.title)
                    .padding()

                Button("Show Error") {
                    errorMessage = "Network connection failed. Please try again."
                }
                .padding()
                .background(AppTheme.accentCyan)
                .foregroundColor(AppTheme.bgPrimary)
                .cornerRadius(8)

                Button("Show Long Error") {
                    errorMessage = "An unexpected error occurred while processing your request. Please check your connection."
                }
                .padding()
                .background(AppTheme.selectableTint)
                .foregroundColor(AppTheme.bgPrimary)
                .cornerRadius(8)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.bgPrimary)
            .errorToast(message: errorMessage) {
                errorMessage = nil
            }
        }
    }

    return ErrorToastPreview()
}
