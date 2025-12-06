//
//  BadgeCelebrationView.swift
//  dogetionary
//
//  Created by Claude Code on 12/5/25.
//

import SwiftUI

struct BadgeCelebrationView: View {
    let badge: NewBadge
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var iconRotation: Double = 0

    var body: some View {
        ZStack {
            // Semi-transparent background
            AppTheme.verticalGradient2
                .ignoresSafeArea()
                .onTapGesture {
                    dismissWithAnimation()
                }

            // Badge card
            VStack(spacing: 20) {
                // Badge icon with glow effect
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(AppTheme.bigTitleText.opacity(0.3))
                        .frame(width: 180, height: 180)
                        .blur(radius: 30)

                    // Badge PNG with rotation animation
                    BadgeAnimation(milestone: badge.milestone, size: 140)
                        .rotationEffect(.degrees(iconRotation))
                        .shadow(color: AppTheme.bigTitleText.opacity(0.5), radius: 15, x: 0, y: 8)
                }

                // Title
                Text("New Badge!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.bigTitleText)

                // Badge name
                Text(badge.title)
                    .font(.title)
                    .fontWeight(.heavy)
                    .foregroundColor(AppTheme.bigTitleText)

                // Milestone
                Text("\(badge.milestone) points reached")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.selectableTint)

                // Dismiss button
                Button(action: dismissWithAnimation) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(AppTheme.buttonForegroundCyan)
                        .frame(width: 150)
                        .padding(.vertical, 12)
                        .background(AppTheme.buttonBackgroundCyan)
                        .cornerRadius(25)
                }
                .padding(.top, 10)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.verticalGradient2.opacity(0.95))
                    
            )
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }

            // Subtle icon animation
            withAnimation(.easeInOut(duration: 0.5).delay(0.3)) {
                iconRotation = 360
            }

            // Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                dismissWithAnimation()
            }
        }
    }

    private var badgeColor: Color {
        switch badge.tier {
        case "beginner":
            return AppTheme.bronze
        case "intermediate":
            return AppTheme.silver
        case "advanced":
            return AppTheme.gold
        case "expert":
            return AppTheme.electricYellow
        default:
            return AppTheme.accentCyan
        }
    }

    private func dismissWithAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 0.8
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
}

// MARK: - Preview

#Preview("Badge Celebration - 100 Points (Bronze)") {
    @Previewable @State var showBadge = true

    if showBadge {
        BadgeCelebrationView(
            badge: NewBadge(
                milestone: 100,
                title: "First Steps",
                symbol: "star.fill",
                tier: "beginner",
                is_award: false
            ),
            onDismiss: {
                showBadge = false
            }
        )
    }
}

#Preview("Badge Celebration - 500 Points (Silver)") {
    @Previewable @State var showBadge = true

    if showBadge {
        BadgeCelebrationView(
            badge: NewBadge(
                milestone: 500,
                title: "Dedicated Learner",
                symbol: "sparkles",
                tier: "intermediate",
                is_award: false
            ),
            onDismiss: {
                showBadge = false
            }
        )
    }
}

#Preview("Badge Celebration - 1000 Points (Gold)") {
    @Previewable @State var showBadge = true

    if showBadge {
        BadgeCelebrationView(
            badge: NewBadge(
                milestone: 1000,
                title: "Vocabulary Master",
                symbol: "crown.fill",
                tier: "advanced",
                is_award: false
            ),
            onDismiss: {
                showBadge = false
            }
        )
    }
}

#Preview("Badge Celebration - 5000 Points (Expert)") {
    @Previewable @State var showBadge = true

    if showBadge {
        BadgeCelebrationView(
            badge: NewBadge(
                milestone: 5000,
                title: "Language Virtuoso",
                symbol: "flame.fill",
                tier: "expert",
                is_award: false
            ),
            onDismiss: {
                showBadge = false
            }
        )
    }
}
