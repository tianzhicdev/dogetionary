//
//  ReviewView.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//
//  Refactored by Claude Code on 12/5/25 - extracted inner views to separate files
//

import SwiftUI
import os.log

// MARK: - Main Review View

struct ReviewView: View {
    private static let logger = Logger(subsystem: "com.shojin.app", category: "ReviewView")
    // Queue manager for instant question loading
    @StateObject private var queueManager = QuestionQueueManager.shared

    // ViewModel
    @StateObject private var viewModel = ReviewViewModel()

    // Search ViewModel
    @StateObject private var searchViewModel = ReviewSearchViewModel()

    // App state for cross-view communication
    @Environment(AppState.self) private var appState

    // Search bar state (controlled by DailyProgressBanner in ContentView)
    @Binding var showSearchBar: Bool

    // Current question is now computed directly from queue - no caching
    private var currentQuestion: BatchReviewQuestion? {
        return queueManager.currentQuestion()
    }

    /// Generate stable, unique ID for SwiftUI view identity
    /// Uses video_id for video questions, saved_word_id for saved words, or combination for new words
    private func questionID(for question: BatchReviewQuestion) -> String {
        // Video questions: use video_id (always unique)
        if let videoId = question.question.video_id {
            return "video-\(videoId)"
        }

        // Saved words: use saved_word_id + type (unique per saved word)
        if let savedWordId = question.saved_word_id {
            return "saved-\(savedWordId)-\(question.question.question_type)"
        }

        // New words: use word + type + source (reasonably unique, duplicates prevented by queuedWords set)
        return "new-\(question.word)-\(question.question.question_type)-\(question.source)"
    }

    var body: some View {
        ZStack {
            // Gradient background
            AppTheme.verticalGradient2
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar overlay (shown when search button clicked)
                if showSearchBar {
                    searchBarView()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }

                // Main content area (fills remaining space)
                ZStack {
                    // Simple 2-state logic: Question OR Loading
                    // Backend always returns questions via 4-tier fallback (DUE → BUNDLE → EVERYDAY → RANDOM)
                    if let question = currentQuestion {
                        // State 1: Show question immediately
                        QuestionCardView(
                            question: question.question,
                            definition: question.definition,
                            word: question.word,
                            learningLanguage: question.learning_language,
                            nativeLanguage: question.native_language,
                            isAnswered: $viewModel.isAnswered,
                            wasCorrect: $viewModel.wasCorrect,
                            onImmediateFeedback: { isCorrect in
                                viewModel.showMiniCurveAnimation(isCorrect: isCorrect)
                            },
                            onAnswer: viewModel.handleAnswer,
                            onSwipeComplete: { viewModel.handleSwipeComplete(currentQuestion: currentQuestion) }
                        )
                        .id(questionID(for: question))
                        .offset(x: viewModel.cardOffset)
                        .opacity(viewModel.cardOpacity)
                    } else {
                        // State 2: Loading question from backend
                        ProgressView("LOADING QUESTION...")
                            .tint(AppTheme.accentCyan)
                            .foregroundColor(AppTheme.smallTitleText)
                    }

                    // Streaming prepend loading overlay
                    if searchViewModel.isStreamingPrepend {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .transition(.opacity)

                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(AppTheme.accentCyan)

                            VStack(spacing: 8) {
                                if searchViewModel.firstQuestionReady {
                                    Text("First video ready!")
                                        .font(.headline)
                                        .foregroundColor(AppTheme.white)

                                    Text("Preparing remaining videos...")
                                        .font(.subheadline)
                                        .foregroundColor(AppTheme.white.opacity(0.8))
                                } else {
                                    Text("Preparing videos...")
                                        .font(.headline)
                                        .foregroundColor(AppTheme.white)

                                    Text("This may take a moment")
                                        .font(.subheadline)
                                        .foregroundColor(AppTheme.white.opacity(0.8))
                                }

                                // Progress indicator
                                let (ready, total) = searchViewModel.streamProgress
                                Text("\(ready) of \(total) ready")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.white.opacity(0.6))
                            }
                        }
                        .padding(32)
                        .background(AppTheme.verticalGradient2)
                        .cornerRadius(16)
                        .shadow(radius: 10)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .errorToast(message: viewModel.errorMessage) {
                viewModel.errorMessage = nil
            }
        }
        .sheet(isPresented: $searchViewModel.showDefinitionSheet) {
            // Definition modal (same pattern as VideoQuestionView:231)
            if let definition = searchViewModel.currentDefinition {
                NavigationView {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Info banner: Videos being prepared
                            HStack(spacing: 12) {
                                Image(systemName: "film.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppTheme.accentCyan)

                                Text("Videos for **\(definition.word)** will appear shortly")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.bodyText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(
                                AppTheme.verticalGradient2.ignoresSafeArea())
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .padding(.top, 8)

                            DefinitionCard(definition: definition)
                                .padding(.horizontal)
                        }
                    }
                    .navigationTitle("Definition")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                searchViewModel.dismissDefinition()
                            }
                        }
                    }
                }
            }
        }
        .alert("Word Validation", isPresented: $searchViewModel.showValidationAlert) {
            if let suggestion = searchViewModel.validationSuggestion {
                Button(suggestion) {
                    searchViewModel.searchSuggestedWord {
                        withAnimation {
                            showSearchBar = false
                        }
                    }
                }
                Button("Yes, use original") {
                    searchViewModel.confirmOriginalWord()
                }
                Button("Cancel", role: .cancel) {
                    searchViewModel.cancelSearch()
                }
            } else {
                Button("Yes") {
                    searchViewModel.confirmOriginalWord()
                }
                Button("Cancel", role: .cancel) {
                    searchViewModel.cancelSearch()
                }
            }
        } message: {
            let confidence = searchViewModel.currentWordConfidence
            Text("This word seems unusual (confidence: \(Int(confidence * 100))%). Did you mean '\(searchViewModel.validationSuggestion ?? "")'?")
        }
        .onAppear {
            viewModel.loadPracticeStatus()

            // Refresh practice status when Practice tab appears
            Task {
                await UserManager.shared.refreshPracticeStatus()
            }
        }
        .refreshable {
            await viewModel.refreshPracticeStatus()
        }
        // Handle test settings changes via AppState
        .onChange(of: appState.testSettingsChanged) { _, changed in
            if changed {
                Self.logger.info("Test settings changed - refreshing question queue")
                queueManager.forceRefresh()
                viewModel.loadPracticeStatus()
            }
        }
    }

    // MARK: - Search Bar View

    @ViewBuilder
    private func searchBarView() -> some View {
        HStack(spacing: 12) {
            HStack {
                TextField("Search word...", text: $searchViewModel.searchText)
                    .font(.title2)
                    .foregroundColor(AppTheme.textFieldUserInput)
                    .onSubmit {
                        searchViewModel.searchWord {
                            // Close search bar when videos prepended
                            withAnimation {
                                showSearchBar = false
                            }
                        }
                    }

                if !searchViewModel.searchText.isEmpty {
                    Button(action: {
                        searchViewModel.searchText = ""
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
                searchViewModel.searchWord {
                    // Close search bar when videos prepended
                    withAnimation {
                        showSearchBar = false
                    }
                }
            }) {
                Image(systemName: "magnifyingglass")
                    .font(.headline)
                    .foregroundColor(AppTheme.bigButtonForeground1)
                    .frame(width: 50, height: 50)
                    .background(AppTheme.bigButtonBackground1)
                    .cornerRadius(10)
            }
            .disabled(searchViewModel.searchText.isEmpty || searchViewModel.isLoading)
        }
    }
}

#Preview {
    ReviewView(showSearchBar: .constant(false))
        .environment(AppState.shared)
}
