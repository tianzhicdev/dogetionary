//
//  AppState.swift
//  dogetionary
//
//  Centralized app state management replacing NotificationCenter
//

import Foundation
import SwiftUI
import Observation

/// Centralized app state manager that replaces NotificationCenter for cross-view communication
/// Uses Swift's Observation framework for efficient state updates
@Observable
final class AppState {
    static let shared = AppState()

    // MARK: - Navigation State

    /// Trigger navigation to review view (e.g., from notification tap)
    var shouldNavigateToReview: Bool = false {
        didSet {
            if shouldNavigateToReview {
                // Auto-reset after navigation is triggered
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    shouldNavigateToReview = false
                }
            }
        }
    }

    // MARK: - Word Management State

    /// Recently unsaved word (triggers UI updates)
    var recentlyUnsavedWord: String? = nil {
        didSet {
            if recentlyUnsavedWord != nil {
                // Auto-clear after a short delay
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    recentlyUnsavedWord = nil
                }
            }
        }
    }

    /// Trigger to refresh saved words list
    var shouldRefreshSavedWords: Bool = false {
        didSet {
            if shouldRefreshSavedWords {
                // Auto-reset after refresh is triggered
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    shouldRefreshSavedWords = false
                }
            }
        }
    }

    // MARK: - Search State

    /// Search query from onboarding (triggers search in SearchView)
    var searchQueryFromOnboarding: String? = nil {
        didSet {
            if searchQueryFromOnboarding != nil {
                // Auto-clear after search is triggered
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    searchQueryFromOnboarding = nil
                }
            }
        }
    }

    // MARK: - Settings State

    /// Test settings changed flag (triggers re-fetch in relevant views)
    var testSettingsChanged: Bool = false {
        didSet {
            if testSettingsChanged {
                // Auto-reset after views respond
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    testSettingsChanged = false
                }
            }
        }
    }

    /// Environment changed flag (dev/staging/production)
    var environmentChanged: Bool = false {
        didSet {
            if environmentChanged {
                // Auto-reset after views respond
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    environmentChanged = false
                }
            }
        }
    }

    // MARK: - Action Methods (for clarity and discoverability)

    /// Mark a word as unsaved (replaces .wordUnsaved notification)
    @MainActor
    func markWordUnsaved(_ word: String) {
        recentlyUnsavedWord = word
        shouldRefreshSavedWords = true
    }

    /// Trigger navigation to review view (replaces .shouldNavigateToReview notification)
    @MainActor
    func navigateToReview() {
        shouldNavigateToReview = true
    }

    /// Request refresh of saved words list (replaces .refreshSavedWords notification)
    @MainActor
    func refreshSavedWords() {
        shouldRefreshSavedWords = true
    }

    /// Perform search from onboarding (replaces .performSearchFromOnboarding notification)
    @MainActor
    func performSearch(query: String) {
        searchQueryFromOnboarding = query
    }

    /// Notify that test settings changed (replaces .testSettingsChanged notification)
    @MainActor
    func notifyTestSettingsChanged() {
        testSettingsChanged = true
    }

    /// Notify that environment changed (replaces .environmentChanged notification)
    @MainActor
    func notifyEnvironmentChanged() {
        environmentChanged = true
    }

    // MARK: - Private Init (Singleton)

    private init() {}
}

// MARK: - SwiftUI Preview Helper

extension AppState {
    /// Create a mock instance for SwiftUI previews
    static func mock() -> AppState {
        return AppState.shared
    }
}
