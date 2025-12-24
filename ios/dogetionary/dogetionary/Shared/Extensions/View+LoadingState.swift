//
//  View+LoadingState.swift
//  dogetionary
//
//  Reusable loading and error state management for views
//

import SwiftUI

/// View modifier that manages loading and error states with consistent UI
struct LoadingStateModifier: ViewModifier {
    let isLoading: Bool
    let errorMessage: String?
    let onErrorDismiss: () -> Void

    func body(content: Content) -> some View {
        ZStack {
            content

            // Loading overlay
            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: AppTheme.spacingM) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(AppTheme.accentCyan)

                    Text("LOADING...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.smallTitleText)
                }
                .padding(AppTheme.spacingL)
                .background(AppTheme.bgPrimary)
                .cornerRadius(AppTheme.cornerRadiusL)
            }
        }
        .errorToast(message: errorMessage, onDismiss: onErrorDismiss)
    }
}

extension View {
    /// Apply loading and error state management to any view
    /// - Parameters:
    ///   - isLoading: Whether the view is in loading state
    ///   - errorMessage: Optional error message to display
    ///   - onErrorDismiss: Callback when error is dismissed
    func loadingState(
        isLoading: Bool,
        errorMessage: String?,
        onErrorDismiss: @escaping () -> Void
    ) -> some View {
        self.modifier(LoadingStateModifier(
            isLoading: isLoading,
            errorMessage: errorMessage,
            onErrorDismiss: onErrorDismiss
        ))
    }
}

// MARK: - Preview

#Preview("Loading State") {
    VStack(spacing: 20) {
        Text("Content behind loading overlay")
            .font(.title)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppTheme.verticalGradient2)
    .loadingState(
        isLoading: true,
        errorMessage: nil,
        onErrorDismiss: {}
    )
}

#Preview("Error State") {
    @Previewable @State var errorMessage: String? = "Failed to load data"

    VStack(spacing: 20) {
        Text("Content with error")
            .font(.title)

        Button("Trigger Error") {
            errorMessage = "Network connection failed"
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppTheme.verticalGradient2)
    .loadingState(
        isLoading: false,
        errorMessage: errorMessage,
        onErrorDismiss: { errorMessage = nil }
    )
}
