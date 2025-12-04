//
//  AppConstants.swift
//  dogetionary
//
//  Central location for all app-wide constants
//  Eliminates magic numbers and improves maintainability
//

import Foundation

enum AppConstants {

    // MARK: - Network Timeouts

    enum Network {
        /// Standard network request timeout (30 seconds)
        static let standardTimeout: TimeInterval = 30.0

        /// Extended timeout for AI generation operations (60 seconds)
        static let aiGenerationTimeout: TimeInterval = 60.0
    }

    // MARK: - Validation Thresholds

    enum Validation {
        /// Minimum confidence score to consider a word valid (0.9)
        /// Words with score >= 0.9 are auto-saved
        /// Words with score < 0.9 trigger validation alert
        static let wordValidityThreshold: Double = 0.9

        /// Default pronunciation accuracy threshold (0.7)
        /// Pronunciation scores >= 0.7 are considered passing
        static let pronunciationThreshold: Double = 0.7
    }

    // MARK: - Animation Durations

    enum Animation {
        /// Standard animation duration in nanoseconds (300ms)
        static let standardDuration: UInt64 = 300_000_000

        /// Short animation duration in nanoseconds (200ms)
        static let shortDuration: UInt64 = 200_000_000

        /// Medium animation duration in nanoseconds (500ms)
        static let mediumDuration: UInt64 = 500_000_000

        /// Long animation duration in nanoseconds (1 second)
        static let longDuration: UInt64 = 1_000_000_000

        /// Spring animation response (0.3)
        static let springResponse: Double = 0.3

        /// Spring animation damping fraction (0.7)
        static let springDamping: Double = 0.7

        /// Short ease animation duration (0.2 seconds)
        static let easeShortDuration: Double = 0.2
    }

    // MARK: - UI Delays

    enum Delay {
        /// Delay before requesting app rating (1 second)
        static let appRatingDelay: UInt64 = 1_000_000_000

        /// Delay after animation completion (0.3 seconds)
        static let animationCompletion: UInt64 = 300_000_000

        /// Delay for badge dismissal (0.2 seconds)
        static let badgeDismissal: UInt64 = 200_000_000

        /// Delay for schedule refresh (0.5 seconds)
        static let scheduleRefresh: UInt64 = 500_000_000
    }

    // MARK: - Batch Sizes

    enum BatchSize {
        /// Number of questions to fetch per batch
        static let reviewQuestions = 10

        /// Maximum schedule days to display
        static let scheduleDays = 7
    }

    // MARK: - Version

    enum Version {
        /// Default app version fallback
        static let defaultVersion = "1.0.0"
    }
}
