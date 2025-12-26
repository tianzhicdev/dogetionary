//
//  ShojinApp.swift
//  TAT (The Alien Training)
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI
import UserNotifications
import AVFoundation

@main
struct TATApp: App {
    @Environment(\.scenePhase) var scenePhase

    init() {
        // Configure audio session for app (videos and audio playback)
        configureAudioSession()

        // Initialize debug configuration
        DebugConfig.setupDefaults()

        // Set up notification center delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared

        // Initialize analytics with new session
        AnalyticsManager.shared.newSession()
        AnalyticsManager.shared.track(action: .appLaunch)

        // Timezone is now synced automatically via UserManager.syncPreferencesToServer()
        // No need for separate syncTimezone() call

        // Clear and refresh question queue on app launch
        QuestionQueueManager.shared.forceRefresh()
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Allow Bluetooth routing and mixing with other apps
            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowBluetoothA2DP, .mixWithOthers]
            )
            try audioSession.setActive(true)
            print("✓ TATApp: Audio session configured for playback with Bluetooth support")
        } catch {
            print("❌ TATApp: Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                // Generate new session when app becomes active from background
                if oldPhase == .background || oldPhase == .inactive {
                    AnalyticsManager.shared.newSession()
                    // Refresh question queue when returning from background
                    QuestionQueueManager.shared.forceRefresh()
                }

                AnalyticsManager.shared.track(action: .appForeground)
            case .background:
                AnalyticsManager.shared.track(action: .appBackground)
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
