//
//  DebugConfig.swift
//  dogetionary
//
//  Centralized developer mode configuration with runtime toggle.
//  Developer features are always compiled in but can be enabled/disabled by users.
//

import Foundation

class DebugConfig {
    // MARK: - UserDefaults Keys
    private static let developerModeKey = "developerModeEnabled"

    // MARK: - Main Developer Mode Toggle

    /// Master switch for all developer features
    /// Can be toggled at runtime in Settings
    static var isDeveloperModeEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: developerModeKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: developerModeKey)
        }
    }

    // MARK: - Setup

    /// Initialize developer mode config with default values
    /// Call this once at app launch
    static func setupDefaults() {
        if UserDefaults.standard.object(forKey: developerModeKey) == nil {
            // Default: OFF in production for privacy, but users can enable it
            isDeveloperModeEnabled = false
        }
    }

    // MARK: - Granular Feature Flags

    /// Show User ID in Settings
    static var showUserID: Bool {
        isDeveloperModeEnabled
    }

    /// Show API Configuration section in Settings
    static var showAPIConfig: Bool {
        isDeveloperModeEnabled
    }

    /// Enable debug logging
    static var enableDebugLogging: Bool {
        isDeveloperModeEnabled
    }

    /// Show debug menu items in UI
    static var showDebugMenu: Bool {
        isDeveloperModeEnabled
    }

    /// Show debug overlay/indicators in ContentView
    static var showDebugOverlay: Bool {
        isDeveloperModeEnabled
    }

    /// Show Demo test (testing-only vocabulary)
    static var showDemoTest: Bool {
        isDeveloperModeEnabled
    }

    /// Show Color Playground in Settings (live theme customization)
    static var showColorPlayground: Bool {
        isDeveloperModeEnabled
    }

    // MARK: - Helper Methods

    /// Reset all developer mode settings to defaults
    static func resetToDefaults() {
        isDeveloperModeEnabled = false
    }
}
