//
//  OnboardingManager.swift
//  dogetionary
//
//  Created by Claude on 10/8/25.
//

import Foundation
import SwiftUI

class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    private let hasCompletedOnboardingKey = "DogetionaryHasCompletedOnboarding"
    private let currentOnboardingStepKey = "DogetionaryCurrentOnboardingStep"
    private let onboardingVersionKey = "DogetionaryOnboardingVersion"
    private let currentVersion = "1.0"

    @Published var shouldShowOnboarding: Bool
    @Published var currentStep: OnboardingStep

    private init() {
        #if DEBUG
        // In debug mode, always show onboarding for testing
        self.shouldShowOnboarding = true
        self.currentStep = .dictionary
        #else
        let completed = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)
        let version = UserDefaults.standard.string(forKey: onboardingVersionKey)

        // Show onboarding if not completed or version changed
        self.shouldShowOnboarding = !completed || version != currentVersion

        // Resume from saved step or start from beginning
        let savedStep = UserDefaults.standard.integer(forKey: currentOnboardingStepKey)
        self.currentStep = OnboardingStep(rawValue: savedStep) ?? .dictionary
        #endif
    }

    func advanceToNextStep() {
        if let nextStep = currentStep.next() {
            currentStep = nextStep
            saveCurrentStep()
        } else {
            completeOnboarding()
        }
    }

    func skipOnboarding() {
        completeOnboarding()
    }

    func completeOnboarding() {
        shouldShowOnboarding = false
        UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.set(currentVersion, forKey: onboardingVersionKey)
        UserDefaults.standard.removeObject(forKey: currentOnboardingStepKey)
    }

    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)
        UserDefaults.standard.removeObject(forKey: currentOnboardingStepKey)
        UserDefaults.standard.removeObject(forKey: onboardingVersionKey)
        shouldShowOnboarding = true
        currentStep = .dictionary
    }

    private func saveCurrentStep() {
        UserDefaults.standard.set(currentStep.rawValue, forKey: currentOnboardingStepKey)
    }
}
