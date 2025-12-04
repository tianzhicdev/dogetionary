//
//  SettingsView.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//

import SwiftUI
import os.log

struct SettingsView: View {
    private static let logger = Logger(subsystem: "com.dogetionary.app", category: "Settings")
    @AppStorage("forceProduction") private var forceProduction: Bool = false
    @State private var connectionTestResult: String = ""
    @State private var isTestingConnection = false
    @State private var showLanguageAlert = false
    @State private var pendingLanguageChange: (type: String, value: String)?
    @State private var searchText: String = ""
    @State private var feedbackText: String = ""
    @State private var isSubmittingFeedback = false
    @State private var showFeedbackAlert = false
    @State private var feedbackAlertMessage = ""
    @ObservedObject private var userManager = UserManager.shared
    @State private var developerModeEnabled = DebugConfig.isDeveloperModeEnabled
    
    var body: some View {
        ZStack {
            // Soft blue gradient background
            AppTheme.secondaryGradient
                .ignoresSafeArea()

            Form {
                debugUserInfoSection
                profileSection
                languagePreferencesSection
                notificationsSection
                feedbackSection
                debugAPIConfigSection
                developerOptionsSection
            }
            .onTapGesture {
                // Dismiss keyboard when tapping outside text fields
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .scrollContentBackground(.hidden)
        }
        .alert("Invalid Language Selection", isPresented: $showLanguageAlert) {
            Button("OK") { }
        } message: {
            Text("Learning language and native language cannot be the same. Please choose different languages.")
        }
        .alert("Feedback", isPresented: $showFeedbackAlert) {
            Button("OK") {
                if feedbackAlertMessage.contains("Thank you") {
                    feedbackText = ""
                }
            }
        } message: {
            Text(feedbackAlertMessage)
        }
    }
    
    private var currentEnvironment: String {
        if forceProduction {
            return "Production (Forced)"
        } else {
            return Configuration.environment == .development ? "Development" : "Production"
        }
    }
    
    private var environmentColor: Color {
        if forceProduction {
            return .green
        } else {
            return Configuration.environment == .development ? .blue : .green
        }
    }
    
    private var learningLanguageBinding: Binding<String> {
        Binding(
            get: { userManager.learningLanguage },
            set: { newValue in
                if newValue == userManager.nativeLanguage {
                    showLanguageAlert = true
                } else {
                    // Track profile language learning update
                    AnalyticsManager.shared.track(action: .profileLanguageLearning, metadata: [
                        "old_language": userManager.learningLanguage,
                        "new_language": newValue
                    ])
                    userManager.learningLanguage = newValue
                }
            }
        )
    }
    
    private var nativeLanguageBinding: Binding<String> {
        Binding(
            get: { userManager.nativeLanguage },
            set: { newValue in
                if newValue == userManager.learningLanguage {
                    showLanguageAlert = true
                } else {
                    // Track profile language native update
                    AnalyticsManager.shared.track(action: .profileLanguageNative, metadata: [
                        "old_language": userManager.nativeLanguage,
                        "new_language": newValue
                    ])
                    userManager.nativeLanguage = newValue
                }
            }
        )
    }

    // MARK: - Form Sections

    @ViewBuilder
    private var debugUserInfoSection: some View {
        if DebugConfig.showUserID {
            Section(header: Text("Debug Info")) {
                HStack {
                    Text("User ID:")
                    Spacer()
                    Text(userManager.userID)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var profileSection: some View {
        Section(header:
            HStack {
                Text("Profile")
                    .foregroundStyle(
                        LinearGradient(colors: [Color.purple, Color.pink],
                                     startPoint: .leading, endPoint: .trailing)
                    )
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter your name", text: $userManager.userName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            AnalyticsManager.shared.track(action: .profileNameUpdate, metadata: [
                                "name_length": userManager.userName.count
                            ])
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Motto")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter your motto", text: $userManager.userMotto)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            AnalyticsManager.shared.track(action: .profileMottoUpdate, metadata: [
                                "motto_length": userManager.userMotto.count
                            ])
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var languagePreferencesSection: some View {
        Section(header:
            HStack {
                Text("Language Preferences")
                    .foregroundStyle(
                        LinearGradient(colors: [Color.blue, Color.cyan],
                                     startPoint: .leading, endPoint: .trailing)
                    )
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Picker("Learning Language", selection: learningLanguageBinding) {
                        ForEach(LanguageConstants.availableLanguages, id: \.0) { code, name in
                            HStack {
                                Text(name)
                                Text("(\(code.uppercased()))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .tint(.blue)
                }

                HStack {
                    Spacer()
                    Picker("Native Language", selection: nativeLanguageBinding) {
                        ForEach(LanguageConstants.availableLanguages, id: \.0) { code, name in
                            HStack {
                                Text(name)
                                Text("(\(code.uppercased()))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .tint(.blue)
                }
            }

            if let learningLang = LanguageConstants.availableLanguages.first(where: { $0.0 == userManager.learningLanguage }),
               let nativeLang = LanguageConstants.availableLanguages.first(where: { $0.0 == userManager.nativeLanguage }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Configuration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Learning \(learningLang.1) → Native \(nativeLang.1)")
                        .font(.footnote)
                        .foregroundColor(.blue)
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section(header:
            HStack {
                Text("Notifications")
                    .foregroundStyle(
                        LinearGradient(colors: [Color.orange, Color.pink],
                                     startPoint: .leading, endPoint: .trailing)
                    )
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Daily Reminder")
                        .font(.subheadline)
                    Spacer()
                    DatePicker("", selection: $userManager.reminderTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                Text("You'll receive a reminder to practice at this time each day")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                HStack {
                    Text("Timezone")
                        .font(.subheadline)
                    Spacer()
                    Text(TimeZone.current.identifier)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("Timezone is automatically detected from your device")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        Section(header:
            HStack {
                Text("Feedback")
                    .foregroundStyle(
                        LinearGradient(colors: [Color.green, Color.mint],
                                     startPoint: .leading, endPoint: .trailing)
                    )
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Help us improve Unforgettable Dictionary")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Share your thoughts, suggestions, or report issues...", text: $feedbackText, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(3...6)

                HStack {
                    Text("\(feedbackText.count)/500")
                        .font(.caption2)
                        .foregroundColor(feedbackText.count > 450 ? .orange : .secondary)

                    Spacer()

                    if isSubmittingFeedback {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Submitting...")
                                .font(.caption)
                        }
                    } else {
                        Button("Submit") {
                            submitFeedback()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var debugAPIConfigSection: some View {
        if DebugConfig.showAPIConfig {
            Section(header: Text("API Configuration")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Current Environment:")
                        Spacer()
                        Text(currentEnvironment)
                            .fontWeight(.medium)
                            .foregroundColor(environmentColor)
                    }

                    Text("Base URL: \(Configuration.effectiveBaseURL)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if Configuration.environment == .development {
                    Toggle("Force Production Mode", isOn: $forceProduction)
                        .onChange(of: forceProduction) { _, newValue in
                            AppState.shared.notifyEnvironmentChanged()
                        }
                }
            }

            Section(header: Text("Environment Info")) {
                HStack {
                    Text("Build Configuration:")
                    Spacer()
                    Text("Debug")
                        .foregroundColor(.orange)
                }

                HStack {
                    Text("Default Environment:")
                    Spacer()
                    Text(Configuration.environment == .development ? "Development" : "Production")
                        .foregroundColor(Configuration.environment == .development ? .blue : .green)
                }
            }

            Section(header: Text("Test Connection")) {
                Button(action: {
                    testConnection()
                }) {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 8)
                        }
                        Text(isTestingConnection ? "Testing..." : "Test API Connection")
                    }
                }
                .disabled(isTestingConnection)
                .foregroundColor(.blue)

                if !connectionTestResult.isEmpty {
                    HStack {
                        Image(systemName: connectionTestResult.contains("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(connectionTestResult.contains("✅") ? .green : .red)
                        Text(connectionTestResult)
                            .font(.caption)
                    }
                }
            }

            Section(header: Text("Reset Onboarding")) {
                Button(action: {
                    UserManager.shared.resetOnboarding()
                }) {
                    Text("Reset Onboarding")
                        .foregroundColor(.blue)
                }
            }
        }
    }

    @ViewBuilder
    private var developerOptionsSection: some View {
        Section(header:
            HStack {
                Text("Developer Options")
                    .foregroundStyle(
                        LinearGradient(colors: [Color.red, Color.orange],
                                     startPoint: .leading, endPoint: .trailing)
                    )
                    .fontWeight(.semibold)
            }
        ) {
            Toggle("Developer Mode", isOn: $developerModeEnabled)
                .onChange(of: developerModeEnabled) { _, newValue in
                    DebugConfig.isDeveloperModeEnabled = newValue
                    AnalyticsManager.shared.track(action: .settingsDeveloperMode, metadata: [
                        "enabled": newValue
                    ])
                }

            if developerModeEnabled {
                Text("Developer features enabled. User ID, API config, test vocabularies, and other debug info will be visible.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helper Methods

    private func submitFeedback() {
        Self.logger.debug("submitFeedback() called")
        Self.logger.debug("feedbackText: '\(self.feedbackText, privacy: .private)'")

        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        Self.logger.debug("trimmed: '\(trimmed, privacy: .private)'")

        guard !trimmed.isEmpty else {
            Self.logger.debug("trimmed is empty, returning")
            return
        }

        Self.logger.debug("Setting isSubmittingFeedback = true")
        isSubmittingFeedback = true

        Self.logger.debug("Calling DictionaryService.submitFeedback")
        DictionaryService.shared.submitFeedback(feedback: trimmed) { result in
            DispatchQueue.main.async {
                Self.logger.debug("Got result from submitFeedback")
                self.isSubmittingFeedback = false

                switch result {
                case .success:
                    Self.logger.info("Feedback submitted successfully")
                    self.feedbackAlertMessage = "Feedback submitted successfully!"
                    self.showFeedbackAlert = true
                case .failure(let error):
                    Self.logger.error("Feedback submission failed: \(error.localizedDescription, privacy: .public)")
                    self.feedbackAlertMessage = "Failed to submit feedback: \(error.localizedDescription)"
                    self.showFeedbackAlert = true
                }
            }
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = ""
        
        // Test with a simple word search
        DictionaryService.shared.searchWord("test") { result in
            DispatchQueue.main.async {
                isTestingConnection = false
                
                switch result {
                case .success(let definitions):
                    if !definitions.isEmpty {
                        connectionTestResult = "✅ Connection successful - API responding"
                    } else {
                        connectionTestResult = "⚠️ Connection OK but no data returned"
                    }
                case .failure(let error):
                    connectionTestResult = "❌ Connection failed: \(error.localizedDescription)"
                }
            }
        }
    }

}

#Preview {
    SettingsView()
}
