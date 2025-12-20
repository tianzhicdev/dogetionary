//
//  DailyProgressBanner.swift
//  dogetionary
//
//  App-wide daily progress banner showing streak and review progress
//

import SwiftUI

struct DailyProgressBanner: View {
    let testType: String  // "TOEFL_ADVANCED", "NONE", etc.
    let streakDays: Int
    let reviewsPast24h: Int
    let dailyTarget: Int
    let bundleProgress: BundleProgress?  // Overall bundle completion
    @Binding var isExpanded: Bool

    @State private var animatedProgress: Double = 0.0
    @State private var isAnimatingScale: Bool = false

    // Badge metadata for test type display names
    private let testTypeNames: [String: String] = [
        "TOEFL_BEGINNER": "TOEFL Beginner",
        "TOEFL_INTERMEDIATE": "TOEFL Intermediate",
        "TOEFL_ADVANCED": "TOEFL Advanced",
        "IELTS_BEGINNER": "IELTS Beginner",
        "IELTS_INTERMEDIATE": "IELTS Intermediate",
        "IELTS_ADVANCED": "IELTS Advanced",
        "DEMO": "Demo",
        "BUSINESS_ENGLISH": "Business",
        "EVERYDAY_ENGLISH": "Everyday",
        "NONE": "Score Progress"
    ]

    var body: some View {
        
        VStack(alignment: .leading, spacing: isExpanded ? 16 : 8) {
            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
//        .background(AppTheme.panelFill.opacity(0.3))
        .cornerRadius(12)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animatedProgress = barProgress
            }
        }
        .onChange(of: barProgress) { _, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedProgress = newValue
            }
        }
        .onChange(of: reviewsPast24h) { oldValue, newValue in
            // Only animate if value increased (new review completed)
            print("🎯 DailyProgressBanner: reviewsPast24h changed from \(oldValue) to \(newValue)")
            if newValue > oldValue {
                print("✨ DailyProgressBanner: Triggering scale animation!")
                // Trigger scale animation
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    isAnimatingScale = true
                }

                // Haptic feedback for satisfying user experience
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()

                // Reset after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isAnimatingScale = false
                    }
                }
            }
        }
    }

    // MARK: - Collapsed State

    private var collapsedContent: some View {
        HStack(spacing: 6) {
            // Bundle name
            Text(displayTestTypeName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.bodyText)
                .lineLimit(1)

            Text("/")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.smallTextColor1)

            // Streak
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.electricYellow)
                Text("\(streakDays)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(AppTheme.electricYellow)
            }

            Text("/")
                .font(.system(size: 11))
                .foregroundColor(AppTheme.smallTextColor1)

            // Daily progress percentage
            HStack(spacing: 3) {
                Text("TODAY:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.smallTitleText)
                Text("\(displayPercentage)%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(percentageColor)
                    .scaleEffect(isAnimatingScale ? 1.2 : 1.0)
            }

            Spacer()

            // Expand button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }) {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.selectableTint)
            }
        }
    }

    // MARK: - Expanded State

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Bundle name
                Text(displayTestTypeName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.bodyText)

                Spacer()

                // Percentage
                Text("\(displayPercentage)%")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.bodyText)

                // Collapse button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.selectableTint)
                }
            }

            // Progress bar
            progressBar

            // Stats row
            HStack(spacing: 24) {
                // Streak
                VStack(alignment: .leading, spacing: 4) {
                    Text("STREAK")
                        .font(.caption)
                        .foregroundColor(AppTheme.smallTitleText)
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(AppTheme.electricYellow)
                            .font(.system(size: 16))
                        Text("\(streakDays)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.electricYellow)
                    }
                }

                Spacer()

                // Daily progress
                VStack(alignment: .trailing, spacing: 4) {
                    Text("DAILY")
                        .font(.caption)
                        .foregroundColor(AppTheme.smallTitleText)
                    HStack(spacing: 2) {
                        Text("\(reviewsPast24h)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.accentCyan)
                        Text("/")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.smallTextColor1)
                        Text("\(dailyTarget)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppTheme.bodyText)
                    }
                }
            }

            // Bundle progress (if available)
            if let progress = bundleProgress {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BUNDLE")
                        .font(.caption)
                        .foregroundColor(AppTheme.smallTitleText)
                    HStack(spacing: 4) {
                        Text("\(progress.saved_words)/\(progress.total_words)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.accentCyan)
                        Text("(\(progress.percentage)%)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.smallTextColor1)
                    }
                }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            // Background track
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.panelFill)
                .frame(height: 20)

            // Animated progress fill with gradient
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * animatedProgress, height: 20)
            }
            .frame(height: 20)
        }
    }

    // MARK: - Computed Properties

    private var displayTestTypeName: String {
        testTypeNames[testType] ?? "Score Progress"
    }

    private var displayProgress: Double {
        guard dailyTarget > 0 else { return 0 }
        return Double(reviewsPast24h) / Double(dailyTarget)
    }

    private var displayPercentage: Int {
        Int(displayProgress * 100)
    }

    private var barProgress: Double {
        min(displayProgress, 1.0)  // Cap visual bar at 100%
    }

    private var percentageColor: Color {
        if displayProgress >= 1.0 {
            return AppTheme.successColor
        } else if displayProgress >= 0.5 {
            return AppTheme.accentCyan
        } else {
            return AppTheme.accentPink
        }
    }

    private var gradientColors: [Color] {
        if displayProgress >= 1.0 {
            return [AppTheme.successColor, AppTheme.accentCyan]
        } else {
            return [AppTheme.accentCyan, AppTheme.neonPurple]
        }
    }
}

// MARK: - Preview

#Preview("Daily Progress Banner") {
    VStack(spacing: 20) {
        // Collapsed - low progress
        DailyProgressBanner(
            testType: "TOEFL_ADVANCED",
            streakDays: 5,
            reviewsPast24h: 15,
            dailyTarget: 60,
            bundleProgress: BundleProgress(saved_words: 234, total_words: 1500, percentage: 15),
            isExpanded: .constant(false)
        )

        // Expanded - good progress
        DailyProgressBanner(
            testType: "IELTS_INTERMEDIATE",
            streakDays: 12,
            reviewsPast24h: 45,
            dailyTarget: 60,
            bundleProgress: BundleProgress(saved_words: 680, total_words: 1200, percentage: 56),
            isExpanded: .constant(true)
        )

        // Expanded - over 100%
        DailyProgressBanner(
            testType: "DEMO",
            streakDays: 30,
            reviewsPast24h: 90,
            dailyTarget: 60,
            bundleProgress: nil,
            isExpanded: .constant(true)
        )
    }
    .padding()
    .background(AppTheme.verticalGradient2)
}
