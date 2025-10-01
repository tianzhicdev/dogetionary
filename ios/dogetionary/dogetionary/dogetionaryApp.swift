//
//  dogetionaryApp.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI
import UserNotifications
import BackgroundTasks

@main
struct dogetionaryApp: App {
    @Environment(\.scenePhase) var scenePhase

    init() {
        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared

        // Register background tasks
        BackgroundTaskManager.shared.registerBackgroundTasks()

        // Initialize analytics with new session
        AnalyticsManager.shared.newSession()
        AnalyticsManager.shared.track(action: .appLaunch)
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                // Start foreground timer when app becomes active
                BackgroundTaskManager.shared.startForegroundTimer()

                // Generate new session when app becomes active from background
                if oldPhase == .background || oldPhase == .inactive {
                    AnalyticsManager.shared.newSession()
                }

                AnalyticsManager.shared.track(action: .appForeground)
            case .background:
                // Schedule background refresh when entering background
                BackgroundTaskManager.shared.scheduleAppRefresh()
                BackgroundTaskManager.shared.stopForegroundTimer()
                AnalyticsManager.shared.track(action: .appBackground)
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
