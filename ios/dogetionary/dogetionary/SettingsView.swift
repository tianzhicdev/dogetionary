//
//  SettingsView.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//

import SwiftUI

struct SettingsView: View {
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
    @State private var testProgress: TestProgressData?
    @State private var vocabularyStats: TestVocabularyStatistics?
    @State private var isLoadingTestStats = false
    @State private var developerModeEnabled = DebugConfig.isDeveloperModeEnabled
    
    var body: some View {
        ZStack {
            // Soft blue gradient background
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
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
        .onAppear {
            loadTestStatistics()
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
        Section(header: Text("Profile")) {
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
        Section(header: Text("Language Preferences")) {
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
        Section(header: Text("Notifications")) {
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
        Section(header: Text("Feedback")) {
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
                            NotificationCenter.default.post(name: .environmentChanged, object: nil)
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
        Section(header: Text("Developer Options")) {
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
        print("🔍 submitFeedback() called")
        print("🔍 feedbackText: '\(feedbackText)'")

        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🔍 trimmed: '\(trimmed)'")

        guard !trimmed.isEmpty else {
            print("🔍 trimmed is empty, returning")
            return
        }

        print("🔍 Setting isSubmittingFeedback = true")
        isSubmittingFeedback = true

        print("🔍 Calling DictionaryService.submitFeedback")
        DictionaryService.shared.submitFeedback(feedback: trimmed) { result in
            DispatchQueue.main.async {
                print("🔍 Got result from submitFeedback")
                self.isSubmittingFeedback = false

                switch result {
                case .success:
                    print("🔍 SUCCESS!")
                    self.feedbackAlertMessage = "Feedback submitted successfully!"
                    self.showFeedbackAlert = true
                case .failure(let error):
                    print("🔍 FAILURE: \(error)")
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

    @ViewBuilder
    private var tianzTestSection: some View {
        Divider()

        HStack {
            VStack(alignment: .leading) {
                Text("Tianz Test")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Testing vocabulary list (20 words)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $userManager.tianzEnabled)
                .labelsHidden()
                .onChange(of: userManager.tianzEnabled) { _, newValue in
                    // Mutually exclusive: disable others when Tianz is enabled
                    if newValue {
                        if userManager.toeflEnabled { userManager.toeflEnabled = false }
                        if userManager.ieltsEnabled { userManager.ieltsEnabled = false }
                    }

                    // Track test preparation changes
                    AnalyticsManager.shared.track(action: .profileTestPrep, metadata: [
                        "test_type": "tianz",
                        "enabled": newValue
                    ])
                }
        }

        if userManager.tianzEnabled {
            HStack {
                Picker("complete in: ", selection: $userManager.tianzTargetDays) {
                    ForEach([30, 40, 50, 60, 70], id: \.self) { days in
                        Text("\(days) days")
                            .tag(days)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .tint(.blue)
            }
        }

        if let progress = testProgress?.tianz, userManager.tianzEnabled {
            HStack {
                Text("Progress:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(progress.saved)/\(progress.total) words (\(String(format: "%.1f", progress.percentage))%)")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }

    @ViewBuilder
    private var testPreparationSection: some View {
        Section(header: Text("Test Preparation")) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose your test level for daily vocabulary practice")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Test type picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Test Level")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Picker("Test Level", selection: $userManager.activeTestType) {
                        Text("None").tag(nil as TestType?)
                        Divider()
                        Text("TOEFL Beginner").tag(TestType.toeflBeginner as TestType?)
                        Text("TOEFL Intermediate").tag(TestType.toeflIntermediate as TestType?)
                        Text("TOEFL Advanced").tag(TestType.toeflAdvanced as TestType?)
                        Divider()
                        Text("IELTS Beginner").tag(TestType.ieltsBeginner as TestType?)
                        Text("IELTS Intermediate").tag(TestType.ieltsIntermediate as TestType?)
                        Text("IELTS Advanced").tag(TestType.ieltsAdvanced as TestType?)
                        if DebugConfig.showTianzTest {
                            Divider()
                            Text("Tianz Test").tag(TestType.tianz as TestType?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.blue)
                    .onChange(of: userManager.activeTestType) { oldValue, newValue in
                        AnalyticsManager.shared.track(action: .profileTestPrep, metadata: [
                            "test_type": newValue?.rawValue ?? "none",
                            "enabled": newValue != nil
                        ])
                    }

                    if let testType = userManager.activeTestType {
                        Text(testTypeDescription(testType))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Target days picker (only show if test selected)
                if userManager.activeTestType != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Complete in:")
                                .font(.subheadline)
                            Picker("", selection: $userManager.targetDays) {
                                ForEach([30, 40, 50, 60, 70, 80, 90, 100], id: \.self) { days in
                                    Text("\(days) days").tag(days)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.blue)
                        }
                    }
                }

                // Progress (only show if test selected)
                if let testType = userManager.activeTestType,
                   let progress = testProgress?.progress(for: testType) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Progress:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(progress.saved)/\(progress.total) words (\(String(format: "%.1f", progress.percentage))%)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }

                dailyWordsSection

                vocabularyStatsSection

                if isLoadingTestStats {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading test statistics...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func testTypeDescription(_ testType: TestType) -> String {
        switch testType {
        case .toeflBeginner:
            return "Foundation TOEFL vocabulary (~796 words)"
        case .toeflIntermediate:
            return "Intermediate TOEFL vocabulary (~1,995 words, includes beginner)"
        case .toeflAdvanced:
            return "Complete TOEFL vocabulary (~4,874 words, all levels)"
        case .ieltsBeginner:
            return "Foundation IELTS vocabulary (~800 words)"
        case .ieltsIntermediate:
            return "Intermediate IELTS vocabulary (~2,000 words, includes beginner)"
        case .ieltsAdvanced:
            return "Complete IELTS vocabulary (~4,323 words, all levels)"
        case .tianz:
            return "Specialized Tianz test vocabulary"
        }
    }

    @ViewBuilder
    private var toeflTestSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("TOEFL Preparation")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Test of English as a Foreign Language")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $userManager.toeflEnabled)
                .labelsHidden()
                .onChange(of: userManager.toeflEnabled) { _, newValue in
                    if newValue {
                        if userManager.ieltsEnabled { userManager.ieltsEnabled = false }
                        if userManager.tianzEnabled { userManager.tianzEnabled = false }
                    }
                    AnalyticsManager.shared.track(action: .profileTestPrep, metadata: [
                        "test_type": "toefl",
                        "enabled": newValue
                    ])
                }
        }

        if userManager.toeflEnabled {
            HStack {
                Picker("complete in: ", selection: $userManager.toeflTargetDays) {
                    ForEach([30, 40, 50, 60, 70], id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .tint(.blue)
            }
        }

        if let progress = testProgress?.toefl, userManager.toeflEnabled {
            HStack {
                Text("Progress:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(progress.saved)/\(progress.total) words (\(String(format: "%.1f", progress.percentage))%)")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }

    @ViewBuilder
    private var ieltsTestSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("IELTS Preparation")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("International English Language Testing System")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $userManager.ieltsEnabled)
                .labelsHidden()
                .onChange(of: userManager.ieltsEnabled) { _, newValue in
                    if newValue {
                        if userManager.toeflEnabled { userManager.toeflEnabled = false }
                        if userManager.tianzEnabled { userManager.tianzEnabled = false }
                    }
                    AnalyticsManager.shared.track(action: .profileTestPrep, metadata: [
                        "test_type": "ielts",
                        "enabled": newValue
                    ])
                }
        }

        if userManager.ieltsEnabled {
            HStack {
                Picker("complete in: ", selection: $userManager.ieltsTargetDays) {
                    ForEach([30, 40, 50, 60, 70], id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .tint(.blue)
            }
        }

        if let progress = testProgress?.ielts, userManager.ieltsEnabled {
            HStack {
                Text("Progress:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(progress.saved)/\(progress.total) words (\(String(format: "%.1f", progress.percentage))%)")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }

    @ViewBuilder
    private var dailyWordsSection: some View {
        if userManager.toeflEnabled || userManager.ieltsEnabled || userManager.tianzEnabled {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Words")
                    .font(.caption)
                    .foregroundColor(.secondary)

                let dailyWordsText = buildDailyWordsText()
                Text(dailyWordsText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var vocabularyStatsSection: some View {
        if let stats = vocabularyStats {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vocabulary Database")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("TOEFL: \(stats.toefl_words) words")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Spacer()
                    Text("IELTS: \(stats.ielts_words) words")
                        .font(.caption2)
                        .foregroundColor(.green)
                }

                if let tianzWords = stats.tianz_words {
                    Text("Tianz: \(tianzWords) words")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func buildDailyWordsText() -> String {
        var parts: [String] = []

        if userManager.toeflEnabled, let progress = testProgress?.toefl, let stats = vocabularyStats {
            let remaining = max(0, stats.toefl_words - progress.saved)
            let dailyWords = max(1, Int(ceil(Double(remaining) / Double(userManager.toeflTargetDays))))
            parts.append("TOEFL: ~\(dailyWords)/day")
        }

        if userManager.ieltsEnabled, let progress = testProgress?.ielts, let stats = vocabularyStats {
            let remaining = max(0, stats.ielts_words - progress.saved)
            let dailyWords = max(1, Int(ceil(Double(remaining) / Double(userManager.ieltsTargetDays))))
            parts.append("IELTS: ~\(dailyWords)/day")
        }

        if userManager.tianzEnabled, let progress = testProgress?.tianz, let stats = vocabularyStats {
            let remaining = max(0, (stats.tianz_words ?? 0) - progress.saved)
            let dailyWords = max(1, Int(ceil(Double(remaining) / Double(userManager.tianzTargetDays))))
            parts.append("Tianz: ~\(dailyWords)/day")
        }

        if parts.isEmpty {
            return "Test vocabulary words are automatically added to your review list daily based on your target completion timeline"
        } else {
            return parts.joined(separator: ", ") + " words are automatically added daily to meet your target timeline"
        }
    }

    private func loadTestStatistics() {
        isLoadingTestStats = true

        // Load test settings and progress
        DictionaryService.shared.getTestSettings(userID: userManager.userID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    self.testProgress = response.progress
                case .failure(let error):
                    print("Failed to load test settings: \(error.localizedDescription)")
                }
            }
        }

        // Load vocabulary statistics
        DictionaryService.shared.getTestVocabularyStats() { result in
            DispatchQueue.main.async {
                self.isLoadingTestStats = false
                switch result {
                case .success(let response):
                    self.vocabularyStats = response.statistics
                case .failure(let error):
                    print("Failed to load vocabulary stats: \(error.localizedDescription)")
                }
            }
        }
    }
}

extension Notification.Name {
    static let environmentChanged = Notification.Name("environmentChanged")
}

#Preview {
    SettingsView()
}
