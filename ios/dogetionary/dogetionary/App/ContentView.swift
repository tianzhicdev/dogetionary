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
    @State private var selectedView = 0  // 0 = TAT (default)
    @State private var showOnboarding = false
    @State private var dailyBannerExpanded = false
    @State private var showDailyGoalCelebration = false  // Full-screen celebration
    @State private var showSearchBar = false  // Control search bar visibility (for TAT tab only)
    @State private var isSearchEnabled = false  // Control search button visibility (only on TAT tab)
    @Environment(\.scenePhase) var scenePhase

    private var dailyTarget: Int {
        let questionsPerMinute: Double = 2.0
        return Int(Double(userManager.dailyTimeCommitmentMinutes) * questionsPerMinute)
    }

    private var remainingReviewsForDailyGoal: Int {
        let reviewsPast24h = userManager.practiceStatus?.reviews_past_24h ?? 0
        let remaining = dailyTarget - reviewsPast24h
        return max(0, remaining)
    }

    var body: some View {
        // Show force upgrade view if required
        if appVersionManager.requiresUpgrade {
            ForceUpgradeView(
                upgradeURL: appVersionManager.upgradeURL,
                message: appVersionManager.upgradeMessage
            )
        } else {
        ZStack {
            
            AppTheme.verticalGradient2.ignoresSafeArea()
            // Main app content with daily progress banner + native TabView
            VStack(spacing: 0) {
                // Daily progress banner (persistent across all tabs)
                DailyProgressBanner(
                    testType: userManager.activeTestType?.rawValue ?? "NONE",
                    streakDays: userManager.streakDays,
                    reviewsPast24h: userManager.practiceStatus?.reviews_past_24h ?? 0,
                    dailyTarget: dailyTarget,
                    bundleProgress: userManager.practiceStatus?.bundle_progress,
                    achievementProgress: nil,
                    testVocabularyAwards: nil,
                    isExpanded: $dailyBannerExpanded,
                    showDailyGoalCelebration: $showDailyGoalCelebration,
                    showSearchBar: $showSearchBar,
                    isSearchEnabled: $isSearchEnabled
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Tab view
                TabView(selection: $selectedView) {
                        Group {
                            if remainingReviewsForDailyGoal > 0 {
                                ReviewView(showSearchBar: $showSearchBar)
                                    .badge(remainingReviewsForDailyGoal)
                            } else {
                                ReviewView(showSearchBar: $showSearchBar)
                            }
                        }
                        .tabItem {
                            Label("TAT", systemImage: "figure.boxing")
                        }
                        .tag(0)
                        .onAppear {
                            isSearchEnabled = true
                        }
                        .onDisappear {
                            isSearchEnabled = false
                            showSearchBar = false  // Close search bar when leaving TAT tab
                        }

                        SavedWordsView()
                            .tabItem {
                                Label("History", systemImage: "clock.fill")
                            }
                            .tag(1)
                            .onAppear {
                                isSearchEnabled = false
                            }

                        SettingsView()
                            .tabItem {
                                Label("Settings", systemImage: "gear")
                            }
                            .tag(2)
                            .onAppear {
                                isSearchEnabled = false
                            }
                    }
                    .accentColor(AppTheme.selectableTint)
            }

            // Daily goal celebration (full-screen, same level as badge celebration)
            if showDailyGoalCelebration {
                DailyGoalCelebrationView {
                    showDailyGoalCelebration = false
                }
                .zIndex(900)
            }

            // Debug overlay (always on top, only visible when debug mode enabled)
            if DebugConfig.isDeveloperModeEnabled {
                DebugOverlayView()
                    .zIndex(999)
            }
        }
        .onChange(of: selectedView) { oldValue, newValue in
            // Track navigation analytics (Search tab removed, indices shifted)
            let action: AnalyticsAction = switch newValue {
            case 0: .navTabReview  // TAT
            case 1: .navTabSaved  // History
            case 2: .navTabSettings
            default: .navTabReview
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

                // Start preloading questions now that onboarding is complete
                // This prevents videos from downloading/playing during onboarding
                questionQueue.preloadQuestions()

                // Refresh practice status after onboarding (schedule may have been created)
                Task {
                    await userManager.refreshPracticeStatus()
                }
            }
        }
        .onChange(of: AppState.shared.shouldNavigateToReview) { _, shouldNavigate in
            if shouldNavigate {
                // Navigate to TAT view when notification is tapped
                selectedView = 0
            }
        }
        .environment(AppState.shared)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Refresh practice status when app becomes active
            if newPhase == .active {
                Task {
                    await userManager.refreshPracticeStatus()
                }
            }
        }
        .onChange(of: AppState.shared.testSettingsChanged) { _, changed in
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
