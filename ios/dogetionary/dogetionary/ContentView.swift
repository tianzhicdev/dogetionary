//
//  ContentView.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var userManager = UserManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var questionQueue = QuestionQueueManager.shared
    @StateObject private var backgroundTaskManager = BackgroundTaskManager.shared
    @State private var selectedTab = 0
    @State private var showOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            // App banner at the top
            AppBanner()

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
                    Text("Schedule")
                }
                .tag(1)

            ReviewView()
                .tabItem {
                    Image(systemName: "brain.head.profile")
                    Text("Practice")
                }
                .tag(2)
                .badge(backgroundTaskManager.practiceCount)

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
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .onAppear {
            // Initialize user manager to generate UUID if needed
            _ = userManager.getUserID()

            // Check if onboarding needs to be shown
            #if DEBUG
            // In debug mode, always show onboarding
            showOnboarding = true
            #else
            // In production, only show if not completed
            if !userManager.hasCompletedOnboarding {
                showOnboarding = true
            }
            #endif

            // Sync user preferences from server on app startup
            userManager.syncPreferencesFromServer()

            // Request notification permissions
            notificationManager.requestPermission { granted in
                if granted {
                    print("✅ User granted notification permission")
                }
            }

            // Note: Practice badge count is automatically updated via @Published practiceCount
            // Synced at: app start (startForegroundTimer), after onboarding, after each review
        }
        .onChange(of: userManager.hasCompletedOnboarding) { _, completed in
            if completed {
                showOnboarding = false
                // Sync practice counts after onboarding (schedule may have been created)
                Task {
                    await BackgroundTaskManager.shared.fetchAndUpdatePracticeCounts()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldNavigateToReview)) { _ in
            // Navigate to Review tab when notification is tapped
            selectedTab = 2
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            // Track tab navigation
            let action: AnalyticsAction = switch newTab {
            case 0: .navTabDictionary
            case 1: .navTabSaved
            case 2: .navTabReview
            case 3: .navTabLeaderboard
            case 4: .navTabSettings
            default: .navTabDictionary
            }
            AnalyticsManager.shared.track(action: action)
        }
    }
}

#Preview {
    ContentView()
}
