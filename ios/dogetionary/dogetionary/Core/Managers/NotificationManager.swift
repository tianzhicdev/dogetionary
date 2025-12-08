//
//  NotificationManager.swift
//  dogetionary
//
//  Created by AI Assistant on 9/16/25.
//

import Foundation
import UserNotifications
import os.log

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isNotificationEnabled = false
    @Published var hasPermission = false

    private let logger = Logger(subsystem: "com.shojin.app", category: "Notifications")

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
                    self?.logger.info("Notification permission granted")
                    self?.scheduleDailyNotification()
                } else {
                    self?.logger.notice("Notification permission denied")
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

    func scheduleDailyNotification(at time: Date? = nil) {
        // Cancel any existing notifications first
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-review-reminder"])

        // Create the notification content
        let content = UNMutableNotificationContent()
        content.title = "Time to Review!"
        content.sound = .default
        content.categoryIdentifier = "REVIEW_REMINDER"

        // Get hour and minute from the provided time, or use UserManager's reminderTime
        let reminderTime = time ?? UserManager.shared.reminderTime
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: reminderTime)
        let minute = calendar.component(.minute, from: reminderTime)

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        // Create the request
        let request = UNNotificationRequest(
            identifier: "daily-review-reminder",
            content: content,
            trigger: trigger
        )

        // Schedule the notification
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Error scheduling notification: \(error.localizedDescription, privacy: .public)")
            } else {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                self?.logger.info("Daily notification scheduled for \(formatter.string(from: reminderTime), privacy: .public)")

                // Immediately check for overdue words to update the notification body
                self?.updateNotificationWithOverdueCount()
            }
        }
    }

    func updateNotificationWithOverdueCount() {
        // Fetch overdue count from the API
        DictionaryService.shared.getDueCounts { [weak self] result in
            switch result {
            case .success(let counts):
                if counts.overdue_count > 0 {
                    self?.scheduleNotificationWithContent(overdueCount: counts.overdue_count)
                } else {
                    // Cancel notification if no words are overdue
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["daily-review-reminder"])
                    self?.logger.info("No overdue words, notification cancelled for today")
                }

            case .failure(let error):
                self?.logger.error("Failed to fetch overdue count: \(error.localizedDescription, privacy: .public)")
                // Still schedule a generic notification
                self?.scheduleNotificationWithContent(overdueCount: nil)
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

        // Use user's configured reminder time
        let reminderTime = UserManager.shared.reminderTime
        let calendar = Calendar.current
        var dateComponents = DateComponents()
        dateComponents.hour = calendar.component(.hour, from: reminderTime)
        dateComponents.minute = calendar.component(.minute, from: reminderTime)

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "daily-review-reminder",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Error updating notification: \(error.localizedDescription, privacy: .public)")
            } else {
                self?.logger.info("Notification updated with overdue count: \(overdueCount ?? 0)")
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

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Test notification error: \(error.localizedDescription, privacy: .public)")
            } else {
                self?.logger.info("Test notification scheduled")
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
        // Handle notification tap - navigate to review view
        if response.notification.request.identifier == "daily-review-reminder" {
            Task { @MainActor in
                AppState.shared.navigateToReview()
            }
        }
        completionHandler()
    }
}

// Note: Notification names now replaced by AppState for cross-view communication
// Only legacy notification definitions that may still be in use are kept here
extension Notification.Name {
    // Legacy: Still used in some places, consider migrating to AppState
    static let shouldNavigateToReview = Notification.Name("shouldNavigateToReview")
}