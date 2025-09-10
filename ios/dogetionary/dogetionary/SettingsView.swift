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
    @ObservedObject private var userManager = UserManager.shared
    
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
                Section(header: Text("User Information")) {
                    HStack {
                        Text("User ID:")
                        Spacer()
                        Text(userManager.userID)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Language Preferences")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Learning")
                                .foregroundColor(.secondary)
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
                            Text("Native")
                                .foregroundColor(.secondary)
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
                        #if DEBUG
                        Text("Debug")
                            .foregroundColor(.orange)
                        #else
                        Text("Release")
                            .foregroundColor(.green)
                        #endif
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
            }
            .navigationTitle("Settings")
            .alert("Invalid Language Selection", isPresented: $showLanguageAlert) {
                Button("OK") { }
            } message: {
                Text("Learning language and native language cannot be the same. Please choose different languages.")
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
