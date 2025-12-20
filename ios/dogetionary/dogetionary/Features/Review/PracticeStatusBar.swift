//
//  PracticeStatusBar.swift
//  dogetionary
//
//  Created by Claude Code on 12/5/25.
//

import SwiftUI

struct PracticeStatusBar: View {
    let practiceStatus: PracticeStatusResponse?
    let score: Int
    let scoreAnimationScale: CGFloat
    let scoreAnimationColor: Color
    let showMiniCurve: Bool
    let curveIsCorrect: Bool
    let onCurveDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            HStack {
                // Simple summary: PRACTICE 5 / LAST 24H 3 / TOTAL 87
                if let status = practiceStatus {
                    HStack(spacing: 6) {
                        Text("PRACTICE")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.smallTitleText)
                        Text("\(status.due_word_count)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.bodyText)

                        Text("/")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.bodyText)

                        Text("LAST 24H")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.smallTitleText)
                        Text("\(status.new_word_count_past_24h)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.bodyText)

                        Text("/")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.bodyText)

                        Text("TOTAL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.smallTitleText)
                        Text("\(status.total_word_count)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.bodyText)
                    }
                }

                Spacer()

                // Score with AnimatedScoreStar
                HStack(spacing: -10) {
                    Text("\(score)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.bodyText)
                        .scaleEffect(scoreAnimationScale)
                    AnimatedScoreStar(size: 40)
                }
            }

            // Mini curve animation (floating at the top)
            if showMiniCurve {
                MiniCurveAnimationView(
                    isCorrect: curveIsCorrect,
                    onDismiss: onCurveDismiss
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

// MARK: - Preview

#Preview("Practice Status Bar") {
    let sampleStatus = PracticeStatusResponse(
        user_id: "preview-user",
        due_word_count: 5,
        new_word_count_past_24h: 3,
        total_word_count: 87,
        score: 450,
        has_practice: true
    )

    VStack(spacing: 20) {
        // Without mini curve
        PracticeStatusBar(
            practiceStatus: sampleStatus,
            score: 450,
            scoreAnimationScale: 1.0,
            scoreAnimationColor: AppTheme.accentCyan,
            showMiniCurve: false,
            curveIsCorrect: true,
            onCurveDismiss: { }
        )
        .padding()
        .background(AppTheme.panelFill)

        // With mini curve (correct)
        PracticeStatusBar(
            practiceStatus: sampleStatus,
            score: 450,
            scoreAnimationScale: 1.2,
            scoreAnimationColor: AppTheme.successColor,
            showMiniCurve: true,
            curveIsCorrect: true,
            onCurveDismiss: { }
        )
        .padding()
        .background(AppTheme.panelFill)
    }
    .padding()
    .background(AppTheme.verticalGradient2)
}
