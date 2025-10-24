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
                    ForEach(0..<4) { index in
                        Capsule()
                            .fill(index <= currentPage ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                .padding(.bottom, 30)

                // Page content
                TabView(selection: $currentPage) {
                    // Page 1: Learning Language
                    languageSelectionPage(
                        title: "What language are you learning?",
                        description: "Choose the language you want to learn and improve",
                        selectedLanguage: $selectedLearningLanguage,
                        excludeLanguage: selectedNativeLanguage
                    )
                    .tag(0)

                    // Page 2: Native Language
                    languageSelectionPage(
                        title: "What is your native language?",
                        description: "Choose your native language for translations",
                        selectedLanguage: $selectedNativeLanguage,
                        excludeLanguage: selectedLearningLanguage
                    )
                    .tag(1)

                    // Page 3: Username
                    usernamePage
                        .tag(2)

                    // Page 4: Search Word
                    searchWordPage
                        .tag(3)
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

    private var canProceed: Bool {
        switch currentPage {
        case 0:
            return !selectedLearningLanguage.isEmpty
        case 1:
            return !selectedNativeLanguage.isEmpty && selectedNativeLanguage != selectedLearningLanguage
        case 2:
            return !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 3:
            return !searchWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    private var buttonTitle: String {
        switch currentPage {
        case 0, 1: return "Next"
        case 2: return "Get Started"
        case 3: return "Search"
        default: return "Next"
        }
    }

    private func handleNextButton() {
        if currentPage < 2 {
            withAnimation {
                currentPage += 1
            }
        } else if currentPage == 2 {
            // Submit onboarding data first
            submitOnboarding()
        } else if currentPage == 3 {
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
            userMotto: ""
        ) { result in
            DispatchQueue.main.async {
                isSubmitting = false

                switch result {
                case .success:
                    // Update local user manager
                    userManager.learningLanguage = selectedLearningLanguage
                    userManager.nativeLanguage = selectedNativeLanguage
                    userManager.userName = trimmedName

                    // Track analytics
                    AnalyticsManager.shared.track(action: .onboardingComplete, metadata: [
                        "learning_language": selectedLearningLanguage,
                        "native_language": selectedNativeLanguage
                    ])

                    // Move to page 4 (search)
                    withAnimation {
                        currentPage = 3
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

}

#Preview {
    OnboardingView()
}
