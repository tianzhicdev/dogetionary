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
                                .foregroundColor(.secondary)
                        }
                    } else if let errorMessage = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: AppTheme.emptyStateIconSize))
                                .foregroundColor(.orange)

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
                        .foregroundColor(isCurrentUser ? AppTheme.primaryBlue : .primary)
                        .lineLimit(1)

                    if isCurrentUser {
                        Text("You")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.primaryBlue)
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
                    .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.3))
                Text("\(entry.score ?? entry.total_reviews)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isCurrentUser ? AppTheme.primaryBlue : .primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            isCurrentUser ?
            AppTheme.primaryBlue.opacity(0.08) :
            Color.white
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

struct RankBadgeView: View {
    let rank: Int

    private var badgeColor: Color {
        switch rank {
        case 1:
            return Color(red: 1.0, green: 0.84, blue: 0.3)
        case 2:
            return Color(red: 0.75, green: 0.75, blue: 0.78)
        case 3:
            return Color(red: 0.8, green: 0.55, blue: 0.35)
        default:
            return Color(red: 0.92, green: 0.93, blue: 0.95)
        }
    }

    private var textColor: Color {
        switch rank {
        case 1:
            return Color(red: 0.7, green: 0.5, blue: 0.1)
        case 2:
            return Color(red: 0.4, green: 0.4, blue: 0.45)
        case 3:
            return .white
        default:
            return Color(red: 0.5, green: 0.5, blue: 0.55)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(badgeColor)
                .frame(width: 30, height: 30)

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