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
    // V3 API keys
    private let testTypeKey = "DogetionaryTestType"
    private let targetDaysKey = "DogetionaryTargetDays"
    // Legacy keys (kept for backward compatibility during transition)
    private let toeflEnabledKey = "DogetionaryToeflEnabled"
    private let ieltsEnabledKey = "DogetionaryIeltsEnabled"
    private let tianzEnabledKey = "DogetionaryTianzEnabled"
    private let toeflTargetDaysKey = "DogetionaryToeflTargetDays"
    private let ieltsTargetDaysKey = "DogetionaryIeltsTargetDays"
    private let tianzTargetDaysKey = "DogetionaryTianzTargetDays"
    private let hasCompletedOnboardingKey = "DogetionaryHasCompletedOnboarding"
    private let reminderTimeKey = "DogetionaryReminderTime"

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

    // MARK: - V3 API Test Preparation Properties

    /// Active test type (V3 API format)
    @Published var activeTestType: TestType? {
        didSet {
            if let testType = activeTestType {
                UserDefaults.standard.set(testType.rawValue, forKey: testTypeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: testTypeKey)
            }
            if !isSyncingFromServer {
                syncTestSettingsToServer()
                // Create schedule when test type changes
                if let testType = activeTestType, oldValue != activeTestType {
                    createScheduleForTestType(testType.rawValue, targetDays: targetDays)
                }
                // Sync legacy properties for backward compatibility
                updateLegacyPropertiesFromActive()
            }
        }
    }

    /// Target days for study plan (V3 API format)
    @Published var targetDays: Int {
        didSet {
            UserDefaults.standard.set(targetDays, forKey: targetDaysKey)
            if !isSyncingFromServer {
                syncTestSettingsToServer()
                // Recreate schedule if test is enabled and days changed
                if let testType = activeTestType, oldValue != targetDays {
                    createScheduleForTestType(testType.rawValue, targetDays: targetDays)
                }
                // Sync legacy properties for backward compatibility
                updateLegacyPropertiesFromActive()
            }
        }
    }

    // MARK: - Legacy Test Preparation Properties (deprecated)

    /// Legacy property for backward compatibility
    @Published var toeflEnabled: Bool {
        didSet {
            UserDefaults.standard.set(toeflEnabled, forKey: toeflEnabledKey)
            if !isSyncingFromServer {
                updateActiveFromLegacyProperties()
            }
        }
    }
    @Published var ieltsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(ieltsEnabled, forKey: ieltsEnabledKey)
            if !isSyncingFromServer {
                updateActiveFromLegacyProperties()
            }
        }
    }
    @Published var toeflTargetDays: Int {
        didSet {
            UserDefaults.standard.set(toeflTargetDays, forKey: toeflTargetDaysKey)
            if !isSyncingFromServer {
                updateActiveFromLegacyProperties()
            }
        }
    }
    @Published var ieltsTargetDays: Int {
        didSet {
            UserDefaults.standard.set(ieltsTargetDays, forKey: ieltsTargetDaysKey)
            if !isSyncingFromServer {
                updateActiveFromLegacyProperties()
            }
        }
    }
    @Published var tianzEnabled: Bool {
        didSet {
            UserDefaults.standard.set(tianzEnabled, forKey: tianzEnabledKey)
            if !isSyncingFromServer {
                updateActiveFromLegacyProperties()
            }
        }
    }
    @Published var tianzTargetDays: Int {
        didSet {
            UserDefaults.standard.set(tianzTargetDays, forKey: tianzTargetDaysKey)
            if !isSyncingFromServer {
                updateActiveFromLegacyProperties()
            }
        }
    }

    @Published var reminderTime: Date {
        didSet {
            UserDefaults.standard.set(reminderTime, forKey: reminderTimeKey)
            // Reschedule notification with new time
            NotificationManager.shared.scheduleDailyNotification(at: reminderTime)
        }
    }

    // MARK: - Helper Methods for Property Synchronization

    /// Update legacy properties based on active test type (for backward compatibility)
    private func updateLegacyPropertiesFromActive() {
        guard !isSyncingFromServer else { return }

        isSyncingFromServer = true
        defer { isSyncingFromServer = false }

        // Map active test type to legacy boolean flags
        if let testType = activeTestType {
            switch testType {
            case .toeflBeginner, .toeflIntermediate, .toeflAdvanced:
                toeflEnabled = true
                ieltsEnabled = false
                tianzEnabled = false
                toeflTargetDays = targetDays
            case .ieltsBeginner, .ieltsIntermediate, .ieltsAdvanced:
                toeflEnabled = false
                ieltsEnabled = true
                tianzEnabled = false
                ieltsTargetDays = targetDays
            case .tianz:
                toeflEnabled = false
                ieltsEnabled = false
                tianzEnabled = true
                tianzTargetDays = targetDays
            }
        } else {
            toeflEnabled = false
            ieltsEnabled = false
            tianzEnabled = false
        }
    }

    /// Update active test type based on legacy properties (for backward compatibility)
    private func updateActiveFromLegacyProperties() {
        guard !isSyncingFromServer else { return }

        isSyncingFromServer = true
        defer { isSyncingFromServer = false }

        // Map legacy boolean flags to active test type (default to advanced level)
        if toeflEnabled {
            activeTestType = .toeflAdvanced
            targetDays = toeflTargetDays
        } else if ieltsEnabled {
            activeTestType = .ieltsAdvanced
            targetDays = ieltsTargetDays
        } else if tianzEnabled {
            activeTestType = .tianz
            targetDays = tianzTargetDays
        } else {
            activeTestType = nil
        }
    }

    private init() {
        // Prevent didSet blocks from running during initialization
        isSyncingFromServer = true

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

        // Load onboarding status from UserDefaults
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)

        // Load language preferences or set defaults
        self.learningLanguage = UserDefaults.standard.string(forKey: learningLanguageKey) ?? "en"
        self.nativeLanguage = UserDefaults.standard.string(forKey: nativeLanguageKey) ?? "en"

        // Load user profile or set defaults
        self.userName = UserDefaults.standard.string(forKey: userNameKey) ?? ""
        self.userMotto = UserDefaults.standard.string(forKey: userMottoKey) ?? ""

        // Load reminder time with default of 9:00 AM (must be initialized first)
        if let savedReminderTime = UserDefaults.standard.object(forKey: reminderTimeKey) as? Date {
            self.reminderTime = savedReminderTime
        } else {
            // Default to 9:00 AM today
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = 9
            components.minute = 0
            self.reminderTime = Calendar.current.date(from: components) ?? Date()
        }

        // Load V3 API test preparation settings
        if let savedTestType = UserDefaults.standard.string(forKey: testTypeKey) {
            self.activeTestType = TestType(rawValue: savedTestType)
        } else {
            self.activeTestType = nil
        }
        let savedTargetDays = UserDefaults.standard.integer(forKey: targetDaysKey)
        self.targetDays = savedTargetDays > 0 ? savedTargetDays : 30

        // Load legacy test preparation settings (for backward compatibility)
        self.toeflEnabled = UserDefaults.standard.bool(forKey: toeflEnabledKey)
        self.ieltsEnabled = UserDefaults.standard.bool(forKey: ieltsEnabledKey)
        self.tianzEnabled = UserDefaults.standard.bool(forKey: tianzEnabledKey)

        // Load legacy target days with default of 30 days
        let savedToeflTargetDays = UserDefaults.standard.integer(forKey: toeflTargetDaysKey)
        self.toeflTargetDays = savedToeflTargetDays > 0 ? savedToeflTargetDays : 30
        let savedIeltsTargetDays = UserDefaults.standard.integer(forKey: ieltsTargetDaysKey)
        self.ieltsTargetDays = savedIeltsTargetDays > 0 ? savedIeltsTargetDays : 30
        let savedTianzTargetDays = UserDefaults.standard.integer(forKey: tianzTargetDaysKey)
        self.tianzTargetDays = savedTianzTargetDays > 0 ? savedTianzTargetDays : 30

        // If no V3 settings but have legacy settings, migrate from legacy
        if self.activeTestType == nil && (self.toeflEnabled || self.ieltsEnabled || self.tianzEnabled) {
            if self.toeflEnabled {
                self.activeTestType = .toeflAdvanced
                self.targetDays = self.toeflTargetDays
            } else if self.ieltsEnabled {
                self.activeTestType = .ieltsAdvanced
                self.targetDays = self.ieltsTargetDays
            } else if self.tianzEnabled {
                self.activeTestType = .tianz
                self.targetDays = self.tianzTargetDays
            }
        }

        // Re-enable property synchronization after initialization
        isSyncingFromServer = false

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
            } else if self.tianzEnabled {
                return "TIANZ"
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
        logger.info("Syncing test settings to server - Test Type: \(self.activeTestType?.rawValue ?? "nil"), Target Days: \(self.targetDays)")

        // Use V3 API format
        DictionaryService.shared.updateTestSettings(
            userID: self.userID,
            testType: self.activeTestType,
            targetDays: self.targetDays
        ) { result in
            switch result {
            case .success(_):
                self.logger.info("Successfully synced test settings to server")
                // Notify SavedWordsView to refresh schedule status
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .refreshSavedWords, object: nil)
                }
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
                    let serverTestType = response.settings.activeTestType
                    let serverTargetDays = response.settings.effectiveTargetDays

                    self.logger.info("Successfully fetched test settings from server: testType=\(serverTestType?.rawValue ?? "nil"), targetDays=\(serverTargetDays)")

                    // Update local settings if they're different from server
                    if self.activeTestType != serverTestType || self.targetDays != serverTargetDays {
                        self.logger.info("Updating local test settings to match server")

                        // Set flag to prevent sync loop
                        self.isSyncingFromServer = true

                        // Update V3 properties
                        self.activeTestType = serverTestType
                        self.targetDays = serverTargetDays

                        // Update legacy properties for backward compatibility
                        self.updateLegacyPropertiesFromActive()

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

    // MARK: - Schedule Management

    private func createScheduleForTestType(_ testType: String, targetDays: Int) {
        logger.info("Creating schedule for \(testType) with \(targetDays) target days")

        // Calculate target end date
        let calendar = Calendar.current
        guard let targetEndDate = calendar.date(byAdding: .day, value: targetDays, to: Date()) else {
            logger.error("Failed to calculate target end date")
            return
        }

        // Format as YYYY-MM-DD string (backend expects this format)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let targetEndDateString = formatter.string(from: targetEndDate)

        logger.info("Calling createSchedule API - testType: \(testType), targetEndDate: \(targetEndDateString)")

        DictionaryService.shared.createSchedule(testType: testType, targetEndDate: targetEndDateString) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.logger.info("Successfully created schedule: \(response.schedule.schedule_id)")
                case .failure(let error):
                    self.logger.error("Failed to create schedule: \(error.localizedDescription)")
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
