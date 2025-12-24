//
//  OnboardingView.swift
//  dogetionary
//
//  Created by biubiu on 10/24/25.
//

import SwiftUI
import os.log
import Lottie

struct OnboardingView: View {
    private static let logger = Logger(subsystem: "com.shojin.app", category: "Onboarding")
    @StateObject private var userManager = UserManager.shared
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) private var appState

    @State private var currentPage = 0
    private let selectedLearningLanguage = "en" // Hardcoded to English for now
    @State private var selectedNativeLanguage = "zh" // Default to Chinese
    @State private var selectedTestType: TestType? = .demo // Default to DEMO as requested
    private let selectedStudyDuration: Int = 30 // Default to 30 days (no longer user-configurable in onboarding)
    @State private var dailyTimeCommitment: Double = 30 // 10-480 minutes via slider
    @State private var vocabularyCounts: [TestType: VocabularyCountInfo] = [:]  // All test type counts
    @State private var searchWord = "unforgettable"
    @State private var isSubmitting = false
    @State private var isSearching = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var shouldDismiss = false
    @State private var searchedDefinitions: [Definition] = []

    var body: some View {
        NavigationView {
            ZStack {
                // Gradient background
                AppTheme.verticalGradient2
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress indicator
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Capsule()
                                .fill(index <= displayPageIndex ?
                                    AppTheme.gradient1 :
                                    LinearGradient(colors: [AppTheme.panelFill],
                                                 startPoint: .leading, endPoint: .trailing))
                                .frame(height: 4)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                    .padding(.bottom, 30)

                    // Page content
                    TabView(selection: $currentPage) {
                        // Page 0: Native Language (with globe lottie animation)
                        languageSelectionPage(
                            title: "WHAT IS YOUR NATIVE LANGUAGE?",
                            description: "CHOOSE YOUR NATIVE LANGUAGE FOR TRANSLATIONS",
                            lottieAnimation: "globe2",
                            selectedLanguage: $selectedNativeLanguage,
                            excludeLanguage: selectedLearningLanguage
                        )
                        .tag(0)

                        // Page 1: Test Prep (renamed to "Choose a program")
                        testPrepPage
                            .tag(1)

                        // Page 2: Daily Time Commitment
                        dailyTimeCommitmentPage
                            .tag(2)

                        // Declaration Page
                        declarationPage
                            .tag(declarationPageIndex)

                        // Motivation Page
                        searchWordPage
                            .tag(searchPageIndex)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentPage)

                    // Navigation buttons
                    HStack(spacing: 16) {
                        if currentPage > 0 {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    currentPage -= 1
                                }
                            } label: {
                                Label("BACK", systemImage: "arrow.left")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(AppTheme.panelFill)
                                    .cornerRadius(10)
                            }
                        }

                        Button {
                            handleNextButton()
                        } label: {
                            if isSubmitting || isSearching {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text(buttonTitle.uppercased())
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(AppTheme.selectableTint.opacity(0.6))
                                .cornerRadius(10)
                            } else {
                                if currentPage < totalPages - 1 {
                                    Label(buttonTitle.uppercased(), systemImage: "arrow.right")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(8)
                                        .background(canProceed ? AppTheme.selectableTint : AppTheme.panelFill)
                                        .cornerRadius(10)
                                } else {
                                    Text(buttonTitle.uppercased())
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(8)
                                        .background(canProceed ? AppTheme.selectableTint : AppTheme.panelFill)
                                        .cornerRadius(10)
                                }
                            }
                        }
                        .disabled(!canProceed || isSubmitting || isSearching)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("ERROR", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage.uppercased())
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: shouldDismiss) { _, dismiss in
            if dismiss {
                self.dismiss()
            }
        }
    }

    // MARK: - Language Selection Page

    private func languageSelectionPage(
        title: String,
        description: String,
        symbolName: String? = nil,
        lottieAnimation: String? = nil,
        selectedLanguage: Binding<String>,
        excludeLanguage: String
    ) -> some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                if let lottieAnimation = lottieAnimation {
                    LottieView(animation: .named(lottieAnimation))
                        .playing(loopMode: .loop)
                        .configure { lottieAnimationView in
                            // Mute audio for all Lottie animations in onboarding
                            lottieAnimationView.backgroundBehavior = .pauseAndRestore
                        }
//                        .frame(width: 200, height: 200)
                } else if let symbolName = symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 80))
                        .foregroundStyle(AppTheme.gradient1)
                }

                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.gradient1)
                    .fixedSize(horizontal: false, vertical: true)
                    
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            HStack {
                Spacer()
                Picker("SELECT LANGUAGE", selection: selectedLanguage) {
                    ForEach(LanguageConstants.availableLanguages.filter { $0.0 != excludeLanguage }, id: \.0) { language in
                        Text("\(language.1.uppercased()) (\(language.0.uppercased()))")
                            .tag(language.0)
                    }
                }
                .pickerStyle(.wheel)
                .preferredColorScheme(.dark)  // Force dark mode → white text
                .colorMultiply(AppTheme.selectableTint)  // Tint white → cyan
                Spacer()
            }

            Spacer()
        }
    }


    // MARK: - Test Prep Page

    private var testPrepPage: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Text("CHOOSE A PROGRAM")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.gradient1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            HStack {
                Spacer()
                Picker("SELECT TEST", selection: $selectedTestType) {
                    Text("NONE").tag(nil as TestType?)
                    ForEach(TestType.allCases, id: \.self) { testType in
                        if let count = vocabularyCounts[testType] {
                            Text("\(testType.displayName.uppercased()), \(count.total_words.formatAsWordCount())")
                                .tag(testType as TestType?)
                        } else {
                            Text(testType.displayName.uppercased())
                                .tag(testType as TestType?)
                        }
                    }
                }
                .pickerStyle(.wheel)
                .preferredColorScheme(.dark)  // Force dark mode → white text
                .colorMultiply(AppTheme.selectableTint)  // Tint white → cyan
                Spacer()
            }
        }
        .onAppear {
            // Fetch all vocabulary counts when page appears
            fetchAllVocabularyCounts()
        }
    }


    // MARK: - Daily Time Commitment Page

    private var dailyTimeCommitmentPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("HOW MUCH TIME CAN YOU COMMIT EVERYDAY?")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.gradient1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 32) {
                // Time display
                VStack(spacing: 8) {
                    Text(Int(dailyTimeCommitment).formatAsTimeCommitment())
                        .font(.system(size: 80, weight: .bold))
                        .foregroundStyle(AppTheme.gradient1)
                    Text(Int(dailyTimeCommitment) >= 60 ? "HOURS" : "MINUTES")
                        .font(.title2)
                        .foregroundColor(AppTheme.smallTitleText)
                }

                // Slider
                VStack(spacing: 8) {
                    Slider(value: $dailyTimeCommitment, in: 10...480, step: 5)
                        .tint(AppTheme.selectableTint)

                    HStack {
                        Text("10 MIN")
                            .font(.caption)
                            .foregroundColor(AppTheme.smallTextColor1)
                        Spacer()
                        Text("8 HOURS")
                            .font(.caption)
                            .foregroundColor(AppTheme.smallTextColor1)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()
        }
    }


    // MARK: - Declaration Page

    private var declarationPage: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Text("SPACED REPITITION")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.gradient1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            // Illustration image
            Image("declaration_illustration")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 350)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 16) {
                (Text("Your brain forgets in predictable patterns. SHOJIN tracks each word individually and prompts review at the ")
                    .foregroundColor(AppTheme.bodyText) +
                Text("precise moment")
                    .foregroundColor(AppTheme.selectableTint)
                    .fontWeight(.semibold) +
                Text(" when recall is challenging but still possible. This ")
                    .foregroundColor(AppTheme.bodyText) +
                Text("desirable difficulty")
                    .foregroundColor(AppTheme.selectableTint)
                    .fontWeight(.semibold) +
                Text(" transforms short-term memorization into permanent vocabulary—making your study time up to ")
                    .foregroundColor(AppTheme.bodyText) +
                Text("20×")
                    .foregroundColor(AppTheme.selectableTint)
                    .fontWeight(.semibold) +
                Text(" more efficient than traditional methods.")
                    .foregroundColor(AppTheme.bodyText))
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Motivation Page

    private var searchWordPage: some View {
        VStack(spacing: 60) {
            Spacer()

            // Logo
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: AppTheme.bigTitleText.opacity(0.3), radius: 15, x: 0, y: 8)

            // Motivation text
            (Text("This won't be easy.\nBut if you persist, you will achieve ")
                .foregroundColor(AppTheme.bodyText) +
            Text("mastery")
                .foregroundColor(AppTheme.accentPink)
                .fontWeight(.semibold) +
            Text(".")
                .foregroundColor(AppTheme.bodyText))
                .font(.title2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Helper Methods

    private var totalPages: Int {
        // Structure: Native, TestPrep, TimeCommitment, Declaration, Motivation = 5 pages
        return 5
    }

    private var declarationPageIndex: Int {
        return 3
    }

    private var searchPageIndex: Int {
        // Note: This is actually the motivation page index (variable name kept for compatibility)
        return 4
    }

    private var displayPageIndex: Int {
        return currentPage
    }

    private var canProceed: Bool {
        switch currentPage {
        case 0:
            // Native language page
            return !selectedNativeLanguage.isEmpty && selectedNativeLanguage != selectedLearningLanguage
        case 1:
            // Test prep page - always allows proceeding (default is DEMO)
            return true
        case 2:
            // Time commitment page
            return true // Slider always has a value
        case 3:
            // Declaration page
            return true
        case 4:
            // Motivation page
            return true
        default:
            return false
        }
    }

    private var buttonTitle: String {
        if currentPage == searchPageIndex {
            return "START"
        } else if currentPage == declarationPageIndex {
            return "GET STARTED"
        } else {
            return "NEXT"
        }
    }

    private func handleNextButton() {
        if currentPage < declarationPageIndex {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentPage += 1
            }
        } else if currentPage == declarationPageIndex {
            // Declaration page - submit onboarding data and advance to motivation page
            submitOnboarding()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentPage = searchPageIndex
            }
        } else if currentPage == searchPageIndex {
            // Motivation page - complete onboarding, dismiss, and navigate to practice
            userManager.completeOnboarding()
            AnalyticsManager.shared.track(action: .onboardingComplete, metadata: ["completed_full_flow": true])
            shouldDismiss = true
            // Navigate to practice mode after dismissing
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay to ensure dismiss completes
                appState.navigateToReview()
            }
        }
    }

    private func submitOnboarding() {
        let userId = userManager.getUserID()

        // Update local user manager immediately (optimistic update)
        userManager.isSyncingFromServer = true
        userManager.learningLanguage = selectedLearningLanguage
        userManager.nativeLanguage = selectedNativeLanguage
        userManager.userName = ""  // Empty string for backward compatibility
        userManager.activeTestType = selectedTestType
        userManager.targetDays = selectedStudyDuration
        userManager.isSyncingFromServer = false

        // Track analytics
        var metadata: [String: Any] = [
            "learning_language": selectedLearningLanguage,
            "native_language": selectedNativeLanguage
        ]
        if let testType = selectedTestType {
            metadata["test_type"] = testType.rawValue
            metadata["study_duration_days"] = selectedStudyDuration
        }
        AnalyticsManager.shared.track(action: .onboardingComplete, metadata: metadata)

        // Sync to server in background (non-blocking)
        DictionaryService.shared.updateUserPreferences(
            userID: userId,
            learningLanguage: selectedLearningLanguage,
            nativeLanguage: selectedNativeLanguage,
            userName: "",  // Empty string for backward compatibility
            userMotto: "",  // Empty string for backward compatibility
            testPrep: selectedTestType?.rawValue,
            studyDurationDays: selectedStudyDuration,
            dailyTimeCommitmentMinutes: Int(dailyTimeCommitment)
        ) { result in
            // Only handle errors, success is silent
            if case .failure(let error) = result {
                DispatchQueue.main.async {
                    Self.logger.warning("Background preference sync failed: \(error.localizedDescription, privacy: .public)")
                    // Don't show error to user - they've already moved on
                }
            }
        }
    }

    private func performSearch() {
        let trimmedWord = searchWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }

        // Mark onboarding as completed
        userManager.completeOnboarding()

        // Track search analytics
        AnalyticsManager.shared.track(action: .dictionarySearch, metadata: [
            "word": trimmedWord,
            "from_onboarding": true
        ])

        // Trigger search in SearchView via AppState
        AppState.shared.performSearch(query: trimmedWord)

        // Dismiss onboarding - SearchView will handle the actual search
        shouldDismiss = true
    }


    private func fetchAllVocabularyCounts() {
        let baseURL = Configuration.effectiveBaseURL
        // Fetch all test types using "ALL" shorthand
        guard let url = URL(string: "\(baseURL)/v3/api/test-vocabulary-count?test_type=ALL") else {
            Self.logger.error("Invalid URL for fetching all vocabulary counts")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                Self.logger.error("Error fetching all vocabulary counts: \(error.localizedDescription, privacy: .public)")
                return
            }

            guard let data = data else {
                Self.logger.warning("No data received for vocabulary counts")
                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(VocabularyCountResponse.self, from: data)

                DispatchQueue.main.async {
                    // Store all counts in the dictionary
                    self.vocabularyCounts = response.allCounts()
                    Self.logger.info("Fetched vocabulary counts for \(self.vocabularyCounts.count) test types")
                }
            } catch {
                Self.logger.error("Error decoding vocabulary counts: \(error.localizedDescription, privacy: .public)")
            }
        }.resume()
    }


}

#Preview {
    OnboardingView()
}
