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
    @State private var selectedTestType: TestType? = nil // Level-based test selection
    @State private var selectedStudyDuration: Double = 30 // 10-100 days via slider
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
                pageGradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress indicator
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Capsule()
                                .fill(index <= displayPageIndex ?
                                    LinearGradient(colors: [Color.purple, Color.blue],
                                                 startPoint: .leading, endPoint: .trailing) :
                                    LinearGradient(colors: [Color.gray.opacity(0.3)],
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
                            gradientColors: [Color.blue, Color.cyan]
                        )
                        .tag(0)

                        // Page 1: Native Language
                        languageSelectionPage(
                            title: "What is your native language?",
                            description: "Choose your native language for translations",
                            emoji: "🏠",
                            selectedLanguage: $selectedNativeLanguage,
                            excludeLanguage: selectedLearningLanguage,
                            gradientColors: [Color.green, Color.mint]
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
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.4)],
                                                 startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(16)
                                .shadow(color: Color.black.opacity(0.1), radius: 5, y: 3)
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
                                if currentPage < totalPages - 1 && !isSubmitting && !isSearching {
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                canProceed ?
                                    LinearGradient(colors: buttonGradientColors,
                                                 startPoint: .leading, endPoint: .trailing) :
                                    LinearGradient(colors: [Color.gray],
                                                 startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(16)
                            .shadow(color: canProceed ? Color.purple.opacity(0.3) : Color.clear, radius: 10, y: 5)
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
        let colors: [Color]
        switch currentPage {
        case 0:
            colors = [Color.blue.opacity(0.3), Color.cyan.opacity(0.2), Color.white]
        case 1:
            colors = [Color.green.opacity(0.3), Color.mint.opacity(0.2), Color.white]
        case 2:
            colors = [Color.purple.opacity(0.3), Color.pink.opacity(0.2), Color.white]
        case 3:
            colors = [Color.orange.opacity(0.3), Color.yellow.opacity(0.2), Color.white]
        case usernamePageIndex:
            colors = [Color.indigo.opacity(0.3), Color.purple.opacity(0.2), Color.white]
        case schedulePageIndex:
            colors = [Color.pink.opacity(0.3), Color.red.opacity(0.2), Color.white]
        case declarationPageIndex:
            colors = [Color.purple.opacity(0.3), Color.blue.opacity(0.2), Color.white]
        case searchPageIndex:
            colors = [Color.teal.opacity(0.3), Color.blue.opacity(0.2), Color.white]
        default:
            colors = [Color.blue.opacity(0.3), Color.white]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var buttonGradientColors: [Color] {
        switch currentPage {
        case 0: return [Color.blue, Color.cyan]
        case 1: return [Color.green, Color.mint]
        case 2: return [Color.purple, Color.pink]
        case 3: return [Color.orange, Color.yellow]
        case usernamePageIndex: return [Color.indigo, Color.purple]
        case schedulePageIndex: return [Color.pink, Color.red]
        case declarationPageIndex: return [Color.purple, Color.blue]
        case searchPageIndex: return [Color.teal, Color.blue]
        default: return [Color.blue, Color.purple]
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
                    .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)

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
                    .shadow(color: Color.yellow.opacity(0.3), radius: 10, y: 5)

                Text("Give yourself a cool name")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.indigo, Color.purple],
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
                TextField("", text: $userName, prompt: Text("Enter your name").foregroundColor(.gray))
                    .font(.title3)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .shadow(color: Color.indigo.opacity(0.2), radius: 10, y: 5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(colors: [Color.indigo, Color.purple],
                                             startPoint: .leading, endPoint: .trailing),
                                lineWidth: 2
                            )
                    )
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
            VStack(spacing: 20) {
                Text("📚")
                    .font(.system(size: 80))
                    .shadow(color: Color.purple.opacity(0.3), radius: 10, y: 5)

                Text("Are you studying for a test?")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.purple, Color.pink],
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
                    testPrepButton(title: "TOEFL Beginner", subtitle: "Foundation vocabulary", emoji: "🌱", testType: .toeflBeginner, colors: [Color.green, Color.mint])
                    testPrepButton(title: "TOEFL Intermediate", subtitle: "Includes beginner words", emoji: "🌿", testType: .toeflIntermediate, colors: [Color.teal, Color.cyan])
                    testPrepButton(title: "TOEFL Advanced", subtitle: "Complete TOEFL vocabulary", emoji: "🌳", testType: .toeflAdvanced, colors: [Color.blue, Color.purple])

                    Divider().padding(.vertical, 8)

                    // IELTS options
                    testPrepButton(title: "IELTS Beginner", subtitle: "Foundation vocabulary", emoji: "🎯", testType: .ieltsBeginner, colors: [Color.orange, Color.yellow])
                    testPrepButton(title: "IELTS Intermediate", subtitle: "Includes beginner words", emoji: "🎪", testType: .ieltsIntermediate, colors: [Color.pink, Color.red])
                    testPrepButton(title: "IELTS Advanced", subtitle: "Complete IELTS vocabulary", emoji: "🏆", testType: .ieltsAdvanced, colors: [Color.purple, Color.indigo])

                    Divider().padding(.vertical, 8)

                    // TIANZ option
                    testPrepButton(title: "Tianz Test", subtitle: "Specialized vocabulary", emoji: "⭐", testType: .tianz, colors: [Color.indigo, Color.purple])

                    // Neither option
                    testPrepButton(title: "None", subtitle: "Skip test preparation", emoji: "🎨", testType: nil, colors: [Color.gray, Color.gray.opacity(0.6)])
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
                    .fill(selectedTestType == testType ? colors[0].opacity(0.15) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        selectedTestType == testType ?
                            LinearGradient(colors: colors,
                                         startPoint: .leading, endPoint: .trailing) :
                            LinearGradient(colors: [Color.gray.opacity(0.2)],
                                         startPoint: .leading, endPoint: .trailing),
                        lineWidth: selectedTestType == testType ? 3 : 1
                    )
            )
            .shadow(color: selectedTestType == testType ? colors[0].opacity(0.3) : Color.clear, radius: 10, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Study Duration Page

    private var studyDurationPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                Text("⏰")
                    .font(.system(size: 80))
                    .shadow(color: Color.orange.opacity(0.3), radius: 10, y: 5)

                Text("How long do you want to study?")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.orange, Color.yellow],
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
                    .tint(Color.orange)
            } else {
                VStack(spacing: 32) {
                    // Duration display
                    VStack(spacing: 8) {
                        Text("\(Int(selectedStudyDuration))")
                            .font(.system(size: 80, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(colors: [Color.orange, Color.yellow],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .shadow(color: Color.orange.opacity(0.3), radius: 10, y: 5)
                        Text("days")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }

                    // Slider
                    VStack(spacing: 8) {
                        Slider(value: $selectedStudyDuration, in: 10...100, step: 5)
                            .tint(Color.orange)

                        HStack {
                            Text("10 days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("100 days")
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
                                    LinearGradient(colors: [Color.orange.opacity(0.2), Color.yellow.opacity(0.1)],
                                                 startPoint: .leading, endPoint: .trailing)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: Color.orange.opacity(0.2), radius: 10, y: 5)
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
                    .shadow(color: Color.purple.opacity(0.3), radius: 10, y: 5)

                Text("How Fledge Works")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.purple, Color.blue],
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
                            LinearGradient(colors: [Color.purple.opacity(0.1), Color.blue.opacity(0.05)],
                                         startPoint: .leading, endPoint: .trailing)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 2)
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
                    .shadow(color: Color.teal.opacity(0.3), radius: 10, y: 5)

                Text("Search a word")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.teal, Color.blue],
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
                TextField("", text: $searchWord, prompt: Text("e.g. unforgettable").foregroundColor(.gray))
                    .font(.title3)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .shadow(color: Color.teal.opacity(0.2), radius: 10, y: 5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(colors: [Color.teal, Color.blue],
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

        // Post notification to SearchView to perform the search
        NotificationCenter.default.post(
            name: .performSearchFromOnboarding,
            object: trimmedWord
        )

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

                        // Auto-select 30 days as default
                        selectedStudyDuration = 30
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
            print("Invalid URL for fetching all vocabulary counts")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching all vocabulary counts: \(error)")
                return
            }

            guard let data = data else {
                print("No data received for vocabulary counts")
                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(VocabularyCountResponse.self, from: data)

                DispatchQueue.main.async {
                    // Store all counts in the dictionary
                    self.vocabularyCounts = response.allCounts()
                    print("Fetched vocabulary counts for \(self.vocabularyCounts.count) test types")
                }
            } catch {
                print("Error decoding vocabulary counts: \(error)")
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
