//
//  DailyGoalCelebrationView.swift
//  dogetionary
//
//  Simple celebration overlay when user reaches 100% daily goal
//

import SwiftUI
import AudioToolbox

struct DailyGoalCelebrationView: View {
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Celebration content
            VStack(spacing: 16) {
                Text("🎉")
                    .font(.system(size: 80))

                Text("100%")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(AppTheme.successColor)

                Text("Daily Goal Complete!")
                    .font(.title2)
                    .foregroundColor(AppTheme.bigTitleText)
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
            // Play celebration sound
            AudioServicesPlaySystemSound(1025)  // Fanfare
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Animate in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }

            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                dismiss()
            }
        }
    }

    private func dismiss() {
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

#Preview("Daily Goal Celebration") {
    @Previewable @State var showCelebration = true

    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        if showCelebration {
            DailyGoalCelebrationView {
                showCelebration = false
            }
        }
    }
}
