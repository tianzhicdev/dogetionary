//
//  OnboardingView.swift
//  dogetionary
//
//  Created by biubiu on 10/24/25.
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var userManager = UserManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var currentPage = 0
    @State private var selectedLearningLanguage = "en"
    @State private var selectedNativeLanguage = "fr"
    @State private var selectedTestPrep: String? = nil // TOEFL, IELTS, or nil
    @State private var selectedStudyDuration: Int? = nil // 30, 40, 50, 60, or 70
    @State private var vocabularyCount: Int = 0
    @State private var studyPlans: [(days: Int, wordsPerDay: Int)] = []
    @State private var isLoadingVocabulary = false
    @State private var userName = ""
    @State private var searchWord = "unforgettable"
    @State private var isSubmitting = false
    @State private var isSearching = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var shouldDismiss = false
    @State private var searchedDefinitions: [Definition] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                HStack(spacing: 8) {
                    ForEach(0..<totalPages) { index in
                        Capsule()
                            .fill(index <= displayPageIndex ? Color.blue : Color.gray.opacity(0.3))
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
                        title: "What language are you learning?",
                        description: "Choose the language you want to learn and improve",
                        selectedLanguage: $selectedLearningLanguage,
                        excludeLanguage: selectedNativeLanguage
                    )
                    .tag(0)

                    // Page 1: Native Language
                    languageSelectionPage(
                        title: "What is your native language?",
                        description: "Choose your native language for translations",
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

                    // Search Word Page
                    searchWordPage
                        .tag(searchPageIndex)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Navigation buttons
                HStack(spacing: 16) {
                    if currentPage > 0 {
                        Button(action: {
                            withAnimation {
                                currentPage -= 1
                            }
                        }) {
                            Text("Back")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }

                    Button(action: {
                        handleNextButton()
                    }) {
                        HStack {
                            if isSubmitting || isSearching {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(buttonTitle)
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canProceed ? Color.blue : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!canProceed || isSubmitting || isSearching)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
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
        selectedLanguage: Binding<String>,
        excludeLanguage: String
    ) -> some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            Picker("Select Language", selection: selectedLanguage) {
                ForEach(LanguageConstants.availableLanguages.filter { $0.0 != excludeLanguage }, id: \.0) { language in
                    HStack {
                        Text(language.1)
                            .font(.title3)
                        Text("(\(language.0.uppercased()))")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .tag(language.0)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .tint(.blue)
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Username Page

    private var usernamePage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("Give yourself a cool name")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("This name will be displayed on the leaderboard")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 16) {
                TextField("Enter your name", text: $userName)
                    .font(.title3)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 24)
                    .autocapitalization(.words)
                    .disableAutocorrection(false)

                Text("\(userName.count)/30 characters")
                    .font(.caption)
                    .foregroundColor(userName.count > 25 ? .orange : .secondary)
            }

            Spacer()
        }
    }

    // MARK: - Test Prep Page

    private var testPrepPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("Are you studying for a test?")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("We can help you prepare for standardized tests")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 16) {
                testPrepButton(title: "TOEFL", icon: "", testType: "TOEFL")
                testPrepButton(title: "IELTS", icon: "", testType: "IELTS")
                testPrepButton(title: "Neither", icon: "", testType: nil)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func testPrepButton(title: String, icon: String, testType: String?) -> some View {
        Button(action: {
            selectedTestPrep = testType
        }) {
            HStack {
                Text(icon)
                    .font(.title2)
                Text(title)
                    .font(.headline)
                Spacer()
                if selectedTestPrep == testType {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding()
            .background(selectedTestPrep == testType ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedTestPrep == testType ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Study Duration Page

    private var studyDurationPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("How long do you want to study?")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Choose your study plan for \(selectedTestPrep ?? "")")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            if isLoadingVocabulary {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                VStack(spacing: 16) {
                    ForEach(studyPlans, id: \.days) { plan in
                        studyDurationButton(days: plan.days, wordsPerDay: plan.wordsPerDay)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .onAppear {
            if studyPlans.isEmpty {
                fetchVocabularyCount()
            }
        }
    }

    private func studyDurationButton(days: Int, wordsPerDay: Int) -> some View {
        Button(action: {
            selectedStudyDuration = days
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(days) days")
                        .font(.headline)
                    Text("~\(wordsPerDay) new words per day")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if selectedStudyDuration == days {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding()
            .background(selectedStudyDuration == days ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedStudyDuration == days ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Search Word Page

    private var searchWordPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("Search a word")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("Try searching for your first word to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 16) {
                TextField("", text: $searchWord)
                    .font(.title3)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
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
            return showDurationPage ? 6 : 5
        }
        return 4
    }

    private var showDurationPage: Bool {
        return selectedLearningLanguage == "en" &&
               (selectedTestPrep == "TOEFL" || selectedTestPrep == "IELTS")
    }

    private var usernamePageIndex: Int {
        if selectedLearningLanguage == "en" {
            return showDurationPage ? 4 : 3
        }
        return 2
    }

    private var searchPageIndex: Int {
        if selectedLearningLanguage == "en" {
            return showDurationPage ? 5 : 4
        }
        return 3
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
            // Study duration (if test) or Username (if no test) or Search (non-English)
            if selectedLearningLanguage == "en" {
                if showDurationPage {
                    return selectedStudyDuration != nil // Study duration page
                } else {
                    return !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty // Username page
                }
            } else {
                return !searchWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty // Search page
            }
        case 4:
            // Username (if test) or Search (if no test) - English only
            if showDurationPage {
                return !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty // Username page
            } else {
                return !searchWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty // Search page
            }
        case 5:
            // Search page (English with test)
            return !searchWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    private var buttonTitle: String {
        if currentPage == usernamePageIndex {
            return "Get Started"
        } else if currentPage == searchPageIndex {
            return "Search"
        } else {
            return "Next"
        }
    }

    private func handleNextButton() {
        if currentPage < usernamePageIndex {
            withAnimation {
                currentPage += 1
            }
        } else if currentPage == usernamePageIndex {
            // Submit onboarding data first
            submitOnboarding()
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
            testPrep: selectedTestPrep,
            studyDurationDays: selectedStudyDuration
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

                    // Update test prep settings
                    // Always update target days if duration was selected, even if test prep is disabled
                    if let duration = selectedStudyDuration {
                        // Update both target days to keep them in sync
                        userManager.toeflTargetDays = duration
                        userManager.ieltsTargetDays = duration
                    }

                    if let testPrep = selectedTestPrep {
                        if testPrep == "TOEFL" {
                            userManager.toeflEnabled = true
                            userManager.ieltsEnabled = false
                        } else if testPrep == "IELTS" {
                            userManager.toeflEnabled = false
                            userManager.ieltsEnabled = true
                        }
                    } else {
                        userManager.toeflEnabled = false
                        userManager.ieltsEnabled = false
                    }

                    userManager.isSyncingFromServer = false

                    // Create schedule if test prep was enabled
                    if let testPrep = selectedTestPrep, let duration = selectedStudyDuration {
                        createSchedule(testType: testPrep, targetDays: duration)
                    }

                    // Track analytics
                    var metadata: [String: Any] = [
                        "learning_language": selectedLearningLanguage,
                        "native_language": selectedNativeLanguage
                    ]
                    if let testPrep = selectedTestPrep {
                        metadata["test_prep"] = testPrep
                    }
                    if let duration = selectedStudyDuration {
                        metadata["study_duration_days"] = duration
                    }
                    AnalyticsManager.shared.track(action: .onboardingComplete, metadata: metadata)

                    // Move to search page
                    withAnimation {
                        currentPage = searchPageIndex
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

        // Post notification to SearchView to perform the search
        NotificationCenter.default.post(
            name: .performSearchFromOnboarding,
            object: trimmedWord
        )

        // Dismiss onboarding - SearchView will handle the actual search
        shouldDismiss = true
    }

    private func fetchVocabularyCount() {
        guard let testType = selectedTestPrep, testType == "TOEFL" || testType == "IELTS" else {
            return
        }

        isLoadingVocabulary = true

        let baseURL = Configuration.effectiveBaseURL
        guard let url = URL(string: "\(baseURL)/v3/api/test-vocabulary-count?test_type=\(testType)") else {
            isLoadingVocabulary = false
            setDefaultStudyPlans()
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoadingVocabulary = false

                if let error = error {
                    print("Error fetching vocabulary count: \(error)")
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

                        // Auto-select 60 days if available
                        if let defaultPlan = studyPlans.first(where: { $0.days == 60 }) {
                            selectedStudyDuration = defaultPlan.days
                        }
                    } else {
                        setDefaultStudyPlans()
                    }
                } catch {
                    print("Error parsing vocabulary count response: \(error)")
                    setDefaultStudyPlans()
                }
            }
        }.resume()
    }

    private func setDefaultStudyPlans() {
        // Fallback to default study plans if API fails
        // Assuming ~3500 words for typical test vocabulary
        let defaultTotalWords = 3500
        studyPlans = [
            (days: 70, wordsPerDay: 50),
            (days: 60, wordsPerDay: 59),
            (days: 50, wordsPerDay: 70),
            (days: 40, wordsPerDay: 88),
            (days: 30, wordsPerDay: 117)
        ]
        vocabularyCount = defaultTotalWords

        // Auto-select 60 days
        selectedStudyDuration = 60
    }

    private func createSchedule(testType: String, targetDays: Int) {
        print("📅 Creating schedule for \(testType) with \(targetDays) target days")

        // Calculate target end date
        let calendar = Calendar.current
        guard let targetEndDate = calendar.date(byAdding: .day, value: targetDays, to: Date()) else {
            print("❌ Failed to calculate target end date")
            return
        }

        // Format as YYYY-MM-DD string (backend expects this format)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let targetEndDateString = formatter.string(from: targetEndDate)

        print("📅 Calling createSchedule API - testType: \(testType), targetEndDate: \(targetEndDateString)")

        DictionaryService.shared.createSchedule(testType: testType, targetEndDate: targetEndDateString) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    print("✅ Successfully created schedule: \(response.schedule.schedule_id)")
                case .failure(let error):
                    print("❌ Failed to create schedule: \(error.localizedDescription)")
                }
            }
        }
    }

}

#Preview {
    OnboardingView()
}
