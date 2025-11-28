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
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(gradientForTestType)
                )

                Spacer()

                // Progress percentage
                Text("\(Int(displayProgress * 100))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                // Expand/collapse button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
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
                        .overlay(
                            // Shimmer effect
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.0),
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.0)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * animatedProgress)
                                .mask(
                                    RoundedRectangle(cornerRadius: 8)
                                        .frame(width: geometry.size.width * animatedProgress)
                                )
                                .offset(x: isExpanded ? 0 : -100)
                                .animation(
                                    Animation.linear(duration: 1.5)
                                        .repeatForever(autoreverses: false),
                                    value: isExpanded
                                )
                        )
                }
                .frame(height: 20)

                // Progress text overlay
                HStack {
                    Spacer()
                    Text("\(displayCurrent) / \(displayTotal)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(animatedProgress > 0.5 ? .white : .primary)
                        .padding(.trailing, 8)
                }
            }

            // Detailed stats (expandable)
            if isExpanded {
                VStack(spacing: 8) {
                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 2) {
                                Text("\(displayRemaining)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.orange)
                                if !isTestMode {
                                    Text("pts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()

                        VStack(alignment: .center, spacing: 4) {
                            Text("Streak")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(streakDays > 0 ? .orange : .gray)
                                    .font(.system(size: 14))
                                Text("\(streakDays)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(streakDays > 0 ? .orange : .gray)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(isTestMode ? "Completed" : "Score")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 2) {
                                Text("\(displayCurrent)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.green)
                                if !isTestMode {
                                    Text("pts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
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
                                    Text("Achievements")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if let current = achievements.current_achievement {
                                        Image(systemName: current.symbol)
                                            .font(.system(size: 16))
                                            .foregroundColor(colorForAchievementTier(current.tier))
                                        Text("\(achievements.score) pts")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.primary)
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
                                                .foregroundColor(.primary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(colorForAchievementTier(achievement.tier).opacity(0.08))
                                        )
                                    }

                                    // Test completion badges
                                    ForEach(earnedTestBadges, id: \.key) { testName, progress in
                                        if let metadata = badgeMetadata[testName] {
                                            VStack(spacing: 4) {
                                                Image(systemName: metadata.symbol)
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.green)

                                                Text(metadata.title)
                                                    .font(.system(size: 9, weight: .medium))
                                                    .foregroundColor(.primary)
                                                    .multilineTextAlignment(.center)
                                                    .lineLimit(2)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Color.green.opacity(0.08))
                                            )
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
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
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
                return [Color.blue, Color.cyan]
            case "IELTS":
                return [Color.purple, Color.pink]
            case "TIANZ":
                return [Color.orange, Color.yellow]
            case "BOTH":
                return [Color.blue, Color.purple, Color.pink]
            default:
                return [Color.green, Color.blue]
            }
        } else {
            // Score mode gradient
            return [Color.purple, Color.orange]
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
            return .green
        case .intermediate:
            return .blue
        case .advanced:
            return .purple
        case .expert:
            return .orange
        }
    }
}

// Preview
struct TestProgressBar_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isExpanded1 = false
        @State private var isExpanded2 = false
        @State private var isExpanded3 = false

        var body: some View {
            VStack(spacing: 20) {
                TestProgressBar(
                    progress: 0.15,
                    totalWords: 3500,
                    savedWords: 525,
                    testType: "TOEFL",
                    streakDays: 5,
                    achievementProgress: nil,
                    testVocabularyAwards: nil,
                    isExpanded: $isExpanded1
                )

                TestProgressBar(
                    progress: 0.67,
                    totalWords: 2800,
                    savedWords: 1876,
                    testType: "IELTS",
                    streakDays: 12,
                    achievementProgress: nil,
                    testVocabularyAwards: nil,
                    isExpanded: $isExpanded2
                )

                TestProgressBar(
                    progress: 0.92,
                    totalWords: 5000,
                    savedWords: 4600,
                    testType: "BOTH",
                    streakDays: 0,
                    achievementProgress: nil,
                    testVocabularyAwards: nil,
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
