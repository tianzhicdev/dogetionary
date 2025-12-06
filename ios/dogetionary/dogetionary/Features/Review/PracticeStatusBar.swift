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
                // Simple summary: NEW 6 / PRACTICE 5 / DUE SOON 20
                if let status = practiceStatus {
                    let practiceCount = status.test_practice_count + status.non_test_practice_count

                    HStack(spacing: 6) {
                        Text("NEW")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.smallTitleText)
                        Text("\(status.new_words_count)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.bodyText)

                        Text("/")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.bodyText)

                        Text("PRACTICE")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.smallTitleText)
                        Text("\(practiceCount)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.bodyText)

                        Text("/")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.bodyText)

                        Text("DUE SOON")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.smallTitleText)
                        Text("\(status.not_due_yet_count)")
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
        new_words_count: 12,
        test_practice_count: 8,
        non_test_practice_count: 5,
        not_due_yet_count: 23,
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
