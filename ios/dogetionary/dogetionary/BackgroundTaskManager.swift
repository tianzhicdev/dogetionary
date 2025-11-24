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

class BackgroundTaskManager: ObservableObject {
    static let shared = BackgroundTaskManager()
    private let logger = Logger(subsystem: "com.dogetionary.app", category: "BackgroundTask")

    private let refreshTaskIdentifier = "com.dogetionary.refresh"
    private let cachedPracticeCountKey = "DogetionaryCachedPracticeCount"
    private let lastCountUpdateKey = "DogetionaryLastCountUpdate"

    @Published var practiceCount: Int = 0

    private init() {
        // Load cached value on init
        practiceCount = UserDefaults.standard.integer(forKey: cachedPracticeCountKey)
    }

    // MARK: - Cache Management

    var cachedPracticeCount: Int {
        get { UserDefaults.standard.integer(forKey: cachedPracticeCountKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: cachedPracticeCountKey)
            DispatchQueue.main.async {
                self.practiceCount = newValue
            }
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

        // Create a task to fetch practice counts
        let fetchTask = Task {
            await fetchAndUpdatePracticeCounts()
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
    func fetchAndUpdatePracticeCounts() async {
        logger.info("Fetching practice status in background")

        await withCheckedContinuation { continuation in
            DictionaryService.shared.getPracticeStatus { result in
                switch result {
                case .success(let status):
                    let totalCount = status.new_words_count + status.test_practice_count + status.non_test_practice_count
                    self.logger.info("Background fetch successful - Practice count: \(totalCount)")
                    self.cachedPracticeCount = totalCount
                    self.lastCountUpdate = Date()
                case .failure(let error):
                    self.logger.error("Background fetch failed: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }

    func updatePracticeCountsAfterReview() {
        logger.info("Updating practice counts after review")

        DictionaryService.shared.getPracticeStatus { result in
            switch result {
            case .success(let status):
                let totalCount = status.new_words_count + status.test_practice_count + status.non_test_practice_count
                self.logger.info("Post-review update - Practice count: \(totalCount)")
                self.cachedPracticeCount = totalCount
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
        cachedPracticeCount = 0
    }

    // MARK: - Timer for Foreground Updates

    private var foregroundTimer: Timer?

    func startForegroundTimer() {
        stopForegroundTimer()

        // Initial fetch
        Task {
            await fetchAndUpdatePracticeCounts()
        }

        // Schedule hourly updates
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            Task {
                await self.fetchAndUpdatePracticeCounts()
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