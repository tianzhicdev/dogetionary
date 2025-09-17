//
//  AnalyticsManager.swift
//  dogetionary
//
//  Created by AI Assistant on 9/17/25.
//

import Foundation
import UIKit

class AnalyticsManager: ObservableObject {
    static let shared = AnalyticsManager()

    private let baseURL: String
    private var sessionId: String
    private let appVersion: String

    private init() {
        self.baseURL = Configuration.effectiveBaseURL
        self.sessionId = UUID().uuidString
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        print("📊 Analytics initialized with session: \(sessionId.prefix(8))...")
    }

    // Generate new session ID (call when app launches)
    func newSession() {
        sessionId = UUID().uuidString
        print("📊 New analytics session: \(sessionId.prefix(8))...")
    }

    // Track user action
    func track(action: AnalyticsAction, metadata: [String: Any] = [:]) {
        let userID = UserManager.shared.getUserID()

        let payload: [String: Any] = [
            "user_id": userID,
            "action": action.rawValue,
            "metadata": metadata,
            "session_id": sessionId,
            "platform": "ios",
            "app_version": appVersion
        ]

        // Send analytics in background
        Task {
            await sendAnalytics(payload: payload)
        }

        print("📊 Tracked: \(action.rawValue) | Session: \(sessionId.prefix(8))... | Metadata: \(metadata)")
    }

    private func sendAnalytics(payload: [String: Any]) async {
        guard let url = URL(string: "\(baseURL)/analytics/track") else {
            print("❌ Invalid analytics URL")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    // Success - no logging needed for production
                } else {
                    print("❌ Analytics failed: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("❌ Analytics error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Analytics Actions Enum
enum AnalyticsAction: String, CaseIterable {
    // Dictionary actions
    case dictionarySearch = "dictionary_search"
    case dictionarySearchAudio = "dictionary_search_audio"
    case dictionarySave = "dictionary_save"
    case dictionaryAutoSave = "dictionary_auto_save"
    case dictionaryExampleAudio = "dictionary_example_audio"
    case dictionaryIllustration = "dictionary_illustration"

    // Word validation actions
    case validationInvalid = "validation_invalid"
    case validationAcceptSuggestion = "validation_accept_suggestion"
    case validationUseOriginal = "validation_use_original"
    case validationCancel = "validation_cancel"

    // Review actions
    case reviewStart = "review_start"
    case reviewAnswerCorrect = "review_answer_correct"
    case reviewAnswerIncorrect = "review_answer_incorrect"
    case reviewAudio = "review_audio"
    case reviewNext = "review_next"
    case reviewComplete = "review_complete"

    // Navigation actions
    case navTabDictionary = "nav_tab_dictionary"
    case navTabSaved = "nav_tab_saved"
    case navTabReview = "nav_tab_review"
    case navTabLeaderboard = "nav_tab_leaderboard"
    case navTabSettings = "nav_tab_settings"

    // Profile actions
    case profileNameUpdate = "profile_name_update"
    case profileMottoUpdate = "profile_motto_update"
    case profileLanguageLearning = "profile_language_learning"
    case profileLanguageNative = "profile_language_native"

    // Settings actions
    case settingsNotificationEnable = "settings_notification_enable"
    case settingsNotificationDisable = "settings_notification_disable"
    case settingsNotificationTime = "settings_notification_time"
    case settingsTimezoneUpdate = "settings_timezone_update"

    // Saved words actions
    case savedViewDetails = "saved_view_details"

    // Feedback actions
    case feedbackSubmit = "feedback_submit"

    // App lifecycle actions
    case appLaunch = "app_launch"
    case appBackground = "app_background"
    case appForeground = "app_foreground"
}
