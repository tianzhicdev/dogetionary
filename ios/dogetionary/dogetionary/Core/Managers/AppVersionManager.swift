//
//  AppVersionManager.swift
//  dogetionary
//
//  Created by AI Assistant on 11/23/25.
//

import Foundation
import os.log

/// Manages app version checking and forced upgrade state
class AppVersionManager: ObservableObject {
    static let shared = AppVersionManager()
    private let logger = Logger(subsystem: "com.shojin.app", category: "AppVersionManager")

    @Published var requiresUpgrade: Bool = false
    @Published var upgradeURL: String = ""
    @Published var upgradeMessage: String?
    @Published var hasCheckedVersion: Bool = false

    private init() {}

    /// Check app version on launch
    func checkVersion() {
        logger.info("Checking app version: \(DictionaryService.appVersion)")

        DictionaryService.shared.checkAppVersion { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                self.hasCheckedVersion = true

                switch result {
                case .success(let response):
                    self.logger.info("Version check result: \(response.status.rawValue)")

                    if response.status == .upgradeRequired {
                        self.requiresUpgrade = true
                        self.upgradeURL = response.upgrade_url ?? "https://apps.apple.com/app/unforgettable-dictionary/id6714451841"
                        self.upgradeMessage = response.message
                        self.logger.warning("Forced upgrade required - current: \(DictionaryService.appVersion), min: \(response.min_version ?? "unknown")")
                    } else {
                        self.requiresUpgrade = false
                        if response.status == .upgradeRecommended {
                            self.logger.info("Upgrade recommended but not required")
                            // Could show a non-blocking banner here in the future
                        }
                    }

                case .failure(let error):
                    // On error, allow app to continue (fail open)
                    self.logger.error("Version check failed: \(error.localizedDescription)")
                    self.requiresUpgrade = false
                }
            }
        }
    }
}
