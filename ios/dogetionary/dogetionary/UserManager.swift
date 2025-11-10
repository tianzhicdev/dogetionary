//
//  UserManager.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import Foundation
import os.log

class UserManager: ObservableObject {
    static let shared = UserManager()
    private let logger = Logger(subsystem: "com.dogetionary.app", category: "UserManager")
    private let userIDKey = "DogetionaryUserID"
    private let learningLanguageKey = "DogetionaryLearningLanguage"
    private let nativeLanguageKey = "DogetionaryNativeLanguage"
    private let userNameKey = "DogetionaryUserName"
    private let userMottoKey = "DogetionaryUserMotto"
    private let hasRequestedAppRatingKey = "DogetionaryHasRequestedAppRating"
    private let toeflEnabledKey = "DogetionaryToeflEnabled"
    private let ieltsEnabledKey = "DogetionaryIeltsEnabled"
    private let toeflTargetDaysKey = "DogetionaryToeflTargetDays"
    private let ieltsTargetDaysKey = "DogetionaryIeltsTargetDays"
    private let hasCompletedOnboardingKey = "DogetionaryHasCompletedOnboarding"

    internal var isSyncingFromServer = false

    @Published var hasCompletedOnboarding: Bool
    
    @Published var userID: String
    @Published var learningLanguage: String {
        didSet {
            UserDefaults.standard.set(learningLanguage, forKey: learningLanguageKey)
            if !isSyncingFromServer {
                syncPreferencesToServer()
            }
        }
    }
    @Published var nativeLanguage: String {
        didSet {
            UserDefaults.standard.set(nativeLanguage, forKey: nativeLanguageKey)
            if !isSyncingFromServer {
                syncPreferencesToServer()
            }
        }
    }
    @Published var userName: String {
        didSet {
            UserDefaults.standard.set(userName, forKey: userNameKey)
            if !isSyncingFromServer {
                syncPreferencesToServer()
            }
        }
    }
    @Published var userMotto: String {
        didSet {
            UserDefaults.standard.set(userMotto, forKey: userMottoKey)
            if !isSyncingFromServer {
                syncPreferencesToServer()
            }
        }
    }
    @Published var toeflEnabled: Bool {
        didSet {
            UserDefaults.standard.set(toeflEnabled, forKey: toeflEnabledKey)
            if !isSyncingFromServer {
                syncTestSettingsToServer()
            }
        }
    }
    @Published var ieltsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(ieltsEnabled, forKey: ieltsEnabledKey)
            if !isSyncingFromServer {
                syncTestSettingsToServer()
            }
        }
    }
    @Published var toeflTargetDays: Int {
        didSet {
            UserDefaults.standard.set(toeflTargetDays, forKey: toeflTargetDaysKey)
            if !isSyncingFromServer {
                syncTestSettingsToServer()
            }
        }
    }
    @Published var ieltsTargetDays: Int {
        didSet {
            UserDefaults.standard.set(ieltsTargetDays, forKey: ieltsTargetDaysKey)
            if !isSyncingFromServer {
                syncTestSettingsToServer()
            }
        }
    }
    
    private init() {
        // Try to load existing user ID from UserDefaults
        if let savedUserID = UserDefaults.standard.string(forKey: userIDKey) {
            self.userID = savedUserID
            logger.info("Loaded existing user ID: \(savedUserID)")
        } else {
            // Generate new UUID and save it
            let newUserID = UUID().uuidString
            self.userID = newUserID
            UserDefaults.standard.set(newUserID, forKey: userIDKey)
            logger.info("Generated new user ID: \(newUserID)")
        }

        // Load onboarding status
        #if DEBUG
        // In debug mode, check onboarding status from UserDefaults
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
        #else
        // In production, check if onboarding is completed
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
        #endif

        // Load language preferences or set defaults
        self.learningLanguage = UserDefaults.standard.string(forKey: learningLanguageKey) ?? "en"
        self.nativeLanguage = UserDefaults.standard.string(forKey: nativeLanguageKey) ?? "en"

        // Load user profile or set defaults
        self.userName = UserDefaults.standard.string(forKey: userNameKey) ?? ""
        self.userMotto = UserDefaults.standard.string(forKey: userMottoKey) ?? ""

        // Load test preparation settings or set defaults
        self.toeflEnabled = UserDefaults.standard.bool(forKey: toeflEnabledKey)
        self.ieltsEnabled = UserDefaults.standard.bool(forKey: ieltsEnabledKey)

        // Load target days with default of 30 days
        let savedToeflTargetDays = UserDefaults.standard.integer(forKey: toeflTargetDaysKey)
        self.toeflTargetDays = savedToeflTargetDays > 0 ? savedToeflTargetDays : 30
        let savedIeltsTargetDays = UserDefaults.standard.integer(forKey: ieltsTargetDaysKey)
        self.ieltsTargetDays = savedIeltsTargetDays > 0 ? savedIeltsTargetDays : 30

        logger.info("Loaded preferences - Learning: \(self.learningLanguage), Native: \(self.nativeLanguage), Onboarding: \(self.hasCompletedOnboarding)")
    }
    
    func getUserID() -> String {
        return userID
    }
    
    private func syncPreferencesToServer() {
        logger.info("Syncing preferences to server - Learning: \(self.learningLanguage), Native: \(self.nativeLanguage)")

        // Convert UserManager's test prep properties to API format
        let testPrep: String? = {
            if self.toeflEnabled {
                return "TOEFL"
            } else if self.ieltsEnabled {
                return "IELTS"
            } else {
                return nil
            }
        }()

        // Always send study duration days to keep settings in sync, even when test prep is disabled
        // Use toeflTargetDays as the source since both should be kept in sync
        let studyDurationDays: Int? = self.toeflTargetDays

        DictionaryService.shared.updateUserPreferences(
            userID: self.userID,
            learningLanguage: self.learningLanguage,
            nativeLanguage: self.nativeLanguage,
            userName: self.userName,
            userMotto: self.userMotto,
            testPrep: testPrep,
            studyDurationDays: studyDurationDays
        ) { result in
            switch result {
            case .success(_):
                self.logger.info("Successfully synced preferences to server")
            case .failure(let error):
                self.logger.error("Failed to sync preferences to server: \(error.localizedDescription)")
            }
        }
    }

    private func syncTestSettingsToServer() {
        logger.info("Syncing test settings to server - TOEFL: \(self.toeflEnabled) (\(self.toeflTargetDays) days), IELTS: \(self.ieltsEnabled) (\(self.ieltsTargetDays) days)")

        DictionaryService.shared.updateTestSettings(
            userID: self.userID,
            toeflEnabled: self.toeflEnabled,
            ieltsEnabled: self.ieltsEnabled,
            toeflTargetDays: self.toeflTargetDays,
            ieltsTargetDays: self.ieltsTargetDays
        ) { result in
            switch result {
            case .success(_):
                self.logger.info("Successfully synced test settings to server")
            case .failure(let error):
                self.logger.error("Failed to sync test settings to server: \(error.localizedDescription)")
            }
        }
    }

    func syncTestSettingsFromServer() {
        logger.info("Syncing test settings from server for user: \(self.userID)")

        DictionaryService.shared.getTestSettings(userID: self.userID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.logger.info("Successfully fetched test settings from server: toefl=\(response.settings.toefl_enabled), ielts=\(response.settings.ielts_enabled)")

                    // Update local settings if they're different from server
                    if self.toeflEnabled != response.settings.toefl_enabled ||
                       self.ieltsEnabled != response.settings.ielts_enabled ||
                       self.toeflTargetDays != response.settings.toefl_target_days ||
                       self.ieltsTargetDays != response.settings.ielts_target_days {
                        self.logger.info("Updating local test settings to match server")

                        // Set flag to prevent sync loop
                        self.isSyncingFromServer = true

                        // Update published properties
                        self.toeflEnabled = response.settings.toefl_enabled
                        self.ieltsEnabled = response.settings.ielts_enabled
                        self.toeflTargetDays = response.settings.toefl_target_days
                        self.ieltsTargetDays = response.settings.ielts_target_days

                        // Reset flag
                        self.isSyncingFromServer = false
                    }
                case .failure(let error):
                    self.logger.error("Failed to fetch test settings from server: \(error.localizedDescription)")
                }
            }
        }
    }

    func syncPreferencesFromServer() {
        logger.info("Syncing preferences from server for user: \(self.userID)")
        
        DictionaryService.shared.getUserPreferences(userID: self.userID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let preferences):
                    self.logger.info("Successfully fetched preferences from server: learning=\(preferences.learning_language), native=\(preferences.native_language)")
                    
                    // Update local preferences if they're different from server
                    if self.learningLanguage != preferences.learning_language || 
                       self.nativeLanguage != preferences.native_language ||
                       self.userName != (preferences.user_name ?? "") ||
                       self.userMotto != (preferences.user_motto ?? "") {
                        self.logger.info("Updating local preferences to match server")
                        
                        // Set flag to prevent sync loop
                        self.isSyncingFromServer = true
                        
                        // Update published properties - the didSet will update UserDefaults but skip server sync
                        self.learningLanguage = preferences.learning_language
                        self.nativeLanguage = preferences.native_language
                        self.userName = preferences.user_name ?? ""
                        self.userMotto = preferences.user_motto ?? ""
                        
                        // Reset flag
                        self.isSyncingFromServer = false
                    }
                case .failure(let error):
                    self.logger.error("Failed to fetch preferences from server: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - App Rating Management

    var hasRequestedAppRating: Bool {
        return UserDefaults.standard.bool(forKey: hasRequestedAppRatingKey)
    }

    func markAppRatingRequested() {
        UserDefaults.standard.set(true, forKey: hasRequestedAppRatingKey)
        logger.info("Marked app rating as requested")
    }

    // MARK: - Onboarding Management

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
        logger.info("Marked onboarding as completed")
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.set(false, forKey: hasCompletedOnboardingKey)
        logger.info("Reset onboarding status")
    }
}
