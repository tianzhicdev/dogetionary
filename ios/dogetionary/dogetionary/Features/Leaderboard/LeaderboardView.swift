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
            // Background gradient
            AppTheme.backgroundGradient
                .ignoresSafeArea()

            Group {
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading leaderboard...")
                                .foregroundColor(AppTheme.systemText)

                        }
                    } else if let errorMessage = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: AppTheme.emptyStateIconSize))
                                .foregroundColor(AppTheme.warningColor)

                            Text("Error")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(errorMessage)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            Button("Try Again") {
                                Task {
                                    await loadLeaderboard()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    } else if leaderboard.isEmpty {
                        AppTheme.emptyState(
                            icon: "chart.bar",
                            title: "No users found",
                            message: "Be the first to start learning!"
                        )
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
                        .font(.system(size: 15, weight: isCurrentUser ? .semibold : .medium))
                        .foregroundColor(
                            isCurrentUser ?
                            AppTheme.primaryBlue : AppTheme.leaderboard.userNameTextColor
                        )
                        .lineLimit(1)

                    if isCurrentUser {
                        Text("You")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppTheme.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.primaryGradient)
                            .cornerRadius(4)
                    }
                }

                if !entry.user_motto.isEmpty {
                    Text(entry.user_motto)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Score with icon
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        LinearGradient(colors: [AppTheme.systemYellow, AppTheme.warningColor],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("\(entry.score ?? entry.total_reviews)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        isCurrentUser ?
                        AppTheme.primaryGradient :
                        LinearGradient(colors: [Color.primary, Color.primary],
                                     startPoint: .leading, endPoint: .trailing)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Group {
                if isCurrentUser {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppTheme.primaryGradient, lineWidth: 2)
                        )
                        .shadow(color: AppTheme.infoColor.opacity(AppTheme.mediumHighOpacity), radius: 8, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.white)
                        .shadow(color: AppTheme.subtleShadowColor, radius: 3, x: 0, y: 1)
                }
            }
        )
    }
}

struct RankBadgeView: View {
    let rank: Int

    private var badgeGradient: LinearGradient {
        switch rank {
        case 1:
            return AppTheme.goldGradient
        case 2:
            return AppTheme.silverGradient
        case 3:
            return AppTheme.bronzeGradient
        default:
            return AppTheme.defaultRankGradient
        }
    }

    private var textColor: Color {
        switch rank {
        case 1:
            return AppTheme.goldTextColor
        case 2:
            return AppTheme.silverTextColor
        case 3:
            return .white
        default:
            return AppTheme.defaultRankTextColor
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(badgeGradient)
                .frame(width: 30, height: 30)
                .shadow(color: rank <= 3 ? AppTheme.black.opacity(AppTheme.mediumOpacity) : AppTheme.clear, radius: 3, y: 2)

            if rank <= 3 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 13))
                    .foregroundColor(textColor)
            } else {
                Text("\(rank)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(textColor)
            }
        }
    }
}

#Preview {
    LeaderboardView()
}
