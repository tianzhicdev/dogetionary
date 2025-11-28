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
                        .foregroundStyle(
                            isCurrentUser ?
                            LinearGradient(colors: [Color.blue, Color.purple],
                                         startPoint: .leading, endPoint: .trailing) :
                            LinearGradient(colors: [Color.primary, Color.primary],
                                         startPoint: .leading, endPoint: .trailing)
                        )
                        .lineLimit(1)

                    if isCurrentUser {
                        Text("You")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                LinearGradient(colors: [Color.blue, Color.purple],
                                             startPoint: .leading, endPoint: .trailing)
                            )
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
                        LinearGradient(colors: [Color.yellow, Color.orange],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("\(entry.score ?? entry.total_reviews)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        isCurrentUser ?
                        LinearGradient(colors: [Color.blue, Color.purple],
                                     startPoint: .leading, endPoint: .trailing) :
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
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    LinearGradient(colors: [Color.blue, Color.purple],
                                                 startPoint: .leading, endPoint: .trailing),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: Color.blue.opacity(0.2), radius: 8, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
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
            // Gold gradient
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.88, blue: 0.4), Color(red: 1.0, green: 0.75, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 2:
            // Silver gradient
            return LinearGradient(
                colors: [Color(red: 0.85, green: 0.85, blue: 0.88), Color(red: 0.65, green: 0.65, blue: 0.70)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 3:
            // Bronze gradient
            return LinearGradient(
                colors: [Color(red: 0.9, green: 0.65, blue: 0.45), Color(red: 0.7, green: 0.45, blue: 0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [Color(red: 0.92, green: 0.93, blue: 0.95), Color(red: 0.85, green: 0.86, blue: 0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
                .fill(badgeGradient)
                .frame(width: 30, height: 30)
                .shadow(color: rank <= 3 ? Color.black.opacity(0.15) : Color.clear, radius: 3, y: 2)

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