//
//  OnboardingStep.swift
//  dogetionary
//
//  Created by Claude on 10/8/25.
//

import Foundation

enum OnboardingStep: Int, CaseIterable {
    case dictionary = 0
    case savedWords = 1
    case review = 2
    case leaderboard = 3
    case settings = 4

    var title: String {
        switch self {
        case .dictionary:
            return "Search Words"
        case .savedWords:
            return "Saved Words"
        case .review:
            return "Review & Learn"
        case .leaderboard:
            return "Leaderboard"
        case .settings:
            return "Settings"
        }
    }

    var message: String {
        switch self {
        case .dictionary:
            return "Look up any word and get instant definitions, pronunciations, and examples."
        case .savedWords:
            return "View all words you've looked up in the past. Your personal vocabulary collection."
        case .review:
            return "Master your vocabulary with spaced repetition powered by the SuperMemo algorithm for maximum retention."
        case .leaderboard:
            return "See how you're doing compared to other learners around the world."
        case .settings:
            return "Customize your name, motto, or start building TOEFL/IELTS vocabulary lists."
        }
    }

    var buttonText: String {
        switch self {
        case .dictionary, .savedWords, .review, .leaderboard:
            return "Next"
        case .settings:
            return "Got it!"
        }
    }

    var targetTab: Int {
        switch self {
        case .dictionary:
            return 0
        case .savedWords:
            return 1
        case .review:
            return 2
        case .leaderboard:
            return 3
        case .settings:
            return 4
        }
    }

    func next() -> OnboardingStep? {
        let allCases = Self.allCases
        guard let currentIndex = allCases.firstIndex(of: self),
              currentIndex + 1 < allCases.count else {
            return nil
        }
        return allCases[currentIndex + 1]
    }
}
