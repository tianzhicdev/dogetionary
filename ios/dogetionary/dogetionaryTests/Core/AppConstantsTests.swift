//
//  AppConstantsTests.swift
//  dogetionaryTests
//
//  Unit tests for AppConstants - ensuring constants are correctly defined
//

import XCTest
@testable import dogetionary

final class AppConstantsTests: XCTestCase {

    // MARK: - Network Constants Tests

    func testNetworkTimeouts_ArePositiveValues() {
        XCTAssertGreaterThan(AppConstants.Network.standardTimeout, 0)
        XCTAssertGreaterThan(AppConstants.Network.aiGenerationTimeout, 0)
    }

    func testAIGenerationTimeout_IsLongerThanStandardTimeout() {
        XCTAssertGreaterThan(
            AppConstants.Network.aiGenerationTimeout,
            AppConstants.Network.standardTimeout,
            "AI generation should have longer timeout than standard requests"
        )
    }

    // MARK: - Validation Threshold Tests

    func testValidationThresholds_AreBetweenZeroAndOne() {
        XCTAssertGreaterThanOrEqual(AppConstants.Validation.wordValidityThreshold, 0.0)
        XCTAssertLessThanOrEqual(AppConstants.Validation.wordValidityThreshold, 1.0)

        XCTAssertGreaterThanOrEqual(AppConstants.Validation.pronunciationThreshold, 0.0)
        XCTAssertLessThanOrEqual(AppConstants.Validation.pronunciationThreshold, 1.0)
    }

    func testWordValidityThreshold_IsHigherThanPronunciationThreshold() {
        XCTAssertGreaterThan(
            AppConstants.Validation.wordValidityThreshold,
            AppConstants.Validation.pronunciationThreshold,
            "Word validity should have stricter threshold than pronunciation"
        )
    }

    // MARK: - Animation Duration Tests

    func testAnimationDurations_ArePositiveValues() {
        XCTAssertGreaterThan(AppConstants.Animation.standardDuration, 0)
        XCTAssertGreaterThan(AppConstants.Animation.shortDuration, 0)
        XCTAssertGreaterThan(AppConstants.Animation.mediumDuration, 0)
        XCTAssertGreaterThan(AppConstants.Animation.longDuration, 0)
    }

    func testAnimationDurations_AreInCorrectOrder() {
        XCTAssertLessThan(
            AppConstants.Animation.shortDuration,
            AppConstants.Animation.standardDuration,
            "Short duration should be shorter than standard"
        )
        XCTAssertLessThan(
            AppConstants.Animation.standardDuration,
            AppConstants.Animation.mediumDuration,
            "Standard duration should be shorter than medium"
        )
        XCTAssertLessThan(
            AppConstants.Animation.mediumDuration,
            AppConstants.Animation.longDuration,
            "Medium duration should be shorter than long"
        )
    }

    func testAnimationDurations_ConvertToSeconds() {
        // Animation durations are in nanoseconds
        let standardInSeconds = Double(AppConstants.Animation.standardDuration) / 1_000_000_000

        XCTAssertEqual(standardInSeconds, 0.3, accuracy: 0.001, "Standard duration should be 300ms")
    }

    // MARK: - Spring Animation Tests

    func testSpringResponse_IsReasonableValue() {
        XCTAssertGreaterThan(AppConstants.Animation.springResponse, 0.1)
        XCTAssertLessThan(AppConstants.Animation.springResponse, 1.0)
    }

    func testSpringDamping_IsValidDampingValue() {
        // Damping should be between 0 (no damping) and 1 (critically damped)
        XCTAssertGreaterThan(AppConstants.Animation.springDamping, 0.0)
        XCTAssertLessThanOrEqual(AppConstants.Animation.springDamping, 1.0)
    }

    // MARK: - Delay Constants Tests

    func testDelays_ArePositiveValues() {
        XCTAssertGreaterThan(AppConstants.Delay.appRatingDelay, 0)
        XCTAssertGreaterThan(AppConstants.Delay.animationCompletion, 0)
        XCTAssertGreaterThan(AppConstants.Delay.badgeDismissal, 0)
        XCTAssertGreaterThan(AppConstants.Delay.scheduleRefresh, 0)
    }

    func testAppRatingDelay_IsAtLeastOneSecond() {
        let delayInSeconds = Double(AppConstants.Delay.appRatingDelay) / 1_000_000_000
        XCTAssertGreaterThanOrEqual(delayInSeconds, 1.0, "App rating should wait at least 1 second")
    }

    // MARK: - Version Tests

    func testDefaultVersion_IsValidSemanticVersion() {
        let version = AppConstants.Version.defaultVersion
        let versionComponents = version.split(separator: ".")

        XCTAssertEqual(versionComponents.count, 3, "Version should have major.minor.patch format")

        // Check each component is a valid number
        for component in versionComponents {
            XCTAssertNotNil(Int(component), "Version component should be numeric")
        }
    }

    // MARK: - Consistency Tests

    func testAnimationCompletionDelay_MatchesStandardDuration() {
        XCTAssertEqual(
            AppConstants.Delay.animationCompletion,
            AppConstants.Animation.standardDuration,
            "Animation completion delay should match standard animation duration"
        )
    }

    func testBadgeDismissalDelay_MatchesShortDuration() {
        XCTAssertEqual(
            AppConstants.Delay.badgeDismissal,
            AppConstants.Animation.shortDuration,
            "Badge dismissal should use short animation duration"
        )
    }
}

// MARK: - Performance Tests

extension AppConstantsTests {
    func testConstantsAccessPerformance() {
        measure {
            // Accessing constants should be extremely fast
            for _ in 0..<10000 {
                _ = AppConstants.Network.standardTimeout
                _ = AppConstants.Validation.wordValidityThreshold
                _ = AppConstants.Animation.standardDuration
            }
        }
    }
}
