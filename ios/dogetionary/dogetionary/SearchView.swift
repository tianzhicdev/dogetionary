//
//  SearchView.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI
import StoreKit

struct SearchView: View {
    var selectedTab: Binding<Int>?
    var showProgressBar: Bool = true  // Default to true for backward compatibility

    @ObservedObject private var userManager = UserManager.shared
    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Show progress bar at top only when NOT showing search results
            // Hide it when user has searched for a word to save screen space
            if showProgressBar, !viewModel.isSearchActive, let progress = viewModel.testProgress, (progress.has_schedule || viewModel.achievementProgress != nil) {
                TestProgressBar(
                    progress: progress.progress,
                    totalWords: progress.total_words,
                    savedWords: progress.saved_words,
                    testType: progress.test_type ?? "NONE",
                    streakDays: progress.streak_days,
                    achievementProgress: viewModel.achievementProgress,
                    testVocabularyAwards: viewModel.testVocabularyAwards,
                    isExpanded: $viewModel.isProgressBarExpanded
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            Spacer()

            // Main content
            ZStack {
                if viewModel.isSearchActive {
                    // Active search layout - search bar at top
                    VStack(spacing: 20) {
                        searchBarView()
                            .padding(.horizontal)

                        if viewModel.isLoading {
                            ProgressView("Searching...")
                                .padding()
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .padding()
                        }

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(viewModel.definitions) { definition in
                                    DefinitionCard(definition: definition)
                                }
                            }
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Dismiss keyboard when tapping on results
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }

                        Spacer()
                    }
                } else {
                    // Landing page layout - centered search bar (hidden when progress bar is expanded)
                    if !viewModel.isProgressBarExpanded {
                        VStack(spacing: 16) {
                            searchBarView()
                        }
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                    }
                }
            }
            
            Spacer()
        }
//        .contentShape(Rectangle())
        .onTapGesture {
            // Dismiss keyboard when tapping outside text field
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .alert("Word Validation", isPresented: $viewModel.showValidationAlert) {
            if let suggestion = viewModel.validationSuggestion {
                // Has suggestion - show suggestion and "yes" options
                Button(suggestion) {
                    viewModel.searchSuggestedWord()
                }
                Button("Yes") {
                    viewModel.showOriginalDefinition()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelSearch()
                }
            } else {
                // No suggestion - show "yes" and cancel options
                Button("Yes") {
                    viewModel.showOriginalDefinition()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelSearch()
                }
            }
        } message: {
            Text("\"\(viewModel.currentSearchQuery)\" is likely not a valid word or phrase, are you sure you want to read its definition?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .performSearchFromOnboarding)) { notification in
            if let word = notification.object as? String {
                viewModel.performSearchFromOnboarding(word: word)
            }
        }
        .onAppear {
            if showProgressBar {
                viewModel.loadTestProgress()
                viewModel.loadAchievementProgress()
                viewModel.loadTestVocabularyAwards()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wordAutoSaved)) { _ in
            // Refresh progress when a word is saved
            if showProgressBar {
                viewModel.loadTestProgress()
                viewModel.loadAchievementProgress()
                viewModel.loadTestVocabularyAwards()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .testSettingsChanged)) { _ in
            // Refresh progress when test settings change
            if showProgressBar {
                viewModel.loadTestProgress()
                viewModel.loadAchievementProgress()
                viewModel.loadTestVocabularyAwards()
            }
        }
    }
    
    @ViewBuilder
    private func searchBarView() -> some View {
        HStack(spacing: 12) {
            HStack {
                TextField("Enter a word or phrase", text: $viewModel.searchText)
                    .font(.title2)
                    .foregroundColor(.primary)
                    .onSubmit {
                        viewModel.searchWord()
                    }

                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                        viewModel.definitions = []
                        viewModel.errorMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.purple.opacity(0.6))
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppTheme.secondaryGradient)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [
                                AppTheme.infoColor.opacity(AppTheme.strongOpacity),
                                Color.purple.opacity(AppTheme.strongOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Color.purple.opacity(AppTheme.lightOpacity), radius: 8, x: 0, y: 4)

            Button(action: {
                viewModel.searchWord()
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.infoColor, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: AppTheme.infoColor.opacity(AppTheme.strongOpacity), radius: 8, x: 0, y: 4)
            }
            .disabled(viewModel.searchText.isEmpty || viewModel.isLoading)
        }
    }
}


#Preview {
    SearchView()
}
