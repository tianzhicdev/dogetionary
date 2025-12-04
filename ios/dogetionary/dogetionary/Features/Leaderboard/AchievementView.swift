//
//  AchievementView.swift
//  dogetionary
//
//  Created by Claude Code on 11/20/25.
//

import SwiftUI

struct AchievementView: View {
    let progress: AchievementProgressResponse
    @Binding var isExpanded: Bool

    // Calculate progress percentage
    private var progressPercentage: Double {
        guard let nextMilestone = progress.next_milestone else { return 1.0 }
        let currentMilestone = progress.current_achievement?.milestone ?? 0
        let totalRange = Double(nextMilestone - currentMilestone)
        let currentProgress = Double(progress.score - currentMilestone)
        return min(currentProgress / totalRange, 1.0)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed state - always visible
            collapsedView()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }

            // Expanded state - shows on tap
            if isExpanded {
                expandedView()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: AppTheme.subtleShadowColor, radius: 10, x: 0, y: 4)
        )
    }

    @ViewBuilder
    private func collapsedView() -> some View {
        HStack(spacing: 12) {
            // Current achievement badge
            if let current = progress.current_achievement {
                Image(systemName: current.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colorForTier(current.tier))
            }

            // Score count
            Text("\(progress.score)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)

            // Next milestone preview
            if let next = progress.next_achievement {
                Text("• Next:")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Image(systemName: next.symbol)
                    .font(.system(size: 16))
                    .foregroundColor(.gray.opacity(0.5))

                Text("\(next.milestone)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Expand/collapse chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func expandedView() -> some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.vertical, 4)

            // Next milestone section
            if let next = progress.next_achievement {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "target")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Next: \(next.title)")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .foregroundColor(.secondary)

                    // Large badge icon
                    Image(systemName: next.symbol)
                        .font(.system(size: 48))
                        .foregroundColor(colorForTier(next.tier).opacity(0.3))
                        .padding(.vertical, 8)

                    // Progress bar
                    VStack(spacing: 4) {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(AppTheme.mediumOpacity))
                                .frame(height: 20)

                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: gradientForTier(next.tier)),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width * progressPercentage, height: 20)
                            }
                            .frame(height: 20)
                        }

                        HStack {
                            Spacer()
                            Text("\(progress.score) / \(next.milestone)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Achievements grid
            VStack(spacing: 12) {
                HStack {
                    Text("Achievements")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                // Badge grid (3 columns)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(progress.achievements) { achievement in
                        BadgeCell(achievement: achievement)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func colorForTier(_ tier: AchievementTier) -> Color {
        switch tier {
        case .beginner:
            return AppTheme.successColor
        case .intermediate:
            return AppTheme.infoColor
        case .advanced:
            return Color.purple
        case .expert:
            return AppTheme.warningColor
        }
    }

    private func gradientForTier(_ tier: AchievementTier) -> [Color] {
        switch tier {
        case .beginner:
            return [AppTheme.successColor, Color.mint]
        case .intermediate:
            return [AppTheme.infoColor, Color.cyan]
        case .advanced:
            return [Color.purple, Color.pink]
        case .expert:
            return [AppTheme.warningColor, Color.yellow]
        }
    }
}

struct BadgeCell: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: achievement.symbol)
                .font(.system(size: 28))
                .foregroundColor(achievement.unlocked ? colorForTier(achievement.tier) : Color.gray.opacity(0.3))

            Text("\(achievement.milestone)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(achievement.unlocked ? .primary : .secondary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(achievement.unlocked ? colorForTier(achievement.tier).opacity(0.08) : Color.gray.opacity(0.05))
        )
    }

    private func colorForTier(_ tier: AchievementTier) -> Color {
        switch tier {
        case .beginner:
            return AppTheme.successColor
        case .intermediate:
            return AppTheme.infoColor
        case .advanced:
            return Color.purple
        case .expert:
            return AppTheme.warningColor
        }
    }
}

// MARK: - Preview

struct AchievementView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var isExpanded = false

        var body: some View {
            VStack(spacing: 20) {
                // Preview with 180 score (unlocked first achievement)
                AchievementView(
                    progress: AchievementProgressResponse(
                        user_id: "test",
                        score: 180,
                        achievements: [
                            Achievement(milestone: 100, title: "First Steps", symbol: "leaf.fill", tier: .beginner, is_award: false, unlocked: true),
                            Achievement(milestone: 300, title: "Growing", symbol: "leaf.circle.fill", tier: .beginner, is_award: false, unlocked: false),
                            Achievement(milestone: 500, title: "Blooming", symbol: "sparkles", tier: .beginner, is_award: false, unlocked: false),
                            Achievement(milestone: 1000, title: "Century", symbol: "star.fill", tier: .beginner, is_award: false, unlocked: false),
                            Achievement(milestone: 5000, title: "Word Master", symbol: "medal.fill", tier: .intermediate, is_award: true, unlocked: false)
                        ],
                        next_milestone: 300,
                        next_achievement: AchievementInfo(milestone: 300, title: "Growing", symbol: "leaf.circle.fill", tier: .beginner, is_award: false),
                        current_achievement: AchievementInfo(milestone: 100, title: "First Steps", symbol: "leaf.fill", tier: .beginner, is_award: false)
                    ),
                    isExpanded: $isExpanded
                )
                .padding()

                Spacer()
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
