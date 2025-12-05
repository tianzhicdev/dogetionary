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
    private static let logger = Logger(subsystem: "com.dogetionary.app", category: "Onboarding")
    @StateObject private var userManager = UserManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var currentPage = 0
    @State private var selectedLearningLanguage = "en"
    @State private var selectedNativeLanguage = "fr"
    @State private var selectedTestType: TestType? = nil // Level-based test selection
    @State private var selectedStudyDuration: Double = 30 // 1-365 days via slider
    @State private var vocabularyCount: Int = 0
    @State private var studyPlans: [(days: Int, wordsPerDay: Int)] = []
    @State private var isLoadingVocabulary = false
    @State private var vocabularyCounts: [TestType: VocabularyCountInfo] = [:]  // All test type counts
    @State private var userName: String = {
        let names = [
            "Vocabulary Ninja",
            "Word Wizard",
            "Dictionary Doge",
            "Lexicon Legend",
            "Vocab Viking",
            "Grammar Guru",
            "Spelling Senpai",
            "Word Nerd Supreme",
            "Captain Vocabulary",
            "The Wordinator",
            "Sir Learns-a-Lot",
            "Professor Vocab"
        ]
        return names.randomElement() ?? "Word Wizard"
    }()
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
                        // Page 0: Learning Language
                        languageSelectionPage(
                            title: "WHAT LANGUAGE ARE YOU LEARNING?",
                            description: "CHOOSE THE LANGUAGE YOU WANT TO LEARN AND IMPROVE",
                            lottieAnimation: "globe2",
                            selectedLanguage: $selectedLearningLanguage,
                            excludeLanguage: selectedNativeLanguage
                        )
                        .tag(0)

                        // Page 1: Native Language
                        languageSelectionPage(
                            title: "WHAT IS YOUR NATIVE LANGUAGE?",
                            description: "CHOOSE YOUR NATIVE LANGUAGE FOR TRANSLATIONS",
                            selectedLanguage: $selectedNativeLanguage,
                            excludeLanguage: selectedLearningLanguage
                        )
                        .tag(1)

                        // Page 2: Test Prep (only shown if learning English)
                        if selectedLearningLanguage == "en" {
                            testPrepPage
                                .tag(2)
                        }

                        // Page 3: Study Duration (only shown if TOEFL or IELTS selected)
                        if showDurationPage {
                            studyDurationPage
                                .tag(3)
                        }

                        // Username Page
                        usernamePage
                            .tag(usernamePageIndex)

                        // Schedule Preview Page (only if test prep enabled)
                        if showDurationPage {
                            schedulePreviewPage
                                .tag(schedulePageIndex)
                        }

                        // Declaration Page
                        declarationPage
                            .tag(declarationPageIndex)

                        // Search Word Page
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
                                Label(buttonTitle.uppercased(), systemImage: currentPage < totalPages - 1 ? "arrow.right" : "checkmark")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(canProceed ? AppTheme.selectableTint : AppTheme.panelFill)
                                    .cornerRadius(10)
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
                .colorInvert()  // hack for dark backgrounds
                .colorMultiply(AppTheme.selectableTint)
                Spacer()
            }

            Spacer()
        }
    }

    // MARK: - Username Page

    private var usernamePage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("GIVE YOURSELF A COOL NAME")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.gradient1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 16) {
                TextField("", text: $userName)
                    .font(.title3)
                    .foregroundColor(AppTheme.textFieldUserInput)
                    .padding(4)
                    .background(AppTheme.textFieldBackgroundColor)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(AppTheme.textFieldBorderColor, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .autocapitalization(.words)
                    .disableAutocorrection(false)

                Text("\(userName.count)/30 CHARACTERS")
                    .font(.caption)
                    .foregroundColor(AppTheme.smallTextColor1)
            }

            Spacer()
        }
    }

    // MARK: - Test Prep Page

    private var testPrepPage: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Text("ARE YOU STUDYING FOR A TEST?")
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
                            Text("\(testType.displayName.uppercased()), \(formatWordCount(count.total_words))")
                                .tag(testType as TestType?)
                        } else {
                            Text(testType.displayName.uppercased())
                                .tag(testType as TestType?)
                        }
                    }
                }
                .pickerStyle(.wheel)
                .colorInvert()
                .colorMultiply(AppTheme.selectableTint)
                Spacer()
            }
        }
        .onAppear {
            // Fetch all vocabulary counts when page appears
            fetchAllVocabularyCounts()
        }
    }

    // MARK: - Study Duration Page

    private var studyDurationPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("HOW LONG DO YOU WANT TO MASTER THE VOCABULARY?")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.gradient1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            if isLoadingVocabulary {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppTheme.selectableTint)
            } else {
                VStack(spacing: 32) {
                    // Duration display
                    VStack(spacing: 8) {
                        Text("\(Int(selectedStudyDuration))")
                            .font(.system(size: 80, weight: .bold))
                            .foregroundStyle(AppTheme.gradient1)
                        Text("DAYS")
                            .font(.title2)
                            .foregroundColor(AppTheme.mediumTextColor1)
                    }

                    // Slider
                    VStack(spacing: 8) {
                        Slider(value: $selectedStudyDuration, in: 1...365, step: 1)
                            .tint(AppTheme.selectableTint)

                        HStack {
                            Text("1 DAY")
                                .font(.caption)
                                .foregroundColor(AppTheme.smallTextColor1)
                            Spacer()
                            Text("365 DAYS")
                                .font(.caption)
                                .foregroundColor(AppTheme.smallTextColor1)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Words per day calculation
                    if vocabularyCount > 0 {
                        let wordsPerDay = max(1, vocabularyCount / Int(selectedStudyDuration))
                        Text("~\(wordsPerDay) NEW WORDS PER DAY")
                            .font(.headline)
                            .foregroundColor(AppTheme.mediumTextColor1)
//                        VStack(spacing: 8) {
//                            HStack {
//                                Text("📝")
//                                    .font(.title)
//                                Text("~\(wordsPerDay) NEW WORDS PER DAY")
//                                    .font(.headline)
//                                    .foregroundColor(AppTheme.mediumTextColor1)
//                            }
//                            Text("\(vocabularyCount) TOTAL \((selectedTestType?.displayName ?? "").uppercased()) WORDS")
//                                .font(.subheadline)
//                                .foregroundColor(AppTheme.smallTextColor1)
//                        }
//                        .padding()
//                        .background(AppTheme.textFieldBackgroundColor)
//                        .cornerRadius(10)
//                        .overlay(
//                            RoundedRectangle(cornerRadius: 10)
//                                .stroke(AppTheme.textFieldBorderColor, lineWidth: 2)
//                        )
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .onAppear {
            fetchVocabularyCount()
        }
        .onChange(of: selectedTestType) { _, _ in
            // Reset and refetch when test type changes
            studyPlans = []
            selectedStudyDuration = 30
            fetchVocabularyCount()
        }
    }

    // MARK: - Schedule Preview Page

    private var schedulePreviewPage: some View {
        // Reuse the existing ScheduleView in embedded mode (no NavigationStack)
        ScheduleView(embedded: true)
    }

    // MARK: - Declaration Page

    private var declarationPage: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Text("HOW HARSH WORDS WORKS")
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
                .frame(maxHeight: 200)
                .cornerRadius(12)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 16) {
                Text("YOUR BRAIN FORGETS IN PREDICTABLE PATTERNS. HARSH WORDS TRACKS EACH WORD INDIVIDUALLY AND PROMPTS REVIEW AT THE PRECISE MOMENT WHEN RECALL IS CHALLENGING BUT STILL POSSIBLE. THIS \"DESIRABLE DIFFICULTY\" IS WHAT TRANSFORMS SHORT-TERM MEMORIZATION INTO PERMANENT VOCABULARY.")
                    .font(.body)
                    .foregroundColor(AppTheme.mediumTextColor1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Search Word Page

    private var searchWordPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("SEARCH A WORD")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.gradient1)

                Text("TRY SEARCHING FOR YOUR FIRST WORD TO GET STARTED")
                    .font(.body)
                    .foregroundColor(AppTheme.mediumTextColor1)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 16) {
                TextField("", text: $searchWord, prompt: Text("E.G. UNFORGETTABLE").foregroundColor(AppTheme.smallTextColor1))
                    .font(.title3)
                    .foregroundColor(AppTheme.textFieldUserInput)
                    .padding(4)
                    .background(AppTheme.textFieldBackgroundColor)
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(AppTheme.textFieldBorderColor, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }

            Spacer()
        }
    }

    // MARK: - Helper Methods

    private var totalPages: Int {
        if selectedLearningLanguage == "en" {
            // With test: Learning, Native, TestPrep, Duration, Username, Schedule, Declaration, Search = 8 pages
            // Without test: Learning, Native, TestPrep, Username, Declaration, Search = 6 pages
            return showDurationPage ? 8 : 6
        }
        // Non-English: Learning, Native, Username, Declaration, Search = 5 pages
        return 5
    }

    private var showDurationPage: Bool {
        return selectedLearningLanguage == "en" && selectedTestType != nil
    }

    private var usernamePageIndex: Int {
        if selectedLearningLanguage == "en" {
            return showDurationPage ? 4 : 3
        }
        return 2
    }

    private var schedulePageIndex: Int {
        // Only valid when showDurationPage is true
        return 5
    }

    private var declarationPageIndex: Int {
        if selectedLearningLanguage == "en" {
            // With test: page 6 (after schedule preview at page 5)
            // Without test: page 4 (after username at page 3)
            return showDurationPage ? 6 : 4
        }
        return 3
    }

    private var searchPageIndex: Int {
        if selectedLearningLanguage == "en" {
            // With test: page 7 (after declaration at page 6)
            // Without test: page 5 (after declaration at page 4)
            return showDurationPage ? 7 : 5
        }
        return 4
    }

    private var displayPageIndex: Int {
        return currentPage
    }

    private var canProceed: Bool {
        switch currentPage {
        case 0:
            return !selectedLearningLanguage.isEmpty
        case 1:
            return !selectedNativeLanguage.isEmpty && selectedNativeLanguage != selectedLearningLanguage
        case 2:
            // Test prep page (English) or Username page (non-English)
            if selectedLearningLanguage == "en" {
                return true // Test prep always allows proceeding
            } else {
                return !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case 3:
            // Study duration (if test) or Username (if no test) or Declaration (non-English)
            if selectedLearningLanguage == "en" {
                if showDurationPage {
                    return true // Slider always has a value
                } else {
                    return !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty // Username page
                }
            } else {
                return true // Declaration page - always can proceed
            }
        case 4:
            // Username (if test) or Declaration (if no test) or Search (non-English) - English only
            if selectedLearningLanguage == "en" {
                if showDurationPage {
                    return !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty // Username page
                } else {
                    return true // Declaration page - always can proceed
                }
            } else {
                return !searchWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty // Search page
            }
        case 5:
            // Schedule preview page (English with test) or Search (if no test)
            if showDurationPage {
                return true // Schedule preview - always can proceed
            } else {
                return !searchWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty // Search page
            }
        case 6:
            // Declaration page (English with test) or beyond
            if showDurationPage {
                return true // Declaration page - always can proceed
            } else {
                return false
            }
        case 7:
            // Search page (English with test)
            return !searchWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    private var buttonTitle: String {
        if currentPage == usernamePageIndex {
            return "GET STARTED"
        } else if currentPage == searchPageIndex {
            return "SEARCH"
        } else {
            return "NEXT"
        }
    }

    private func handleNextButton() {
        if currentPage < usernamePageIndex {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentPage += 1
            }
        } else if currentPage == usernamePageIndex {
            // Submit onboarding data first
            submitOnboarding()
        } else if currentPage == schedulePageIndex && showDurationPage {
            // Schedule preview page - just advance to declaration
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentPage = declarationPageIndex
            }
        } else if currentPage == declarationPageIndex {
            // Declaration page - just advance to search
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentPage = searchPageIndex
            }
        } else if currentPage == searchPageIndex {
            // Perform search and dismiss onboarding
            performSearch()
        }
    }

    private func submitOnboarding() {
        isSubmitting = true

        let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let userId = userManager.getUserID()

        DictionaryService.shared.updateUserPreferences(
            userID: userId,
            learningLanguage: selectedLearningLanguage,
            nativeLanguage: selectedNativeLanguage,
            userName: trimmedName,
            userMotto: "",
            testPrep: selectedTestType?.rawValue,  // Use raw value for legacy API
            studyDurationDays: Int(selectedStudyDuration)
        ) { result in
            DispatchQueue.main.async {
                isSubmitting = false

                switch result {
                case .success:
                    // Update local user manager
                    // Set isSyncingFromServer to prevent didSet observers from triggering additional API calls
                    userManager.isSyncingFromServer = true
                    userManager.learningLanguage = selectedLearningLanguage
                    userManager.nativeLanguage = selectedNativeLanguage
                    userManager.userName = trimmedName

                    // Update test prep settings using V3 API
                    let duration = Int(selectedStudyDuration)
                    userManager.activeTestType = selectedTestType
                    userManager.targetDays = duration

                    userManager.isSyncingFromServer = false

                    // Track analytics
                    var metadata: [String: Any] = [
                        "learning_language": selectedLearningLanguage,
                        "native_language": selectedNativeLanguage
                    ]
                    if let testType = selectedTestType {
                        metadata["test_type"] = testType.rawValue
                        metadata["study_duration_days"] = duration
                    }
                    AnalyticsManager.shared.track(action: .onboardingComplete, metadata: metadata)

                    // Move to next page (schedule preview if test enabled, otherwise search)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if self.showDurationPage {
                            currentPage = schedulePageIndex
                        } else {
                            currentPage = searchPageIndex
                        }
                    }

                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
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

    private func fetchVocabularyCount() {
        guard let testType = selectedTestType else {
            return
        }

        isLoadingVocabulary = true

        let baseURL = Configuration.effectiveBaseURL
        guard let url = URL(string: "\(baseURL)/v3/api/test-vocabulary-count?test_type=\(testType.rawValue)") else {
            isLoadingVocabulary = false
            setDefaultStudyPlans()
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoadingVocabulary = false

                if let error = error {
                    Self.logger.error("Error fetching vocabulary count: \(error.localizedDescription, privacy: .public)")
                    setDefaultStudyPlans()
                    return
                }

                guard let data = data else {
                    setDefaultStudyPlans()
                    return
                }

                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if let totalWords = json?["total_words"] as? Int,
                       let plans = json?["study_plans"] as? [[String: Int]] {

                        vocabularyCount = totalWords
                        studyPlans = plans.compactMap { plan in
                            if let days = plan["days"], let wordsPerDay = plan["words_per_day"] {
                                return (days: days, wordsPerDay: wordsPerDay)
                            }
                            return nil
                        }

                        // Auto-select 30 days as default
                        selectedStudyDuration = 30
                    } else {
                        setDefaultStudyPlans()
                    }
                } catch {
                    Self.logger.error("Error parsing vocabulary count response: \(error.localizedDescription, privacy: .public)")
                    setDefaultStudyPlans()
                }
            }
        }.resume()
    }

    private func setDefaultStudyPlans() {
        // Fallback to default vocabulary count if API fails
        // Assuming ~3500 words for typical test vocabulary
        vocabularyCount = 3500

        // Keep 30 days as default
        selectedStudyDuration = 30
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

    /// Format word count for display (e.g., "1,247 words" or "3.5K words")
    private func formatWordCount(_ count: Int) -> String {
        if count >= 10000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fK words", k)
        } else if count >= 1000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            let formatted = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
            return "\(formatted) words"
        } else {
            return "\(count) words"
        }
    }

}

#Preview {
    OnboardingView()
}
