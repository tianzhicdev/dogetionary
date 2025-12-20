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
    @State private var appState = AppState.shared
    @State private var selectedView = 0  // 0 = Search (default)
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
        ZStack {
            // Main app content with native TabView
            TabView(selection: $selectedView) {
                SearchView(showProgressBar: true)
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(0)

                ReviewView()
                    .tabItem {
                        Label("Shojin", image: "shojin_symbol")
                    }
                    .badge(userManager.practiceCount > 0 ? userManager.practiceCount : 0)
                    .tag(2)

                SavedWordsView()
                    .tabItem {
                        Label("History", systemImage: "clock.fill")
                    }
                    .tag(3)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(5)
            }
            .accentColor(AppTheme.selectableTint)

            // Debug overlay (always on top, only visible when debug mode enabled)
            if DebugConfig.isDeveloperModeEnabled {
                DebugOverlayView()
                    .zIndex(999)
            }
        }
        .onChange(of: selectedView) { oldValue, newValue in
            // Track navigation analytics
            let action: AnalyticsAction = switch newValue {
            case 2: .navTabReview  // Practice
            case 3: .navTabSaved  // Saved Words
            case 5: .navTabSettings
            default: .navTabDictionary
            }
            AnalyticsManager.shared.track(action: action)
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
                // NotificationManager already logs the permission result
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
        .onChange(of: appState.shouldNavigateToReview) { _, shouldNavigate in
            if shouldNavigate {
                // Navigate to Practice view when notification is tapped
                selectedView = 2
            }
        }
        .environment(appState)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Refresh practice status when app becomes active
            if newPhase == .active {
                Task {
                    await userManager.refreshPracticeStatus()
                }
            }
        }
        .onChange(of: appState.testSettingsChanged) { _, changed in
            if changed {
                // Auto-refresh question queue when test settings change
                questionQueue.forceRefresh()
            }
        }
        } // end else (not requiring upgrade)
    }
}

#Preview {
    ContentView()
}
