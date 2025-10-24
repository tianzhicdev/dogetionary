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
    
    var body: some View {
        Form {
                #if DEBUG
                Section(header: Text("User Information")) {
                    HStack {
                        Text("User ID:")
                        Spacer()
                        Text(userManager.userID)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                #endif
                
                Section(header: Text("Profile")) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Enter your name", text: $userManager.userName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onSubmit {
                                    // Track profile name update
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
                                    // Track profile motto update
                                    AnalyticsManager.shared.track(action: .profileMottoUpdate, metadata: [
                                        "motto_length": userManager.userMotto.count
                                    ])
                                }
                        }
                    }
                }
                
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
                    
                    // Show current selection summary
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

                Section(header: Text("Test Preparation")) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Enable daily vocabulary practice for standardized tests")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        VStack(spacing: 12) {
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
                                        // Track test preparation changes
                                        AnalyticsManager.shared.track(action: .profileTestPrep, metadata: [
                                            "test_type": "toefl",
                                            "enabled": newValue
                                        ])
                                    }
                            }

                            if userManager.toeflEnabled {
                                HStack {
                                    Picker("complete in: ", selection: $userManager.toeflTargetDays) {
                                        ForEach([7, 14, 21, 30, 45, 60, 90], id: \.self) { days in
                                            Text("\(days) days")
                                                .tag(days)
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

                            Divider()

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
                                        // Track test preparation changes
                                        AnalyticsManager.shared.track(action: .profileTestPrep, metadata: [
                                            "test_type": "ielts",
                                            "enabled": newValue
                                        ])
                                    }
                            }

                            if userManager.ieltsEnabled {
                                HStack {
                                    Picker("complete in: ", selection: $userManager.ieltsTargetDays) {
                                        ForEach([7, 14, 21, 30, 45, 60, 90], id: \.self) { days in
                                            Text("\(days) days")
                                                .tag(days)
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

                        if userManager.toeflEnabled || userManager.ieltsEnabled {
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

                                Text("Shared: \(stats.words_in_both) words")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

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

                #if DEBUG
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
                                // This will trigger DictionaryService to use new URL
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
                #endif
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside text fields
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
