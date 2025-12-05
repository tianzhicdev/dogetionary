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

    // Color Playground state
    @State private var debugPrimaryColor = AppTheme.getPrimaryColor()
    @State private var debugAccentColor = AppTheme.getAccentColor()
    @State private var debugBackgroundColor = AppTheme.getBackgroundColor()
    @State private var showColorExportSheet = false
    @State private var exportedColorCode = ""

    var body: some View {
        ZStack {
            // Soft blue gradient background
            AppTheme.verticalGradient2
                .ignoresSafeArea()

            Form {
                debugUserInfoSection
                profileSection
                languagePreferencesSection
                notificationsSection
                feedbackSection
                debugAPIConfigSection
                debugColorPlaygroundSection
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
                Text("PROFILE")
                .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NAME")
                        .font(.caption)
                        .foregroundColor(AppTheme.smallTextColor1)
                    
                    TextField("Enter your name", text: $userManager.userName)
                        .onSubmit {
                            AnalyticsManager.shared.track(action: .profileNameUpdate, metadata: [
                                "name_length": userManager.userName.count
                            ])
                        }
                        .padding(4)
                        .background(AppTheme.textFieldBackgroundColor)
                        .border(AppTheme.textFieldBorderColor).cornerRadius(4)
                        .foregroundColor(AppTheme.smallTextColor1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("MOTTO")
                        .font(.caption)
                        .foregroundColor(AppTheme.smallTextColor1)
                    TextField("Enter your motto", text: $userManager.userMotto)
                        .onSubmit {
                            AnalyticsManager.shared.track(action: .profileMottoUpdate, metadata: [
                                "motto_length": userManager.userMotto.count
                            ])
                        }
                        .padding(4)
                        .background(AppTheme.textFieldBackgroundColor)
                        .border(AppTheme.textFieldBorderColor).cornerRadius(4)
                        .foregroundColor(AppTheme.smallTextColor1)
                    
                }
            }
        }.listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var languagePreferencesSection: some View {
        Section(header:
            HStack {
                Text("LANGUAGE PREFERENCES")
                .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Picker("LEARNING LANGUAGE", selection: learningLanguageBinding) {
                        ForEach(LanguageConstants.availableLanguages, id: \.0) { code, name in
                            HStack {
                                Text(name)
                                Text("(\(code.uppercased()))")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.mediumTextColor1)
                            }
                            .tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .tint(AppTheme.selectableTint)
                    .foregroundColor(AppTheme.mediumTextColor1)
                }

                HStack {
                    Spacer()
                    Picker("NATIVE LANGUAGE", selection: nativeLanguageBinding) {
                        ForEach(LanguageConstants.availableLanguages, id: \.0) { code, name in
                            HStack {
                                Text(name)
                                Text("(\(code.uppercased()))")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.mediumTextColor1)
                            }
                            .tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .tint(AppTheme.selectableTint)
                    .foregroundColor(AppTheme.mediumTextColor1)
                }
            }
        }.listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section(header:
            HStack {
                Text("NOTIFICATIONS")
                    .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    DatePicker("", selection: $userManager.reminderTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                            .colorInvert()  // hack for dark backgrounds
                            .colorMultiply(AppTheme.selectableTint)
                        
                }

                HStack {
                    Text("TIMEZONE")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.mediumTextColor1)
                    Spacer()
                    Text(TimeZone.current.identifier.uppercased())
                        .font(.subheadline)
                        
                        .foregroundColor(AppTheme.selectableTint)
                }
            }
        }.listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var feedbackSection: some View {
        Section(header:
            HStack {
                Text("FEEDBACK")
                    .foregroundStyle(
                        AppTheme.gradient1
                    )
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Share your thoughts, suggestions, or report issues...", text: $feedbackText, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(4)
                    .background(AppTheme.textFieldBackgroundColor)
                    .border(AppTheme.textFieldBorderColor).cornerRadius(4)

                HStack {
                    Text("\(feedbackText.count)/500")
                        .font(.caption2)
                        .foregroundColor(feedbackText.count > 450 ? .orange : .secondary)

                    Spacer()

                    if isSubmittingFeedback {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    } else {
                        Button {
                            submitFeedback()
                        } label: {
                            Label("SEND ", systemImage: "paperplane.fill")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(AppTheme.selectableTint)
                                .cornerRadius(10)
                        }
                    }
                }
            }
        }.listRowBackground(Color.clear)
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
                        .foregroundColor(AppTheme.warningColor)
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
                .foregroundColor(AppTheme.infoColor)

                if !connectionTestResult.isEmpty {
                    HStack {
                        Image(systemName: connectionTestResult.contains("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(connectionTestResult.contains("✅") ? AppTheme.successColor : AppTheme.errorColor)
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
                        .foregroundColor(AppTheme.infoColor)
                }
            }
        }
    }

    @ViewBuilder
    private var debugColorPlaygroundSection: some View {
        if DebugConfig.showColorPlayground {
            Section(header: Text("Color Playground")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Experiment with theme colors in real-time. Changes are saved and persist across app restarts.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Primary Color Picker
                    ColorPicker("Primary Color", selection: $debugPrimaryColor)
                        .onChange(of: debugPrimaryColor) { _, newColor in
                            AppTheme.setDebugPrimaryColor(newColor)
                        }

                    // Accent Color Picker
                    ColorPicker("Accent Color", selection: $debugAccentColor)
                        .onChange(of: debugAccentColor) { _, newColor in
                            AppTheme.setDebugAccentColor(newColor)
                        }

                    // Background Color Picker
                    ColorPicker("Background Color", selection: $debugBackgroundColor)
                        .onChange(of: debugBackgroundColor) { _, newColor in
                            AppTheme.setDebugBackgroundColor(newColor)
                        }
                }

                // Reset Button
                Button(action: {
                    AppTheme.resetDebugColors()
                    debugPrimaryColor = AppTheme.getPrimaryColor()
                    debugAccentColor = AppTheme.getAccentColor()
                    debugBackgroundColor = AppTheme.getBackgroundColor()
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Defaults")
                    }
                }
                .foregroundColor(.orange)

                // Export Button
                Button(action: {
                    exportedColorCode = AppTheme.exportDebugColorsAsCode()
                    showColorExportSheet = true
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Export as Swift Code")
                    }
                }
                .foregroundColor(.blue)
                .sheet(isPresented: $showColorExportSheet) {
                    NavigationView {
                        ScrollView {
                            Text(exportedColorCode)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .textSelection(.enabled)
                        }
                        .navigationTitle("Color Code")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showColorExportSheet = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var developerOptionsSection: some View {
        Section(header:
            HStack {
                Text("DEVELOPER OPTIONS")
                    .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }
        ) {
            Toggle("DEVELOPER MODE", isOn: $developerModeEnabled)
                .tint(AppTheme.selectableTint)
                .foregroundColor(AppTheme.mediumTextColor1)
                .onChange(of: developerModeEnabled) { _, newValue in
                    DebugConfig.isDeveloperModeEnabled = newValue
                    AnalyticsManager.shared.track(action: .settingsDeveloperMode, metadata: [
                        "enabled": newValue
                    ])
                }
            
        }.listRowBackground(Color.clear)
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
