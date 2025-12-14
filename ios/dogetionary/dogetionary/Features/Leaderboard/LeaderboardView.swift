//
//  LeaderboardView.swift
//  dogetionary
//
//  Created by biubiu on 9/12/25.
//

import SwiftUI

struct LeaderboardView: View {
    @State private var leaderboard: [LeaderboardEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @ObservedObject private var userManager = UserManager.shared
    
    var body: some View {
        ZStack {
            // Background gradient - matches SettingsView
            AppTheme.verticalGradient2
                .ignoresSafeArea()

            Group {
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(AppTheme.accentCyan)
                            Text("LOADING LEADERBOARD...")
                                .foregroundColor(AppTheme.smallTitleText)

                        }
                    } else if let errorMessage = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: AppTheme.emptyStateIconSize))
                                .foregroundColor(AppTheme.selectableTint)

                            Text("ERROR")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.smallTitleText)

                            Text(errorMessage.uppercased())
                                .foregroundColor(AppTheme.smallTextColor1)
                                .multilineTextAlignment(.center)

                            Button("TRY AGAIN") {
                                Task {
                                    await loadLeaderboard()
                                }
                            }
                            .foregroundColor(AppTheme.bgPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentCyan)
                            .cornerRadius(4)
                        }
                        .padding()
                    } else if leaderboard.isEmpty {
                        VStack(spacing: 20) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: AppTheme.emptyStateIconSize))
                                .foregroundColor(AppTheme.accentCyan)

                            Text("NO USERS FOUND")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.smallTitleText)

                            Text("BE THE FIRST TO START LEARNING!")
                                .foregroundColor(AppTheme.smallTextColor1)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(leaderboard) { entry in
                                    LeaderboardRowView(entry: entry, isCurrentUser: entry.user_id == userManager.userID)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
            }
        }
        .refreshable {
            await loadLeaderboard()
        }
        .onAppear {
            Task {
                await loadLeaderboard()
            }
        }
    }
    
    @MainActor
    private func loadLeaderboard() async {
        isLoading = true
        errorMessage = nil
        
        DictionaryService.shared.getLeaderboard { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let entries):
                    self.leaderboard = entries
                    self.errorMessage = nil
                case .failure(let error):
                    self.errorMessage = "Failed to load leaderboard: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct LeaderboardRowView: View {
    let entry: LeaderboardEntry
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Rank badge
            RankBadgeView(rank: entry.rank)

            // Name and motto
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.user_name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.bodyText
                        )
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if isCurrentUser {
                        Text("YOU")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.bgPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.selectableTint)
                            .cornerRadius(AppTheme.smallBadge.cornerRadius)
                    }
                }

                if !entry.user_motto.isEmpty {
                    Text(entry.user_motto)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.smallTextColor1)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            // Score with icon
            HStack(spacing: -10) {

                Text("\(entry.score ?? entry.total_reviews)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.bodyText)
                
                    AnimatedScoreStar(size: 45)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)

    }
}

struct RankBadgeView: View {
    let rank: Int

    private var badgeColor: Color {
        switch rank {
        case 1:
            return AppTheme.gold
        case 2:
            return AppTheme.silver
        case 3:
            return AppTheme.bronze
        default:
            return AppTheme.clear
        }
    }

    private var textColor: Color {
        switch rank {
        case 1, 2, 3:
            return AppTheme.bgPrimary
        default:
            return AppTheme.smallTitleText
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(badgeColor)
                .frame(width: 30, height: 30)
//                .overlay(
//                    Circle()
//                        .stroke(rank <= 3 ? AppTheme.accentCyan : AppTheme.accentCyan.opacity(0.3), lineWidth: rank <= 3 ? 2 : 1)
//                )

            if rank <= 3 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 13))
                    .foregroundColor(textColor)
            } else {
                Text("\(rank)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(textColor)
            }
        }
    }
}

#Preview {
    LeaderboardView()
}
