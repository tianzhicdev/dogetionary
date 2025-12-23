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
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Gradient background
            AppTheme.verticalGradient2
                .ignoresSafeArea()

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
                            ProgressView("SEARCHING...")
                                .tint(AppTheme.accentCyan)
                                .foregroundColor(AppTheme.smallTitleText)
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

                            Text("Search for a word to add it to your vocabulary")
                                .font(.subheadline)
                                .foregroundColor(AppTheme.bodyText)
                                
                        }
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                    }
                }
            }

                Spacer()
            }
        }
        .errorToast(message: viewModel.errorMessage) {
            viewModel.errorMessage = nil
        }
        .overlay(
            // Video search message toast
            Group {
                if viewModel.showVideoSearchMessage {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .foregroundColor(AppTheme.accentCyan)
                            Text(viewModel.videoSearchMessageText)
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        .padding()
                        .background(AppTheme.panelFill)
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.3), radius: 10)
                        .padding(.bottom, 60)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: viewModel.showVideoSearchMessage)
                }
            }
        )
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
        .onChange(of: appState.searchQueryFromOnboarding) { _, query in
            if let word = query {
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
        .onChange(of: appState.testSettingsChanged) { _, changed in
            if changed {
                // Refresh progress when test settings change
                if showProgressBar {
                    viewModel.loadTestProgress()
                    viewModel.loadAchievementProgress()
                    viewModel.loadTestVocabularyAwards()
                }
            }
        }
        
    }
    
    @ViewBuilder
    private func searchBarView() -> some View {
        HStack(spacing: 12) {
            HStack {
                TextField("", text: $viewModel.searchText)
                    .font(.title2)
                    .foregroundColor(AppTheme.textFieldUserInput)
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
                            .foregroundColor(AppTheme.selectableTint)
                            .font(.title3)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppTheme.textFieldBackgroundColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppTheme.textFieldBorderColor, lineWidth: 2)
            )

            Button(action: {
                viewModel.searchWord()
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .foregroundColor(AppTheme.bigButtonForeground1)
                    .frame(width: 50, height: 50)
                    .background(AppTheme.bigButtonBackground1)
                    .cornerRadius(10)
            }
            .disabled(viewModel.searchText.isEmpty || viewModel.isLoading)
//            .opacity((viewModel.searchText.isEmpty || viewModel.isLoading) ? 0.5 : 1.0)
        }
    }
}


#Preview {
    SearchView()
        .environment(AppState.shared)
}
