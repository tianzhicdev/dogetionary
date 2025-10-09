//
//  OnboardingOverlayView.swift
//  dogetionary
//
//  Created by Claude on 10/8/25.
//

import SwiftUI

struct OnboardingOverlayView: View {
    @ObservedObject var manager: OnboardingManager

    var body: some View {
        ZStack {
            // Centered card
            VStack(spacing: 24) {
                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 64))
                    .foregroundColor(.accentColor)

                // Title
                Text(manager.currentStep.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                // Message
                Text(manager.currentStep.message)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            manager.advanceToNextStep()
                        }
                    }) {
                        Text(manager.currentStep.buttonText)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            manager.skipOnboarding()
                        }
                    }) {
                        Text("Skip Tutorial")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 340)
            .background(Color(uiColor: .systemBackground))
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 15)
            .padding(.horizontal, 20)
        }
    }

    private var iconName: String {
        switch manager.currentStep {
        case .dictionary:
            return "magnifyingglass.circle.fill"
        case .savedWords:
            return "bookmark.fill"
        case .review:
            return "brain.head.profile"
        case .leaderboard:
            return "trophy.fill"
        case .settings:
            return "gear"
        }
    }
}

#Preview {
    OnboardingOverlayView(manager: OnboardingManager.shared)
}
