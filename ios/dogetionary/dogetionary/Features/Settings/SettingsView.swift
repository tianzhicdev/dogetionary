//
//  SettingsView.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//

import SwiftUI
import os.log

struct SettingsView: View {
    private static let logger = Logger(subsystem: "com.shojin.app", category: "Settings")
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
    @State private var videoCacheInfo: String = ""
    @State private var questionCacheInfo: String = ""
    @State private var showCacheClearAlert = false
    @State private var cacheClearMessage = ""
    @State private var vocabularyCounts: [TestType: VocabularyCountInfo] = [:]

    var body: some View {
        ZStack {
            // Soft blue gradient background
            AppTheme.verticalGradient2
                .ignoresSafeArea()

            Form {
                debugUserInfoSection
                profileSection
                languagePreferencesSection
                programSection
                dailyCommitmentSection
                notificationsSection
                cacheSection
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
        .alert("INVALID LANGUAGE SELECTION", isPresented: $showLanguageAlert) {
            Button("OK") { }
        } message: {
            Text("INVALID LANGUAGE SELECTION. PLEASE TRY AGAIN.")
        }
        .alert("FEEDBACK", isPresented: $showFeedbackAlert) {
            Button("OK") {
                if feedbackAlertMessage.contains("Thank you") || feedbackAlertMessage.contains("THANK YOU") {
                    feedbackText = ""
                }
            }
        } message: {
            Text(feedbackAlertMessage.uppercased())
        }
        .alert("CACHE", isPresented: $showCacheClearAlert) {
            Button("OK") { }
        } message: {
            Text(cacheClearMessage.uppercased())
        }
        .onAppear {
            updateCacheInfo()
            fetchAllVocabularyCounts()
        }
    }

    private var currentEnvironment: String {
        if forceProduction {
            return "PRODUCTION (FORCED)"
        } else {
            return Configuration.environment == .development ? "DEVELOPMENT" : "PRODUCTION"
        }
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
            Section(header: HStack {
                Text("USER INFO")
                    .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }) {
                HStack {
                    Text("ID:")
                        .foregroundColor(AppTheme.smallTitleText)
                    Spacer()
                    Text(userManager.userID.uppercased())
                        .font(.caption)
                        .foregroundColor(AppTheme.selectableTint)
                }
            }.listRowBackground(Color.clear)
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
                    
                    TextField("ENTER YOUR NAME", text: $userManager.userName)
                        .onSubmit {
                            AnalyticsManager.shared.track(action: .profileNameUpdate, metadata: [
                                "name_length": userManager.userName.count
                            ])
                        }
                        .padding(4)
                        .background(AppTheme.textFieldBackgroundColor)
                        .border(AppTheme.textFieldBorderColor).cornerRadius(4)
                        .foregroundColor(AppTheme.textFieldUserInput)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("MOTTO")
                        .font(.caption)
                        .foregroundColor(AppTheme.smallTextColor1)
                    TextField("ENTER YOUR MOTTO", text: $userManager.userMotto)
                        .onSubmit {
                            AnalyticsManager.shared.track(action: .profileMottoUpdate, metadata: [
                                "motto_length": userManager.userMotto.count
                            ])
                        }
                        .padding(4)
                        .background(AppTheme.textFieldBackgroundColor)
                        .border(AppTheme.textFieldBorderColor).cornerRadius(4)
                        .foregroundColor(AppTheme.textFieldUserInput)
                    
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
                    Picker("NATIVE LANGUAGE", selection: nativeLanguageBinding) {
                        ForEach(LanguageConstants.availableLanguages, id: \.0) { code, name in
                            HStack {
                                Text(name.uppercased())
                                Text("(\(code.uppercased()))")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.smallTitleText)
                            }
                            .tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .tint(AppTheme.selectableTint)
                    .foregroundColor(AppTheme.smallTitleText)
                }
            }
        }.listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var programSection: some View {
        Section(header:
            HStack {
                Text("PROGRAM")
                    .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Picker("PROGRAM", selection: $userManager.activeTestType) {
                        Text("NONE").tag(nil as TestType?)
                        ForEach(TestType.allCases, id: \.self) { testType in
                            if let count = vocabularyCounts[testType] {
                                Text("\(testType.displayName.uppercased()), \(formatWordCount(count.total_words))")
                                    .tag(testType as TestType?)
                            } else {
                                Text(testType.displayName.uppercased())
                                    .tag(testType as TestType?)
                            }
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .tint(AppTheme.selectableTint)
                    .foregroundColor(AppTheme.smallTitleText)
                    .onChange(of: userManager.activeTestType) { _, newValue in
                        // Track program change analytics
                        AnalyticsManager.shared.track(action: .settingsProgramChange, metadata: [
                            "new_program": newValue?.rawValue ?? "none"
                        ])
                    }
                }
            }
        }.listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var dailyCommitmentSection: some View {
        Section(header:
            HStack {
                Text("DAILY COMMITMENT")
                    .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // Time display
                VStack(spacing: 8) {
                    Text(formatTimeCommitment(minutes: userManager.dailyTimeCommitmentMinutes))
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(AppTheme.gradient1)
                    Text(userManager.dailyTimeCommitmentMinutes >= 60 ? "HOURS" : "MINUTES")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.smallTitleText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                // Slider
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(userManager.dailyTimeCommitmentMinutes) },
                            set: { userManager.dailyTimeCommitmentMinutes = Int($0) }
                        ),
                        in: 10...480,
                        step: 5
                    )
                    .tint(AppTheme.selectableTint)
                    .onChange(of: userManager.dailyTimeCommitmentMinutes) { _, newValue in
                        // Track daily commitment change
                        AnalyticsManager.shared.track(action: .settingsDailyCommitment, metadata: [
                            "minutes": newValue
                        ])
                    }

                    HStack {
                        Text("10 MIN")
                            .font(.caption)
                            .foregroundColor(AppTheme.smallTextColor1)
                        Spacer()
                        Text("8 HOURS")
                            .font(.caption)
                            .foregroundColor(AppTheme.smallTextColor1)
                    }
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
                        .preferredColorScheme(.dark)  // Force dark mode → white text
                        .colorMultiply(AppTheme.selectableTint)  // Tint white → cyan
                        
                }

                HStack {
                    Text("TIMEZONE")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.smallTitleText)
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
                TextField("", text: $feedbackText, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(4)
                    .background(AppTheme.textFieldBackgroundColor)
                    .border(AppTheme.textFieldBorderColor).cornerRadius(4)
                    .foregroundColor(AppTheme.textFieldUserInput)

                HStack {
                    Text("\(feedbackText.count)/500")
                        .font(.caption2)
                        .foregroundColor(AppTheme.smallTextColor1)

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
            Section(header: HStack {
                Text("API CONFIGURATION")
                    .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CURRENT ENVIRONMENT:")
                            .foregroundColor(AppTheme.smallTitleText)
                        Spacer()
                        Text(currentEnvironment)
                            .fontWeight(.medium)
                            .foregroundColor(AppTheme.selectableTint)
                    }

                    Text("BASE URL: \(Configuration.effectiveBaseURL.uppercased())")
                        .font(.caption)
                        .foregroundColor(AppTheme.smallTitleText)
                }

                if Configuration.environment == .development {
                    Toggle("FORCE PRODUCTION MODE", isOn: $forceProduction)
                        .tint(AppTheme.selectableTint)
                        .foregroundColor(AppTheme.smallTitleText)
                        .onChange(of: forceProduction) { _, newValue in
                            AppState.shared.notifyEnvironmentChanged()
                        }
                }
            }.listRowBackground(Color.clear)

            Section(header: HStack {
                Text("ENVIRONMENT INFO")
                    .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }) {
                HStack {
                    Text("BUILD CONFIGURATION:")
                        .foregroundColor(AppTheme.smallTitleText)
                    Spacer()
                    Text("DEBUG")
                        .foregroundColor(AppTheme.selectableTint)
                }

                HStack {
                    Text("DEFAULT ENVIRONMENT:")
                        .foregroundColor(AppTheme.smallTitleText)
                    Spacer()
                    Text(Configuration.environment == .development ? "DEVELOPMENT" : "PRODUCTION")
                        .foregroundColor(AppTheme.selectableTint)
                }
            }.listRowBackground(Color.clear)

            Section(header: HStack {
                Text("TEST CONNECTION")
                    .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }) {
                Button {
                    testConnection()
                } label: {
                    if isTestingConnection {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("TESTING...")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(AppTheme.selectableTint.opacity(0.6))
                        .cornerRadius(10)
                    } else {
                        Label("TEST API CONNECTION", systemImage: "network")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(AppTheme.selectableTint)
                            .cornerRadius(10)
                    }
                }
                .disabled(isTestingConnection)

                if !connectionTestResult.isEmpty {
                    HStack {
                        Image(systemName: connectionTestResult.contains("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(connectionTestResult.contains("✅") ? AppTheme.successColor : AppTheme.errorColor)
                        Text(connectionTestResult)
                            .font(.caption)
                            .foregroundColor(AppTheme.smallTitleText)
                    }
                }
            }.listRowBackground(Color.clear)

            Section(header: HStack {
                Text("RESET ONBOARDING")
                    .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }) {
                Button {
                    UserManager.shared.resetOnboarding()
                } label: {
                    Label("RESET ONBOARDING", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(AppTheme.selectableTint)
                        .cornerRadius(10)
                }
            }.listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var cacheSection: some View {
        Section(header:
            HStack {
                Text("CACHE")
                    .foregroundStyle(AppTheme.gradient1)
                    .fontWeight(.semibold)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !videoCacheInfo.isEmpty {
                    HStack {
                        Image(systemName: "video.fill")
                            .foregroundColor(AppTheme.selectableTint)
                        Text(videoCacheInfo)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.smallTitleText)
                    }
                }

                if !questionCacheInfo.isEmpty {
                    HStack {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundColor(AppTheme.selectableTint)
                        Text(questionCacheInfo)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.smallTitleText)
                    }
                }

                Button(action: {
                    clearAllCache()
                }) {
                    Label("CLEAR ALL CACHE", systemImage: "trash.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(AppTheme.errorColor)
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }.listRowBackground(Color.clear)
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
                .foregroundColor(AppTheme.smallTitleText)
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
                    self.feedbackAlertMessage = "FEEDBACK SUBMITTED SUCCESSFULLY!"
                    self.showFeedbackAlert = true
                case .failure(let error):
                    Self.logger.error("Feedback submission failed: \(error.localizedDescription, privacy: .public)")
                    self.feedbackAlertMessage = "FAILED TO SUBMIT FEEDBACK: \(error.localizedDescription.uppercased())"
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
                        connectionTestResult = "✅ CONNECTION SUCCESSFUL - API RESPONDING"
                    } else {
                        connectionTestResult = "⚠️ CONNECTION OK BUT NO DATA RETURNED"
                    }
                case .failure(let error):
                    connectionTestResult = "❌ CONNECTION FAILED: \(error.localizedDescription.uppercased())"
                }
            }
        }
    }

    private func updateCacheInfo() {
        // Update video cache info
        let (videoFileCount, videoSizeBytes) = VideoService.shared.getCacheInfo()
        if videoFileCount == 0 {
            videoCacheInfo = "NO CACHED VIDEOS"
        } else {
            let sizeMB = Double(videoSizeBytes) / 1024.0 / 1024.0
            videoCacheInfo = String(format: "%d VIDEO%@ (%.1f MB)", videoFileCount, videoFileCount == 1 ? "" : "S", sizeMB)
        }

        // Update question cache info
        let (questionFileCount, questionSizeBytes) = QuestionCacheManager.shared.getCacheInfo()
        if questionFileCount == 0 {
            questionCacheInfo = "NO CACHED QUESTIONS"
        } else {
            let sizeMB = Double(questionSizeBytes) / 1024.0 / 1024.0
            questionCacheInfo = String(format: "%d QUESTION%@ (%.1f MB)", questionFileCount, questionFileCount == 1 ? "" : "S", sizeMB)
        }
    }

    private func clearAllCache() {
        print("SettingsView: clearAllCache() called")

        var totalCleared = 0
        var errors: [String] = []

        // Clear video cache
        let videoResult = VideoService.shared.clearCache()
        switch videoResult {
        case .success(let count):
            print("SettingsView: Successfully cleared \(count) videos")
            totalCleared += count
        case .failure(let error):
            print("SettingsView: Failed to clear video cache: \(error)")
            errors.append("Videos: \(error.localizedDescription)")
        }

        // Clear question cache
        let questionResult = QuestionCacheManager.shared.clearCache()
        switch questionResult {
        case .success(let count):
            print("SettingsView: Successfully cleared \(count) questions")
            totalCleared += count
        case .failure(let error):
            print("SettingsView: Failed to clear question cache: \(error)")
            errors.append("Questions: \(error.localizedDescription)")
        }

        // Update cache info display
        updateCacheInfo()

        // Show result message
        if !errors.isEmpty {
            cacheClearMessage = "Failed to clear some caches: \(errors.joined(separator: ", "))"
        } else if totalCleared == 0 {
            cacheClearMessage = "Cache was already empty"
        } else {
            cacheClearMessage = "Successfully cleared \(totalCleared) cached item\(totalCleared == 1 ? "" : "s")"
        }

        print("SettingsView: Showing alert with message: \(cacheClearMessage)")
        showCacheClearAlert = true
    }

    private func fetchAllVocabularyCounts() {
        let baseURL = Configuration.effectiveBaseURL
        // Fetch all test types using "ALL" shorthand
        guard let url = URL(string: "\(baseURL)/v3/api/test-vocabulary-count?test_type=ALL") else {
            Self.logger.error("Invalid URL for fetching all vocabulary counts")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                Self.logger.error("Error fetching all vocabulary counts: \(error.localizedDescription, privacy: .public)")
                return
            }

            guard let data = data else {
                Self.logger.warning("No data received for vocabulary counts")
                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(VocabularyCountResponse.self, from: data)

                DispatchQueue.main.async {
                    // Store all counts in the dictionary
                    self.vocabularyCounts = response.allCounts()
                    Self.logger.info("Fetched vocabulary counts for \(self.vocabularyCounts.count) test types")
                }
            } catch {
                Self.logger.error("Error decoding vocabulary counts: \(error.localizedDescription, privacy: .public)")
            }
        }.resume()
    }

    /// Format word count for display (e.g., "1,247 words" or "3.5K words")
    private func formatWordCount(_ count: Int) -> String {
        if count >= 10000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fK words", k)
        } else if count >= 1000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            let formatted = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
            return "\(formatted) words"
        } else {
            return "\(count) words"
        }
    }

    /// Format time commitment display
    private func formatTimeCommitment(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)"
        } else {
            let hours = Double(minutes) / 60.0
            if hours == Double(Int(hours)) {
                return "\(Int(hours))"
            } else {
                return String(format: "%.1f", hours)
            }
        }
    }

}

#Preview {
    SettingsView()
}
