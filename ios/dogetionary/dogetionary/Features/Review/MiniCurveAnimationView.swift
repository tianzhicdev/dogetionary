//
//  MiniCurveAnimationView.swift
//  dogetionary
//
//  Compact brain animation that appears in status bar after answering questions
//

import SwiftUI

struct MiniCurveAnimationView: View {
    let isCorrect: Bool
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 4) {
            // Trend arrow
            Image(systemName: isCorrect ? "arrow.up" : "arrow.down")
                .font(.system(size: 11, weight: .bold))

            // Brain symbol
            Image(systemName: "brain")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(isCorrect ? AppTheme.successColor : AppTheme.warningColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill((isCorrect ? AppTheme.successColor : AppTheme.warningColor).opacity(AppTheme.lightOpacity))
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // Pop in
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            scale = 1.0
            opacity = 1.0
        }

        // Hold for 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Fade out
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 0
                scale = 0.8
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onDismiss()
            }
        }
    }
}

#Preview {
    HStack(spacing: 8) {
        // Correct answer preview
        MiniCurveAnimationView(
            isCorrect: true,
            onDismiss: {}
        )

        // Incorrect answer preview
        MiniCurveAnimationView(
            isCorrect: false,
            onDismiss: {}
        )
    }
    .padding()
}
