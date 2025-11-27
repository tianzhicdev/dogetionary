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
    @StateObject private var appVersionManager = AppVersionManager.shared
    @State private var selectedTab = 0
    @State private var showOnboarding = false

    var body: some View {
        // Show force upgrade view if required
        if appVersionManager.requiresUpgrade {
            ForceUpgradeView(
                upgradeURL: appVersionManager.upgradeURL,
                message: appVersionManager.upgradeMessage
            )
        } else {
        VStack(spacing: 0) {
            // App banner at the top
            AppBanner()

            TabView(selection: $selectedTab) {
            DictionaryTabView(selectedTab: $selectedTab, backgroundTaskManager: backgroundTaskManager)
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Dictionary")
                }
                .tag(0)

            ScheduleView()
                .tabItem {
                    Image(systemName: "calendar")
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
            case 1: .navTabSaved  // Schedule (reusing saved action)
            case 2: .navTabReview
            case 3: .navTabLeaderboard
            case 4: .navTabSettings
            default: .navTabDictionary
            }
            AnalyticsManager.shared.track(action: action)
        }
        } // end else (not requiring upgrade)
    }
}

// Dictionary tab with toggle for Search and Words
struct DictionaryTabView: View {
    @Binding var selectedTab: Int
    @ObservedObject var backgroundTaskManager: BackgroundTaskManager
    @State private var selectedView = 0  // 0 = Search, 1 = Words
    @State private var savedWords: [SavedWord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toggle at the very top
            Picker("View", selection: $selectedView) {
                Text("Search").tag(0)
                Text("Words").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
//            Spacer()

            // Content below
            if selectedView == 0 {
                SearchView(selectedTab: $selectedTab, backgroundTaskManager: backgroundTaskManager, showProgressBar: true)
            } else {
                NavigationView {
                    SavedWordsListView(
                        savedWords: $savedWords,
                        isLoading: isLoading,
                        errorMessage: errorMessage,
                        onRefresh: { await loadSavedWords() },
                        onDelete: { word in await deleteSavedWord(word) },
                        onToggleKnown: { word in await toggleKnownStatus(word) }
                    )
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .onAppear {
            if selectedView == 1 {
                Task {
                    await loadSavedWords()
                }
            }
        }
        .onChange(of: selectedView) { _, newValue in
            if newValue == 1 {
                Task {
                    await loadSavedWords()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshSavedWords)) { _ in
            if selectedView == 1 {
                Task {
                    await loadSavedWords()
                }
            }
        }
    }

    @MainActor
    private func loadSavedWords() async {
        isLoading = true
        errorMessage = nil

        await withCheckedContinuation { continuation in
            DictionaryService.shared.getSavedWords { result in
                DispatchQueue.main.async {
                    self.isLoading = false

                    switch result {
                    case .success(let words):
                        self.savedWords = words.sorted { word1, word2 in
                            if word1.is_known != word2.is_known {
                                return !word1.is_known
                            }
                            guard let date1 = word1.next_review_date else { return false }
                            guard let date2 = word2.next_review_date else { return true }
                            let formatter = ISO8601DateFormatter()
                            guard let d1 = formatter.date(from: date1),
                                  let d2 = formatter.date(from: date2) else { return false }
                            return d1 < d2
                        }
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func deleteSavedWord(_ word: SavedWord) async {
        DictionaryService.shared.unsaveWord(wordID: word.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.savedWords.removeAll { $0.id == word.id }
                    AnalyticsManager.shared.track(action: .savedDeleteWord, metadata: [
                        "word": word.word,
                        "word_id": word.id
                    ])
                case .failure(let error):
                    self.errorMessage = "Failed to delete word: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func toggleKnownStatus(_ word: SavedWord) async {
        let newKnownStatus = !word.is_known
        DictionaryService.shared.toggleExcludeFromPractice(
            word: word.word,
            excluded: newKnownStatus,
            learningLanguage: word.learning_language,
            nativeLanguage: word.native_language
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    if let index = self.savedWords.firstIndex(where: { $0.id == word.id }) {
                        self.savedWords[index].is_known = newKnownStatus
                    }
                    self.savedWords.sort { word1, word2 in
                        if word1.is_known != word2.is_known {
                            return !word1.is_known
                        }
                        guard let date1 = word1.next_review_date else { return false }
                        guard let date2 = word2.next_review_date else { return true }
                        let formatter = ISO8601DateFormatter()
                        guard let d1 = formatter.date(from: date1),
                              let d2 = formatter.date(from: date2) else { return false }
                        return d1 < d2
                    }
                case .failure(let error):
                    self.errorMessage = "Failed to update word status: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
