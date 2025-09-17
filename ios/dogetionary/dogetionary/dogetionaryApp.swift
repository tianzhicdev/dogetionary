//
//  dogetionaryApp.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct dogetionaryApp: App {

    init() {
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
    }
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
