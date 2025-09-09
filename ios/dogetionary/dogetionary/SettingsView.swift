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
    
    var body: some View {
        NavigationView {
            Form {
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