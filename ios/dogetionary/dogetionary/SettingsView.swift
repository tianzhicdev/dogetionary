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
    @ObservedObject private var notificationManager = NotificationManager.shared
    
    private let availableLanguages = [
        ("af", "Afrikaans"),
        ("ar", "Arabic"),
        ("hy", "Armenian"),
        ("az", "Azerbaijani"),
        ("be", "Belarusian"),
        ("bs", "Bosnian"),
        ("bg", "Bulgarian"),
        ("ca", "Catalan"),
        ("zh", "Chinese"),
        ("hr", "Croatian"),
        ("cs", "Czech"),
        ("da", "Danish"),
        ("nl", "Dutch"),
        ("en", "English"),
        ("et", "Estonian"),
        ("fi", "Finnish"),
        ("fr", "French"),
        ("gl", "Galician"),
        ("de", "German"),
        ("el", "Greek"),
        ("he", "Hebrew"),
        ("hi", "Hindi"),
        ("hu", "Hungarian"),
        ("is", "Icelandic"),
        ("id", "Indonesian"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("kn", "Kannada"),
        ("kk", "Kazakh"),
        ("ko", "Korean"),
        ("lv", "Latvian"),
        ("lt", "Lithuanian"),
        ("mk", "Macedonian"),
        ("ms", "Malay"),
        ("mr", "Marathi"),
        ("mi", "Maori"),
        ("ne", "Nepali"),
        ("no", "Norwegian"),
        ("fa", "Persian"),
        ("pl", "Polish"),
        ("pt", "Portuguese"),
        ("ro", "Romanian"),
        ("ru", "Russian"),
        ("sr", "Serbian"),
        ("sk", "Slovak"),
        ("sl", "Slovenian"),
        ("es", "Spanish"),
        ("sw", "Swahili"),
        ("sv", "Swedish"),
        ("tl", "Tagalog"),
        ("ta", "Tamil"),
        ("th", "Thai"),
        ("tr", "Turkish"),
        ("uk", "Ukrainian"),
        ("ur", "Urdu"),
        ("vi", "Vietnamese"),
        ("cy", "Welsh")
    ]
    
    var body: some View {
        NavigationView {
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
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Motto")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Enter your motto", text: $userManager.userMotto)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }
                
                Section(header: Text("Language Preferences")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Spacer()
                            Picker("Learning Language", selection: learningLanguageBinding) {
                                ForEach(availableLanguages, id: \.0) { code, name in
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
                                ForEach(availableLanguages, id: \.0) { code, name in
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
                    if let learningLang = availableLanguages.first(where: { $0.0 == userManager.learningLanguage }),
                       let nativeLang = availableLanguages.first(where: { $0.0 == userManager.nativeLanguage }) {
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

                Section(header: Text("Notifications")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Daily Review Reminders")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Get notified at 11:59 AM when you have words ready for review")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(notificationManager.hasPermission ? "✅ Enabled" : "❌ Disabled")
                                .font(.caption)
                                .foregroundColor(notificationManager.hasPermission ? .green : .orange)
                        }

                        if !notificationManager.hasPermission {
                            Button("Enable Notifications") {
                                notificationManager.requestPermission()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        #if DEBUG
                        Button("Test Notification") {
                            notificationManager.triggerTestNotification()
                        }
                        .buttonStyle(.bordered)
                        #endif
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
                            .onChange(of: feedbackText) { _, newValue in
                                if newValue.count > 500 {
                                    feedbackText = String(newValue.prefix(500))
                                }
                            }

                        HStack {
                            Text("\(feedbackText.count)/500")
                                .font(.caption2)
                                .foregroundColor(feedbackText.count > 450 ? .orange : .secondary)

                            Spacer()

                            Button(action: submitFeedback) {
                                HStack {
                                    if isSubmittingFeedback {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "paperplane.fill")
                                    }
                                    Text(isSubmittingFeedback ? "Sending..." : "Submit")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(feedbackText.isEmpty || isSubmittingFeedback ? Color.gray.opacity(0.3) : Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .disabled(feedbackText.isEmpty || isSubmittingFeedback)
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
                #endif
            }
            .navigationTitle("Settings")
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
                    userManager.nativeLanguage = newValue
                }
            }
        )
    }
    
    private func getLanguageName(for code: String) -> String {
        return availableLanguages.first(where: { $0.0 == code })?.1 ?? code.uppercased()
    }
    
    private func submitFeedback() {
        guard !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSubmittingFeedback = true

        DictionaryService.shared.submitFeedback(feedback: feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)) { result in
            DispatchQueue.main.async {
                isSubmittingFeedback = false

                switch result {
                case .success:
                    feedbackAlertMessage = "Thank you for your feedback! We appreciate your input and will use it to improve Dogetionary."
                    showFeedbackAlert = true
                case .failure(let error):
                    feedbackAlertMessage = "Failed to submit feedback. Please try again later. Error: \(error.localizedDescription)"
                    showFeedbackAlert = true
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

extension Notification.Name {
    static let environmentChanged = Notification.Name("environmentChanged")
}

#Preview {
    SettingsView()
}
