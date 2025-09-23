//
//  NotificationManager.swift
//  dogetionary
//
//  Created by AI Assistant on 9/16/25.
//

import Foundation
import UserNotifications

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isNotificationEnabled = false
    @Published var hasPermission = false

    private override init() {
        super.init()
        checkNotificationStatus()
    }

    func requestPermission(completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.hasPermission = granted
                self?.isNotificationEnabled = granted

                if granted {
                    print("✅ Notification permission granted")
                    self?.scheduleDailyNotification()
                } else {
                    print("❌ Notification permission denied")
                }

                completion(granted)
            }
        }
    }

    func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.hasPermission = settings.authorizationStatus == .authorized
                self?.isNotificationEnabled = settings.authorizationStatus == .authorized

                if settings.authorizationStatus == .authorized {
                    self?.scheduleDailyNotification()
                }
            }
        }
    }

    func scheduleDailyNotification() {
        // Cancel any existing notifications first
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-review-reminder"])

        // Create the notification content
        let content = UNMutableNotificationContent()
        content.title = "Time to Review! 📚"
        content.sound = .default
        content.categoryIdentifier = "REVIEW_REMINDER"

        // Set the trigger for 11:59 AM daily
        var dateComponents = DateComponents()
        dateComponents.hour = 11
        dateComponents.minute = 59

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        // Create the request
        let request = UNNotificationRequest(
            identifier: "daily-review-reminder",
            content: content,
            trigger: trigger
        )

        // Schedule the notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("✅ Daily notification scheduled for 11:59 AM")

                // Immediately check for overdue words to update the notification body
                self.updateNotificationWithOverdueCount()
            }
        }
    }

    func updateNotificationWithOverdueCount() {
        // Fetch overdue count from the API
        DictionaryService.shared.getDueCounts { result in
            switch result {
            case .success(let counts):
                if counts.overdue_count > 0 {
                    self.scheduleNotificationWithContent(overdueCount: counts.overdue_count)
                } else {
                    // Cancel notification if no words are overdue
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-review-reminder"])
                    print("📝 No overdue words, notification cancelled for today")
                }

            case .failure(let error):
                print("❌ Failed to fetch overdue count: \(error.localizedDescription)")
                // Still schedule a generic notification
                self.scheduleNotificationWithContent(overdueCount: nil)
            }
        }
    }

    private func scheduleNotificationWithContent(overdueCount: Int?) {
        // Cancel existing notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-review-reminder"])

        let content = UNMutableNotificationContent()
        content.title = "Time to Review! 📚"

        if let count = overdueCount {
            content.body = "Now is the best timing to review \(count) word\(count > 1 ? "s" : "") you saved"
        } else {
            content.body = "Now is the best timing to review your saved words"
        }

        content.sound = .default
        content.categoryIdentifier = "REVIEW_REMINDER"

        // Set the trigger for 11:59 AM
        var dateComponents = DateComponents()
        dateComponents.hour = 11
        dateComponents.minute = 59

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "daily-review-reminder",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error updating notification: \(error.localizedDescription)")
            } else {
                print("✅ Notification updated with overdue count: \(overdueCount ?? 0)")
            }
        }
    }

    // Method to manually trigger a test notification (for debugging)
    func triggerTestNotification() {
        updateNotificationWithOverdueCount()

        // Also fire an immediate test notification
        let content = UNMutableNotificationContent()
        content.title = "Test Notification 🧪"
        content.body = "This is a test of the review reminder system"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: "test-notification",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Test notification error: \(error.localizedDescription)")
            } else {
                print("✅ Test notification scheduled")
            }
        }
    }
}

// Extension to handle notification delegate methods
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap - could navigate to review view
        if response.notification.request.identifier == "daily-review-reminder" {
            // Post a notification that the app can listen to for navigation
            NotificationCenter.default.post(name: .shouldNavigateToReview, object: nil)
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let shouldNavigateToReview = Notification.Name("shouldNavigateToReview")
    static let wordAutoSaved = Notification.Name("wordAutoSaved")
    static let wordUnsaved = Notification.Name("wordUnsaved")
    static let refreshSavedWords = Notification.Name("refreshSavedWords")
}