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
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading leaderboard...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
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
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        
                        Text("No users found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Be the first to start learning!")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(leaderboard) { entry in
                            LeaderboardRowView(entry: entry, isCurrentUser: entry.user_id == userManager.userID)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Leaderboard")
            .refreshable {
                await loadLeaderboard()
            }
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
        HStack(spacing: 12) {
            // Rank
            RankBadgeView(rank: entry.rank)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.user_name)
                        .font(.headline)
                        .fontWeight(isCurrentUser ? .bold : .medium)
                        .foregroundColor(isCurrentUser ? .blue : .primary)
                    
                    if isCurrentUser {
                        Text("(You)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .fontWeight(.medium)
                    }
                }
                
                if !entry.user_motto.isEmpty {
                    Text(entry.user_motto)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.total_reviews)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(isCurrentUser ? .blue : .primary)
                
                Text("reviews")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .background(
            isCurrentUser ? 
            Color.blue.opacity(0.1) : 
            Color.clear
        )
        .cornerRadius(8)
    }
}

struct RankBadgeView: View {
    let rank: Int
    
    private var badgeColor: Color {
        switch rank {
        case 1:
            return .yellow
        case 2:
            return Color(.systemGray2)
        case 3:
            return Color(.brown)
        default:
            return Color(.systemGray4)
        }
    }
    
    private var textColor: Color {
        switch rank {
        case 1:
            return .orange
        case 2:
            return .black
        case 3:
            return .white
        default:
            return .black
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(badgeColor)
                .frame(width: 36, height: 36)
            
            if rank <= 3 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16))
                    .foregroundColor(textColor)
            } else {
                Text("\(rank)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(textColor)
            }
        }
    }
}

#Preview {
    LeaderboardView()
}