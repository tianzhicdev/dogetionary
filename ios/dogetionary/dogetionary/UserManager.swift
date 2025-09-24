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
    
    private var isSyncingFromServer = false
    
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
        
        // Load language preferences or set defaults
        self.learningLanguage = UserDefaults.standard.string(forKey: learningLanguageKey) ?? "en"
        self.nativeLanguage = UserDefaults.standard.string(forKey: nativeLanguageKey) ?? "en"
        
        // Load user profile or set defaults
        self.userName = UserDefaults.standard.string(forKey: userNameKey) ?? ""
        self.userMotto = UserDefaults.standard.string(forKey: userMottoKey) ?? ""

        // Load test preparation settings or set defaults
        self.toeflEnabled = UserDefaults.standard.bool(forKey: toeflEnabledKey)
        self.ieltsEnabled = UserDefaults.standard.bool(forKey: ieltsEnabledKey)
        
        logger.info("Loaded preferences - Learning: \(self.learningLanguage), Native: \(self.nativeLanguage)")
    }
    
    func getUserID() -> String {
        return userID
    }
    
    private func syncPreferencesToServer() {
        logger.info("Syncing preferences to server - Learning: \(self.learningLanguage), Native: \(self.nativeLanguage)")
        
        DictionaryService.shared.updateUserPreferences(
            userID: self.userID,
            learningLanguage: self.learningLanguage,
            nativeLanguage: self.nativeLanguage,
            userName: self.userName,
            userMotto: self.userMotto
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
        logger.info("Syncing test settings to server - TOEFL: \(self.toeflEnabled), IELTS: \(self.ieltsEnabled)")

        DictionaryService.shared.updateTestSettings(
            userID: self.userID,
            toeflEnabled: self.toeflEnabled,
            ieltsEnabled: self.ieltsEnabled
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
                       self.ieltsEnabled != response.settings.ielts_enabled {
                        self.logger.info("Updating local test settings to match server")

                        // Set flag to prevent sync loop
                        self.isSyncingFromServer = true

                        // Update published properties
                        self.toeflEnabled = response.settings.toefl_enabled
                        self.ieltsEnabled = response.settings.ielts_enabled

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
}
