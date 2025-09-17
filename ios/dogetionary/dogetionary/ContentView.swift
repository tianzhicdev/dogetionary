//
//  ContentView.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var userManager = UserManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var selectedTab = 0
    @State private var reviewBadgeCount = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Dictionary")
                }
                .tag(0)
            
            SavedWordsView()
                .tabItem {
                    Image(systemName: "bookmark.fill")
                    Text("Saved")
                }
                .tag(1)
            
            ReviewView()
                .tabItem {
                    Image(systemName: "brain.head.profile")
                    Text("Review")
                }
                .tag(2)
                .badge(reviewBadgeCount)
            
            LeaderboardView()
                .tabItem {
                    Image(systemName: "trophy.fill")
                    Text("Leaderboard")
                }
                .tag(3)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(4)
        }
        .onAppear {
            // Initialize user manager to generate UUID if needed
            _ = userManager.getUserID()

            // Sync user preferences from server on app startup
            userManager.syncPreferencesFromServer()

            // Request notification permissions
            notificationManager.requestPermission { granted in
                if granted {
                    print("✅ User granted notification permission")
                }
            }

            // Set initial badge count from cache
            reviewBadgeCount = BackgroundTaskManager.shared.cachedOverdueCount

            // Start listening for badge updates
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                reviewBadgeCount = BackgroundTaskManager.shared.cachedOverdueCount
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldNavigateToReview)) { _ in
            // Navigate to Review tab when notification is tapped
            selectedTab = 2
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
