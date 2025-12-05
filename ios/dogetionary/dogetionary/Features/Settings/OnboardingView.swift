//
//  OnboardingView.swift
//  dogetionary
//
//  Created by biubiu on 10/24/25.
//

import SwiftUI
import os.log

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
                                    LinearGradient(colors: [AppTheme.systemPurple, AppTheme.systemBlue],
                                                 startPoint: .leading, endPoint: .trailing) :
                                    LinearGradient(colors: [AppTheme.lightGray],
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
                            title: "What language are you learning?",
                            description: "Choose the language you want to learn and improve",
                            emoji: "🌍",
                            selectedLanguage: $selectedLearningLanguage,
                            excludeLanguage: selectedNativeLanguage,
                            gradientColors: [AppTheme.systemBlue, AppTheme.systemCyan]
                        )
                        .tag(0)

                        // Page 1: Native Language
                        languageSelectionPage(
                            title: "What is your native language?",
                            description: "Choose your native language for translations",
                            emoji: "🏠",
                            selectedLanguage: $selectedNativeLanguage,
                            excludeLanguage: selectedLearningLanguage,
                            gradientColors: [AppTheme.systemGreen, AppTheme.systemMint]
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
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    currentPage -= 1
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.left")
                                    Text("Back")
                                }
                                .font(.headline)
                                .foregroundColor(AppTheme.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(colors: [AppTheme.disabledGray, AppTheme.lightGray.opacity(1.33)],
                                                 startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(16)
                                .shadow(color: AppTheme.black.opacity(0.1), radius: 5, y: 3)
                            }
                        }

                        Button(action: {
                            handleNextButton()
                        }) {
                            HStack {
                                if isSubmitting || isSearching {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.white))
                                        .scaleEffect(0.8)
                                }
                                Text(buttonTitle)
                                    .font(.headline)
                                if currentPage < totalPages - 1 && !isSubmitting && !isSearching {
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .foregroundColor(AppTheme.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                canProceed ?
                                    LinearGradient(colors: buttonGradientColors,
                                                 startPoint: .leading, endPoint: .trailing) :
                                    LinearGradient(colors: [AppTheme.mediumGray],
                                                 startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(16)
                            .shadow(color: canProceed ? AppTheme.systemPurple.opacity(0.3) : AppTheme.clear, radius: 10, y: 5)
                        }
                        .disabled(!canProceed || isSubmitting || isSearching)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
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

    // MARK: - Gradient Backgrounds

    private var pageGradient: LinearGradient {
        // Map page indices to gradient array indices (0-7)
        let gradientIndex: Int
        switch currentPage {
        case 0: gradientIndex = 0  // Learning Language
        case 1: gradientIndex = 1  // Native Language
        case 2: gradientIndex = 2  // Test Prep
        case 3: gradientIndex = 3  // Study Duration
        case usernamePageIndex: gradientIndex = 4  // Username
        case schedulePageIndex: gradientIndex = 5  // Schedule Preview
        case declarationPageIndex: gradientIndex = 6  // Declaration
        case searchPageIndex: gradientIndex = 7  // Search Word
        default: gradientIndex = 0  // Fallback to first gradient
        }
        return AppTheme.onboardingBackgroundGradients[gradientIndex]
    }

    private var buttonGradientColors: [Color] {
        // Map page indices to gradient array indices (0-7)
        let gradientIndex: Int
        switch currentPage {
        case 0: gradientIndex = 0  // Learning Language
        case 1: gradientIndex = 1  // Native Language
        case 2: gradientIndex = 2  // Test Prep
        case 3: gradientIndex = 3  // Study Duration
        case usernamePageIndex: gradientIndex = 4  // Username
        case schedulePageIndex: gradientIndex = 5  // Schedule Preview
        case declarationPageIndex: gradientIndex = 6  // Declaration
        case searchPageIndex: gradientIndex = 7  // Search Word
        default: gradientIndex = 0  // Fallback to first gradient
        }
        // Extract colors from the gradient
        let gradient = AppTheme.onboardingPageGradients[gradientIndex]
        // Return the gradient colors (we need to extract them from LinearGradient)
        // Since we can't extract, return the same colors used in ThemeConstants
        switch gradientIndex {
        case 0: return [AppTheme.systemBlue, AppTheme.systemCyan]
        case 1: return [AppTheme.systemGreen, AppTheme.systemMint]
        case 2: return [AppTheme.systemPurple, AppTheme.systemPink]
        case 3: return [AppTheme.systemOrange, AppTheme.systemYellow]
        case 4: return [AppTheme.systemIndigo, AppTheme.systemPurple]
        case 5: return [AppTheme.systemPink, AppTheme.systemRed]
        case 6: return [AppTheme.systemPurple, AppTheme.systemBlue]
        case 7: return [AppTheme.systemTeal, AppTheme.systemBlue]
        default: return [AppTheme.systemBlue, AppTheme.systemPurple]
        }
    }

    // MARK: - Language Selection Page

    private func languageSelectionPage(
        title: String,
        description: String,
        emoji: String,
        selectedLanguage: Binding<String>,
        excludeLanguage: String,
        gradientColors: [Color]
    ) -> some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Text(emoji)
                    .font(.system(size: 80))
                    .shadow(color: AppTheme.black.opacity(0.1), radius: 10, y: 5)

                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: gradientColors,
                                     startPoint: .leading, endPoint: .trailing)
                    )

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
            .tint(gradientColors[0])
            .padding(.horizontal, 24)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(gradientColors[0].opacity(0.1))
                    .shadow(color: gradientColors[0].opacity(0.2), radius: 10, y: 5)
            )
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Username Page

    private var usernamePage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("🌟")
                    .font(.system(size: 80))
                    .shadow(color: AppTheme.systemYellow.opacity(0.3), radius: 10, y: 5)

                Text("Give yourself a cool name")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: [AppTheme.systemIndigo, AppTheme.systemPurple],
                                     startPoint: .leading, endPoint: .trailing)
                    )

                Text("This name will be displayed on the leaderboard")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 16) {
                TextField("", text: $userName, prompt: Text("Enter your name").foregroundColor(AppTheme.mediumGray))
                    .font(.title3)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppTheme.white)
                            .shadow(color: AppTheme.systemIndigo.opacity(0.2), radius: 10, y: 5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(colors: [AppTheme.systemIndigo, AppTheme.systemPurple],
                                             startPoint: .leading, endPoint: .trailing),
                                lineWidth: 2
                            )
                    )
                    .padding(.horizontal, 24)
                    .autocapitalization(.words)
                    .disableAutocorrection(false)

                Text("\(userName.count)/30 characters")
                    .font(.caption)
                    .foregroundColor(userName.count > 25 ? AppTheme.systemOrange : .secondary)
            }

            Spacer()
        }
    }

    // MARK: - Test Prep Page

    private var testPrepPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("📚")
                    .font(.system(size: 80))
                    .shadow(color: AppTheme.systemPurple.opacity(0.3), radius: 10, y: 5)

                Text("Are you studying for a test?")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: [AppTheme.systemPurple, AppTheme.systemPink],
                                     startPoint: .leading, endPoint: .trailing)
                    )

                Text("Choose your test level")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            ScrollView {
                VStack(spacing: 12) {
                    // TOEFL options
                    testPrepButton(title: "TOEFL Beginner", subtitle: "Foundation vocabulary", emoji: "🌱", testType: .toeflBeginner, colors: [AppTheme.systemGreen, AppTheme.systemMint])
                    testPrepButton(title: "TOEFL Intermediate", subtitle: "Includes beginner words", emoji: "🌿", testType: .toeflIntermediate, colors: [AppTheme.systemTeal, AppTheme.systemCyan])
                    testPrepButton(title: "TOEFL Advanced", subtitle: "Complete TOEFL vocabulary", emoji: "🌳", testType: .toeflAdvanced, colors: [AppTheme.systemBlue, AppTheme.systemPurple])

                    Divider().padding(.vertical, 8)

                    // IELTS options
                    testPrepButton(title: "IELTS Beginner", subtitle: "Foundation vocabulary", emoji: "🎯", testType: .ieltsBeginner, colors: [AppTheme.systemOrange, AppTheme.systemYellow])
                    testPrepButton(title: "IELTS Intermediate", subtitle: "Includes beginner words", emoji: "🎪", testType: .ieltsIntermediate, colors: [AppTheme.systemPink, AppTheme.systemRed])
                    testPrepButton(title: "IELTS Advanced", subtitle: "Complete IELTS vocabulary", emoji: "🏆", testType: .ieltsAdvanced, colors: [AppTheme.systemPurple, AppTheme.systemIndigo])

                    Divider().padding(.vertical, 8)

                    // TIANZ option
                    testPrepButton(title: "Tianz Test", subtitle: "Specialized vocabulary", emoji: "⭐", testType: .tianz, colors: [AppTheme.systemIndigo, AppTheme.systemPurple])

                    // Neither option
                    testPrepButton(title: "None", subtitle: "Skip test preparation", emoji: "🎨", testType: nil, colors: [AppTheme.mediumGray, AppTheme.disabledGray])
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            // Fetch all vocabulary counts when page appears
            fetchAllVocabularyCounts()
        }
    }

    private func testPrepButton(title: String, subtitle: String, emoji: String, testType: TestType?, colors: [Color]) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTestType = testType
            }
        }) {
            HStack(spacing: 16) {
                Text(emoji)
                    .font(.system(size: 32))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Word count badge
                if let testType = testType, let count = vocabularyCounts[testType] {
                    Text(formatWordCount(count.total_words))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(colors: colors,
                                         startPoint: .leading, endPoint: .trailing)
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [colors[0].opacity(0.15), colors[1].opacity(0.15)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(colors: colors,
                                                 startPoint: .leading, endPoint: .trailing),
                                    lineWidth: 1
                                )
                        )
                }

                if selectedTestType == testType {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(
                            LinearGradient(colors: colors,
                                         startPoint: .leading, endPoint: .trailing)
                        )
                        .font(.title2)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedTestType == testType ? colors[0].opacity(0.15) : AppTheme.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        selectedTestType == testType ?
                            LinearGradient(colors: colors,
                                         startPoint: .leading, endPoint: .trailing) :
                            LinearGradient(colors: [AppTheme.lightGray.opacity(0.67)],
                                         startPoint: .leading, endPoint: .trailing),
                        lineWidth: selectedTestType == testType ? 3 : 1
                    )
            )
            .shadow(color: selectedTestType == testType ? colors[0].opacity(0.3) : AppTheme.clear, radius: 10, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Study Duration Page

    private var studyDurationPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("⏰")
                    .font(.system(size: 80))
                    .shadow(color: AppTheme.systemOrange.opacity(0.3), radius: 10, y: 5)

                Text("How long do you want to study?")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: [AppTheme.systemOrange, AppTheme.systemYellow],
                                     startPoint: .leading, endPoint: .trailing)
                    )

                Text("Set your study timeline for \(selectedTestType?.displayName ?? "")")
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
                    .tint(AppTheme.systemOrange)
            } else {
                VStack(spacing: 32) {
                    // Duration display
                    VStack(spacing: 8) {
                        Text("\(Int(selectedStudyDuration))")
                            .font(.system(size: 80, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(colors: [AppTheme.systemOrange, AppTheme.systemYellow],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .shadow(color: AppTheme.systemOrange.opacity(0.3), radius: 10, y: 5)
                        Text("days")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }

                    // Slider
                    VStack(spacing: 8) {
                        Slider(value: $selectedStudyDuration, in: 1...365, step: 1)
                            .tint(AppTheme.systemOrange)

                        HStack {
                            Text("1 day")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("365 days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Words per day calculation
                    if vocabularyCount > 0 {
                        let wordsPerDay = max(1, vocabularyCount / Int(selectedStudyDuration))
                        VStack(spacing: 8) {
                            HStack {
                                Text("📝")
                                    .font(.title)
                                Text("~\(wordsPerDay) new words per day")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            Text("\(vocabularyCount) total \(selectedTestType?.displayName ?? "") words")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(colors: [AppTheme.systemOrange.opacity(0.2), AppTheme.systemYellow.opacity(0.1)],
                                                 startPoint: .leading, endPoint: .trailing)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppTheme.systemOrange.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: AppTheme.systemOrange.opacity(0.2), radius: 10, y: 5)
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
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("🧠")
                    .font(.system(size: 80))
                    .shadow(color: AppTheme.systemPurple.opacity(0.3), radius: 10, y: 5)

                Text("How Fledge Works")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: [AppTheme.systemPurple, AppTheme.systemBlue],
                                     startPoint: .leading, endPoint: .trailing)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            VStack(alignment: .leading, spacing: 24) {
                Text("Building vocabulary the old way is wasteful—you forget, re-learn, forget again.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Fledge fixes this. It tracks every word you study, calculates when you're about to forget, and prompts you at exactly the right moment.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("⚡")
                            .font(.title)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SuperMemo Spaced Repetition")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Up to 20x more efficient learning")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Text("⏱")
                            .font(.title)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Save Your Time")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("80+ hours back for every 1,000 words")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(colors: [AppTheme.systemPurple.opacity(0.1), AppTheme.systemBlue.opacity(0.05)],
                                         startPoint: .leading, endPoint: .trailing)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.systemPurple.opacity(0.2), lineWidth: 2)
                )
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Search Word Page

    private var searchWordPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("🔍")
                    .font(.system(size: 80))
                    .shadow(color: AppTheme.systemTeal.opacity(0.3), radius: 10, y: 5)

                Text("Search a word")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: [AppTheme.systemTeal, AppTheme.systemBlue],
                                     startPoint: .leading, endPoint: .trailing)
                    )

                Text("Try searching for your first word to get started")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)

            Spacer()

            VStack(spacing: 16) {
                TextField("", text: $searchWord, prompt: Text("e.g. unforgettable").foregroundColor(AppTheme.mediumGray))
                    .font(.title3)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(AppTheme.white)
                            .shadow(color: AppTheme.systemTeal.opacity(0.2), radius: 10, y: 5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(colors: [AppTheme.systemTeal, AppTheme.systemBlue],
                                             startPoint: .leading, endPoint: .trailing),
                                lineWidth: 2
                            )
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
            return "Get Started"
        } else if currentPage == searchPageIndex {
            return "Search"
        } else {
            return "Next"
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
