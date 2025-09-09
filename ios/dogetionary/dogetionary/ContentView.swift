//
//  ContentView.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var userManager = UserManager.shared
    
    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Dictionary")
                }
            
            SavedWordsView()
                .tabItem {
                    Image(systemName: "bookmark.fill")
                    Text("Saved")
                }
            
            ReviewView()
                .tabItem {
                    Image(systemName: "brain.head.profile")
                    Text("Review")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
        .onAppear {
            // Initialize user manager to generate UUID if needed
            _ = userManager.getUserID()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
