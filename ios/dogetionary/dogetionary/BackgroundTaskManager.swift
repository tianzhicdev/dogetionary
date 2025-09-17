//
//  BackgroundTaskManager.swift
//  dogetionary
//
//  Created by AI Assistant on 2025.
//

import Foundation
import BackgroundTasks
import UIKit
import os.log

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    private let logger = Logger(subsystem: "com.dogetionary.app", category: "BackgroundTask")

    private let refreshTaskIdentifier = "com.dogetionary.refresh"
    private let cachedOverdueCountKey = "DogetionaryCachedOverdueCount"
    private let lastCountUpdateKey = "DogetionaryLastCountUpdate"

    private init() {}

    // MARK: - Cache Management

    var cachedOverdueCount: Int {
        get { UserDefaults.standard.integer(forKey: cachedOverdueCountKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: cachedOverdueCountKey)
            updateAppBadge(newValue)
        }
    }

    var lastCountUpdate: Date? {
        get { UserDefaults.standard.object(forKey: lastCountUpdateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCountUpdateKey) }
    }

    // MARK: - Background Task Registration

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskIdentifier,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }

        logger.info("Registered background task: \(self.refreshTaskIdentifier)")
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour from now

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background refresh for 1 hour from now")
        } catch {
            logger.error("Could not schedule app refresh: \(error.localizedDescription)")
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh
        scheduleAppRefresh()

        // Create a task to fetch due counts
        let fetchTask = Task {
            await fetchAndUpdateDueCounts()
            task.setTaskCompleted(success: true)
        }

        // Handle expiration
        task.expirationHandler = {
            fetchTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: - Fetching and Updating

    @MainActor
    func fetchAndUpdateDueCounts() async {
        logger.info("Fetching due counts in background")

        await withCheckedContinuation { continuation in
            DictionaryService.shared.getDueCounts { result in
                switch result {
                case .success(let counts):
                    self.logger.info("Background fetch successful - Overdue: \(counts.overdue_count)")
                    self.cachedOverdueCount = counts.overdue_count
                    self.lastCountUpdate = Date()
                case .failure(let error):
                    self.logger.error("Background fetch failed: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    func updateDueCountsAfterReview() {
        logger.info("Updating due counts after review")

        DictionaryService.shared.getDueCounts { result in
            switch result {
            case .success(let counts):
                self.logger.info("Post-review update - Overdue: \(counts.overdue_count)")
                self.cachedOverdueCount = counts.overdue_count
                self.lastCountUpdate = Date()
            case .failure(let error):
                self.logger.error("Post-review update failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Badge Management

    private func updateAppBadge(_ count: Int) {
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = count
            self.logger.info("Updated app badge to: \(count)")
        }
    }

    func clearBadge() {
        cachedOverdueCount = 0
    }

    // MARK: - Timer for Foreground Updates

    private var foregroundTimer: Timer?

    func startForegroundTimer() {
        stopForegroundTimer()

        // Initial fetch
        Task {
            await fetchAndUpdateDueCounts()
        }

        // Schedule hourly updates
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task {
                await self.fetchAndUpdateDueCounts()
            }
        }

        logger.info("Started foreground timer for hourly updates")
    }

    func stopForegroundTimer() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        logger.info("Stopped foreground timer")
    }
}