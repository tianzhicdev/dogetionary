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
    @StateObject private var appVersionManager = AppVersionManager.shared
    @State private var selectedView = 0  // 0 = Search (default)
    @State private var isMenuExpanded = false
    @State private var showOnboarding = false
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        // Show force upgrade view if required
        if appVersionManager.requiresUpgrade {
            ForceUpgradeView(
                upgradeURL: appVersionManager.upgradeURL,
                message: appVersionManager.upgradeMessage
            )
        } else {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // App banner at the top
                AppBanner()

                // View switcher
                Group {
                    switch selectedView {
                    case 0:
                        SearchView(showProgressBar: true)
                    case 1:
                        ScheduleView()
                    case 2:
                        ReviewView()
                    case 3:
                        SavedWordsView()
                    case 4:
                        LeaderboardView()
                    case 5:
                        SettingsView()
                    default:
                        SearchView(showProgressBar: true)
                    }
                }
            }

            // Floating Action Menu (overlay)
            FloatingActionMenu(
                isExpanded: $isMenuExpanded,
                selectedView: $selectedView,
                practiceCount: userManager.practiceCount,
                onItemTapped: { tag in
                    selectedView = tag

                    // Track navigation analytics
                    let action: AnalyticsAction = switch tag {
                    case 1: .navTabSaved  // Schedule
                    case 2: .navTabReview  // Practice
                    case 3: .navTabSaved  // Saved Words
                    case 4: .navTabLeaderboard
                    case 5: .navTabSettings
                    default: .navTabDictionary
                    }
                    AnalyticsManager.shared.track(action: action)
                }
            )
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .onAppear {
            // Check app version on launch
            appVersionManager.checkVersion()

            // Initialize user manager to generate UUID if needed
            _ = userManager.getUserID()

            // Check if onboarding needs to be shown
            if DebugConfig.isDeveloperModeEnabled {
                // In developer mode, always show onboarding
                showOnboarding = true
            } else {
                // Otherwise, only show if not completed
                if !userManager.hasCompletedOnboarding {
                    showOnboarding = true
                }
            }

            // Sync user preferences from server on app startup
            userManager.syncPreferencesFromServer()

            // Request notification permissions
            notificationManager.requestPermission { granted in
                if granted {
                    print("✅ User granted notification permission")
                }
            }

            // Refresh practice status on app startup
            Task {
                await userManager.refreshPracticeStatus()
            }
        }
        .onChange(of: userManager.hasCompletedOnboarding) { _, completed in
            if completed {
                showOnboarding = false
                // Refresh practice status after onboarding (schedule may have been created)
                Task {
                    await userManager.refreshPracticeStatus()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shouldNavigateToReview)) { _ in
            // Navigate to Practice view when notification is tapped
            selectedView = 2
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Refresh practice status when app becomes active
            if newPhase == .active {
                Task {
                    await userManager.refreshPracticeStatus()
                }
            }
        }
        } // end else (not requiring upgrade)
    }
}

#Preview {
    ContentView()
}
