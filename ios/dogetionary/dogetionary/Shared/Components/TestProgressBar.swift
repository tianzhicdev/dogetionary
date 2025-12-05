//
//  TestProgressBar.swift
//  dogetionary
//
//  Created by Claude Code on 11/18/25.
//

import SwiftUI

struct TestProgressBar: View {
    let progress: Double // 0.0 to 1.0
    let totalWords: Int
    let savedWords: Int
    let testType: String
    let streakDays: Int  // Streak days
    let achievementProgress: AchievementProgressResponse?  // Optional achievements
    let testVocabularyAwards: TestVocabularyAwardsResponse?  // Optional test vocabulary awards
    @Binding var isExpanded: Bool  // Binding to track expansion state

    @State private var animatedProgress: Double = 0.0

    // Badge metadata - map test names to user-friendly titles and SF Symbols
    private let badgeMetadata: [String: (title: String, symbol: String)] = [
        "TOEFL_BEGINNER": ("TOEFL Beginner", "graduationcap.fill"),
        "TOEFL_INTERMEDIATE": ("TOEFL Intermediate", "graduationcap.circle.fill"),
        "TOEFL_ADVANCED": ("TOEFL Advanced", "brain.head.profile"),
        "IELTS_BEGINNER": ("IELTS Beginner", "graduationcap.fill"),
        "IELTS_INTERMEDIATE": ("IELTS Intermediate", "graduationcap.circle.fill"),
        "IELTS_ADVANCED": ("IELTS Advanced", "brain.head.profile"),
        "TIANZ": ("Tianz", "star.circle.fill")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with test type badge and details toggle
            HStack {
                // Progress mode badge
                HStack(spacing: 4) {
                    Image(systemName: badgeIcon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(badgeText)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(AppTheme.bodyText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
//                .background(
//                    Capsule()
//                        .fill(gradientForTestType)
//                )

                Spacer()

                // Progress percentage
                Text("\(Int(displayProgress * 100))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.bodyText)

                // Expand/collapse button
                Button(action: {
                    withAnimation(.spring(response: AppConstants.Animation.springResponse, dampingFraction: AppConstants.Animation.springDamping)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.selectableTint)
                }
            }

            // Progress bar
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

            // Detailed stats (expandable)
            if isExpanded {
                VStack(spacing: 8) {
                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("REMAINING")
                                .font(.caption)
                                .foregroundColor(AppTheme.smallTitleText)
                            HStack(spacing: 2) {
                                Text("\(displayRemaining)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.accentPink)
                            }
                        }

                        Spacer()

                        VStack(alignment: .center, spacing: 4) {
                            Text("STREAK")
                                .font(.caption)
                                .foregroundColor(AppTheme.smallTitleText)
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(AppTheme.electricYellow)
                                    .font(.system(size: 14))
                                Text("\(streakDays)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.electricYellow)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(isTestMode ? "COMPLETED" : "SCORE")
                                .font(.caption)
                                .foregroundColor(AppTheme.smallTitleText)
                            HStack(spacing: 2) {
                                Text("\(displayCurrent)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppTheme.accentCyan)
                            }
                        }
                    }

                    // Achievements section - combines score-based and test-completion badges
                    if let achievements = achievementProgress {
                        // Filter for only unlocked achievements
                        let unlockedAchievements = achievements.achievements.filter { $0.unlocked }

                        // Get earned test completion badges
                        let earnedTestBadges = testVocabularyAwards?.filter { $0.value.isEarned }.sorted(by: { $0.key < $1.key }) ?? []

                        // Only show section if there are any badges to display
                        if !unlockedAchievements.isEmpty || !earnedTestBadges.isEmpty {
                            Divider()
                                .padding(.vertical, 4)

                            VStack(spacing: 12) {
                                HStack {
                                    Text("ACHEIVEMENTS")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppTheme.smallTitleText)
                                    Spacer()
                                    HStack(spacing: -10) {
                                        Text("\(achievements.score)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(AppTheme.bodyText)
                                        AnimatedScoreStar(size: 45)
                                    }
                                }

                                // Combined badge grid (4 columns for compact display)
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    // Score-based achievements
                                    ForEach(unlockedAchievements) { achievement in
                                        VStack(spacing: 4) {
                                            Image(systemName: achievement.symbol)
                                                .font(.system(size: 20))
                                                .foregroundColor(colorForAchievementTier(achievement.tier))

                                            Text("\(achievement.milestone)")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(AppTheme.electricYellow)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(AppTheme.panelFill)
                                        )
                                    }

                                    // Test completion badges
                                    ForEach(earnedTestBadges, id: \.key) { testName, progress in
                                        if let metadata = badgeMetadata[testName] {
                                            VStack(spacing: 4) {
                                                Image(systemName: metadata.symbol)
                                                    .font(.system(size: 20))
                                                    .foregroundColor(AppTheme.accentCyan)

                                                Text(metadata.title)
                                                    .font(.system(size: 9, weight: .medium))
                                                    .foregroundColor(AppTheme.electricYellow)
                                                    .multilineTextAlignment(.center)
                                                    .lineLimit(2)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
//                                            .background(
//                                                RoundedRectangle(cornerRadius: 6)
//                                                    .fill(AppTheme.panelFill)
//                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppTheme.panelFill)
                .shadow(color: AppTheme.black.opacity(0.3), radius: 10, x: 0, y: 4)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animatedProgress = displayProgress
            }
        }
        .onChange(of: displayProgress) { oldValue, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedProgress = newValue
            }
        }
    }

    // MARK: - Computed Properties

    private var gradientColors: [Color] {
        if isTestMode {
            switch testType {
            case "TOEFL":
                return [AppTheme.accentCyan, AppTheme.neonPurple]
            case "IELTS":
                return [AppTheme.neonPurple, AppTheme.accentPink]
            case "TIANZ":
                return [AppTheme.electricYellow, AppTheme.accentCyan]
            case "BOTH":
                return [AppTheme.accentCyan, AppTheme.neonPurple, AppTheme.accentPink]
            default:
                return [AppTheme.accentCyan, AppTheme.neonPurple]
            }
        } else {
            // Score mode gradient
            return [AppTheme.neonPurple, AppTheme.electricYellow]
        }
    }

    private var gradientForTestType: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: gradientColors),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Progress Mode

    private var isTestMode: Bool {
        testType != "NONE" && totalWords > 0
    }

    private var displayProgress: Double {
        if isTestMode {
            return progress
        } else if let next = achievementProgress?.next_milestone,
                  let score = achievementProgress?.score {
            return Double(score) / Double(next)
        } else {
            return 1.0  // all achievements unlocked
        }
    }

    private var displayTotal: Int {
        isTestMode ? totalWords : (achievementProgress?.next_milestone ?? 0)
    }

    private var displayCurrent: Int {
        isTestMode ? savedWords : (achievementProgress?.score ?? 0)
    }

    private var displayRemaining: Int {
        displayTotal - displayCurrent
    }

    private var badgeIcon: String {
        isTestMode ? "target" : "trophy.fill"
    }

    private var badgeText: String {
        isTestMode ? testType : "Score Progress"
    }

    private func colorForAchievementTier(_ tier: AchievementTier) -> Color {
        switch tier {
        case .beginner:
            return AppTheme.bronze
        case .intermediate:
            return AppTheme.silver
        case .advanced:
            return AppTheme.gold
        case .expert:
            return AppTheme.gold
        }
    }
}

// Preview
struct TestProgressBar_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isExpanded1 = true
        @State private var isExpanded2 = false
        @State private var isExpanded3 = true

        // Sample achievement progress with multiple unlocked achievements
        static let sampleAchievementProgress = AchievementProgressResponse(
            user_id: "preview-user",
            score: 850,
            achievements: [
                Achievement(milestone: 100, title: "First Steps", symbol: "star.fill", tier: .beginner, is_award: false, unlocked: true),
                Achievement(milestone: 250, title: "Getting Started", symbol: "star.circle.fill", tier: .beginner, is_award: false, unlocked: true),
                Achievement(milestone: 500, title: "Dedicated Learner", symbol: "sparkles", tier: .intermediate, is_award: false, unlocked: true),
                Achievement(milestone: 750, title: "Word Master", symbol: "crown.fill", tier: .intermediate, is_award: false, unlocked: true),
                Achievement(milestone: 1000, title: "Elite Scholar", symbol: "brain.head.profile", tier: .advanced, is_award: false, unlocked: false),
                Achievement(milestone: 2500, title: "Vocabulary Guru", symbol: "flame.fill", tier: .expert, is_award: false, unlocked: false)
            ],
            next_milestone: 1000,
            next_achievement: AchievementInfo(milestone: 1000, title: "Elite Scholar", symbol: "brain.head.profile", tier: .advanced, is_award: false),
            current_achievement: AchievementInfo(milestone: 750, title: "Word Master", symbol: "crown.fill", tier: .intermediate, is_award: false)
        )

        // Sample test vocabulary awards
        static let sampleTestAwards: TestVocabularyAwardsResponse = [
            "TOEFL_BEGINNER": TestVocabularyProgress(saved_test_words: 1000, total_test_words: 1000),
            "IELTS_INTERMEDIATE": TestVocabularyProgress(saved_test_words: 1500, total_test_words: 1500)
        ]

        var body: some View {
            VStack(spacing: 20) {
                TestProgressBar(
                    progress: 0.15,
                    totalWords: 3500,
                    savedWords: 525,
                    testType: "TOEFL",
                    streakDays: 5,
                    achievementProgress: Self.sampleAchievementProgress,
                    testVocabularyAwards: Self.sampleTestAwards,
                    isExpanded: $isExpanded1
                )

                TestProgressBar(
                    progress: 0.67,
                    totalWords: 2800,
                    savedWords: 1876,
                    testType: "IELTS",
                    streakDays: 12,
                    achievementProgress: Self.sampleAchievementProgress,
                    testVocabularyAwards: Self.sampleTestAwards,
                    isExpanded: $isExpanded2
                )

                TestProgressBar(
                    progress: 0.92,
                    totalWords: 5000,
                    savedWords: 4600,
                    testType: "BOTH",
                    streakDays: 0,
                    achievementProgress: Self.sampleAchievementProgress,
                    testVocabularyAwards: Self.sampleTestAwards,
                    isExpanded: $isExpanded3
                )
            }
            .padding()
            .background(Color(.systemGroupedBackground))
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
