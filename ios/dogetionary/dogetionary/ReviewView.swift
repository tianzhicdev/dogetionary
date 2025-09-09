//
//  ReviewView.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//

import SwiftUI

struct ReviewView: View {
    @State private var dueWords: [SavedWord] = []
    @State private var currentWordIndex = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reviewStats: ReviewStats?
    @State private var isSessionComplete = false
    @State private var reviewStartTime: Date?
    @State private var reviewType: String = "regular"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading reviews...")
                        .padding()
                } else if dueWords.isEmpty && !isSessionComplete {
                    EmptyReviewState(
                        onStartAnyway: {
                            startAnywayReview()
                        }
                    )
                } else if isSessionComplete {
                    ReviewCompleteView(
                        reviewStats: reviewStats,
                        onStartNewReview: startNewReview,
                        onStartAnyway: startNewAnywayReview
                    )
                } else {
                    ReviewSessionView(
                        currentWord: dueWords[currentWordIndex],
                        progress: reviewType == "start_anyway" ? "Review Mode" : "\(currentWordIndex + 1) of \(dueWords.count)",
                        onResponse: { response in
                            submitReview(response: response)
                        }
                    )
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("Review")
            .onAppear {
                loadDueWords()
            }
            .refreshable {
                await loadDueWordsAsync()
            }
        }
    }
    
    private func loadDueWords() {
        isLoading = true
        errorMessage = nil
        reviewType = "regular"
        
        DictionaryService.shared.getDueWords { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let words):
                    self.dueWords = words
                    self.currentWordIndex = 0
                    self.isSessionComplete = false
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func startAnywayReview() {
        isLoading = true
        errorMessage = nil
        reviewType = "start_anyway"
        
        DictionaryService.shared.getNextDueWords(limit: 1) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let words):
                    self.dueWords = words
                    self.currentWordIndex = 0
                    self.isSessionComplete = false
                    self.reviewStartTime = Date()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    @MainActor
    private func loadDueWordsAsync() async {
        await withCheckedContinuation { continuation in
            loadDueWords()
            continuation.resume()
        }
    }
    
    private func submitReview(response: Bool) {
        guard currentWordIndex < dueWords.count else { return }
        
        let currentWord = dueWords[currentWordIndex]
        let responseTime = reviewStartTime.map { Int(Date().timeIntervalSince($0) * 1000) }
        
        DictionaryService.shared.submitReview(
            wordID: currentWord.id,
            response: response,
            responseTimeMS: responseTime,
            reviewType: reviewType
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    self.moveToNextWord()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func moveToNextWord() {
        if reviewType == "start_anyway" {
            // For "start anyway" mode, fetch next word one by one
            isLoading = true
            DictionaryService.shared.getNextDueWords(limit: 1) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success(let words):
                        if !words.isEmpty {
                            // Continue with next word
                            self.dueWords = words
                            self.currentWordIndex = 0
                            self.reviewStartTime = Date()
                        } else {
                            // No more words - session complete
                            self.fetchReviewStats()
                        }
                    case .failure:
                        // End session on error
                        self.fetchReviewStats()
                    }
                }
            }
        } else {
            // Regular review mode - use batched words
            if currentWordIndex + 1 < dueWords.count {
                currentWordIndex += 1
                reviewStartTime = Date()
            } else {
                // Session complete - fetch updated stats
                fetchReviewStats()
            }
        }
    }
    
    private func fetchReviewStats() {
        DictionaryService.shared.getReviewStats { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let stats):
                    self.reviewStats = stats
                    self.isSessionComplete = true
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.isSessionComplete = true // Show completion even if stats fail
                }
            }
        }
    }
    
    private func startNewReview() {
        loadDueWords()
    }
    
    private func startNewAnywayReview() {
        startAnywayReview()
    }
}

struct EmptyReviewState: View {
    let onStartAnyway: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Reviews Due")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Great job! Come back tomorrow to continue learning.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                Text("Want to practice anyway?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button("Start Anyway") {
                    onStartAnyway()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Text("Reviews words one by one using an alternative scheduling algorithm. You can exit anytime.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}

struct ReviewSessionView: View {
    let currentWord: SavedWord
    let progress: String
    let onResponse: (Bool) -> Void
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var wordDefinitions: [Definition] = []
    @State private var isLoadingAudio = false
    @State private var hasAnswered = false
    @State private var userResponse: Bool? = nil
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            HStack {
                Text(progress)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            
            // Word card
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(currentWord.word)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    // Audio play button
                    if !wordDefinitions.isEmpty, let audioData = wordDefinitions.first?.audioData {
                        Button(action: {
                            if audioPlayer.isPlaying {
                                audioPlayer.stopAudio()
                            } else {
                                audioPlayer.playAudio(from: audioData)
                            }
                        }) {
                            HStack {
                                Image(systemName: audioPlayer.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                Text("Pronunciation")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else if isLoadingAudio {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading audio...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 32)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .cornerRadius(16)
            .padding(.horizontal)
            
            // Show definitions if user answered "No"
            if hasAnswered && userResponse == false && !wordDefinitions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(wordDefinitions) { definition in
                            DefinitionCard(definition: definition)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
            }
            
            // Question or instruction
            if !hasAnswered {
                Text("Do you know this word?")
                    .font(.title2)
                    .fontWeight(.medium)
                    .padding(.horizontal)
            }
            
            // Response buttons
            if !hasAnswered {
                HStack(spacing: 20) {
                    // No button
                    Button(action: {
                        userResponse = false
                        hasAnswered = true
                    }) {
                        HStack {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .fontWeight(.medium)
                            Text("No")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Yes button
                    Button(action: {
                        userResponse = true
                        hasAnswered = true
                        onResponse(true)
                    }) {
                        HStack {
                            Image(systemName: "checkmark")
                                .font(.title3)
                                .fontWeight(.medium)
                            Text("Yes")
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
            } else {
                // Next button after answering
                Button(action: {
                    if let response = userResponse {
                        onResponse(response)
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.right")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Next")
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .onAppear {
            loadWordAudio()
        }
        .onChange(of: currentWord.word) { _, newWord in
            // Reset state when word changes
            wordDefinitions = []
            hasAnswered = false
            userResponse = nil
            loadWordAudio()
        }
    }
    
    private func loadWordAudio() {
        isLoadingAudio = true
        
        DictionaryService.shared.searchWord(currentWord.word) { result in
            DispatchQueue.main.async {
                isLoadingAudio = false
                
                switch result {
                case .success(let definitions):
                    wordDefinitions = definitions
                case .failure(_):
                    // Silently fail - audio is optional
                    break
                }
            }
        }
    }
}

struct ReviewCompleteView: View {
    let reviewStats: ReviewStats?
    let onStartNewReview: () -> Void
    let onStartAnyway: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Review Complete!")
                .font(.title)
                .fontWeight(.bold)
            
            if let stats = reviewStats {
                VStack(spacing: 12) {
                    StatRow(label: "Words reviewed today", value: "\(stats.reviews_today)")
                    StatRow(label: "Total words", value: "\(stats.total_words)")
                    StatRow(label: "Success rate (7 days)", value: "\(Int(stats.success_rate_7_days * 100))%")
                    StatRow(label: "Current streak", value: "\(stats.streak_days) days")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            VStack(spacing: 12) {
                Button("Check for New Reviews") {
                    onStartNewReview()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Continue Review Mode") {
                    onStartAnyway()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.blue)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    ReviewView()
}