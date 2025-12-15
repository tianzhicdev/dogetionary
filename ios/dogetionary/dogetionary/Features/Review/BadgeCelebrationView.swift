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
    @State private var iconScale: CGFloat = 0.5
    @State private var autoDismissTask: DispatchWorkItem?

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

                    // Badge PNG with scale animation
                    BadgeAnimation(badgeId: badge.badge_id, size: 140)
                        .scaleEffect(iconScale)
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

                // Description
                Text(badge.description)
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

            // Subtle icon scale animation
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5).delay(0.3)) {
                iconScale = 1.2
            }

            // Auto-dismiss after 3 seconds
            let task = DispatchWorkItem {
                dismissWithAnimation()
            }
            autoDismissTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: task)
        }
    }

    private func dismissWithAnimation() {
        // Cancel auto-dismiss timer to prevent double-dismissal
        autoDismissTask?.cancel()
        autoDismissTask = nil

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

#Preview("Badge Celebration - 100 Points") {
    @Previewable @State var showBadge = true

    if showBadge {
        BadgeCelebrationView(
            badge: NewBadge(
                badge_id: "score_100",
                title: "First Steps",
                description: "100 points reached"
            ),
            onDismiss: {
                showBadge = false
            }
        )
    }
}

#Preview("Badge Celebration - 500 Points") {
    @Previewable @State var showBadge = true

    if showBadge {
        BadgeCelebrationView(
            badge: NewBadge(
                badge_id: "score_500",
                title: "Dedicated Learner",
                description: "500 points reached"
            ),
            onDismiss: {
                showBadge = false
            }
        )
    }
}

#Preview("Badge Celebration - 1000 Points") {
    @Previewable @State var showBadge = true

    if showBadge {
        BadgeCelebrationView(
            badge: NewBadge(
                badge_id: "score_1000",
                title: "Vocabulary Master",
                description: "1000 points reached"
            ),
            onDismiss: {
                showBadge = false
            }
        )
    }
}

#Preview("Badge Celebration - TIANZ Test") {
    @Previewable @State var showBadge = true

    if showBadge {
        BadgeCelebrationView(
            badge: NewBadge(
                badge_id: "DEMO",
                title: "TIANZ Master",
                description: "TIANZ vocabulary completed!"
            ),
            onDismiss: {
                showBadge = false
            }
        )
    }
}
