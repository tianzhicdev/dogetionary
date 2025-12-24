//
//  AppButtonStyles.swift
//  dogetionary
//
//  Reusable button styles for consistent UI across the app
//

import SwiftUI

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacingM)
            .background(
                isDisabled
                    ? AppTheme.smallTextColor1.opacity(0.3)
                    : (configuration.isPressed
                        ? AppTheme.selectableTint.opacity(0.7)
                        : AppTheme.selectableTint)
            )
            .cornerRadius(AppTheme.cornerRadiusM)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Secondary Button Style

struct SecondaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(AppTheme.selectableTint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacingM)
            .background(
                isDisabled
                    ? AppTheme.panelFill.opacity(0.3)
                    : (configuration.isPressed
                        ? AppTheme.panelFill.opacity(0.7)
                        : AppTheme.panelFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusM)
                    .stroke(AppTheme.selectableTint, lineWidth: 1.5)
            )
            .cornerRadius(AppTheme.cornerRadiusM)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - View Extension for Easy Usage

extension View {
    func primaryButtonStyle(isDisabled: Bool = false) -> some View {
        self.buttonStyle(PrimaryButtonStyle(isDisabled: isDisabled))
    }

    func secondaryButtonStyle(isDisabled: Bool = false) -> some View {
        self.buttonStyle(SecondaryButtonStyle(isDisabled: isDisabled))
    }
}

// MARK: - Preview

#Preview("Button Styles") {
    VStack(spacing: 20) {
        Button("Primary Button") {}
            .primaryButtonStyle()

        Button("Primary Disabled") {}
            .primaryButtonStyle(isDisabled: true)

        Button("Secondary Button") {}
            .secondaryButtonStyle()
    }
    .padding()
    .background(AppTheme.verticalGradient2)
}
