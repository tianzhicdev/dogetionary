//
//  ReviewView.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//

import SwiftUI

struct ReviewView: View {
    @State private var currentWord: ReviewWord?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reviewStats: ReviewStats?
    @State private var isSessionComplete = false
    @State private var reviewStartTime: Date?
    @State private var dueCounts: DueCountsResponse?
    @State private var isLoadingCounts = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Always show overdue count at top
                if isLoadingCounts {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading counts...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                } else if let dueCounts = dueCounts {
                    OverdueCountView(dueCounts: dueCounts)
                        .padding(.horizontal)
                }
                
                if isLoading {
                    ProgressView("Loading review...")
                        .padding()
                } else if let currentWord = currentWord, !isSessionComplete {
                    ReviewSessionView(
                        currentWord: currentWord,
                        progress: "Review Mode",
                        onResponse: { response in
                            submitReview(response: response)
                        }
                    )
                } else if isSessionComplete {
                    ReviewCompleteView(
                        reviewStats: reviewStats,
                        onStartNewReview: startReview,
                        onStartAnyway: startReview
                    )
                } else {
                    StartReviewState(
                        dueCounts: dueCounts,
                        isLoadingCounts: isLoadingCounts,
                        onStart: startReview
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
                loadDueCounts()
            }
            .refreshable {
                await loadDueCountsAsync()
            }
        }
    }
    
    private func loadDueCounts() {
        isLoadingCounts = true
        errorMessage = nil
        
        DictionaryService.shared.getDueCounts { result in
            DispatchQueue.main.async {
                self.isLoadingCounts = false
                
                switch result {
                case .success(let counts):
                    self.dueCounts = counts
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func startReview() {
        isLoading = true
        errorMessage = nil
        
        DictionaryService.shared.getNextReviewWord { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let words):
                    if !words.isEmpty {
                        self.currentWord = words[0]
                        self.isSessionComplete = false
                        self.reviewStartTime = Date()
                    } else {
                        self.errorMessage = "No words available for review"
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    @MainActor
    private func loadDueCountsAsync() async {
        await withCheckedContinuation { continuation in
            loadDueCounts()
            continuation.resume()
        }
    }
    
    private func submitReview(response: Bool) {
        guard let currentWord = currentWord else { return }
        
        let responseTime = reviewStartTime.map { Int(Date().timeIntervalSince($0) * 1000) }
        
        DictionaryService.shared.submitReview(
            wordID: currentWord.id,
            response: response
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
        // Refresh due counts after each review
        loadDueCounts()
        
        // Get the next word to review
        isLoading = true
        DictionaryService.shared.getNextReviewWord { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let words):
                    if !words.isEmpty {
                        // Always use the next word returned by backend
                        self.currentWord = words[0]
                        self.reviewStartTime = Date()
                    } else {
                        // No more words - session complete
                        self.fetchReviewStats()
                    }
                case .failure(let error):
                    // Show error but don't end session
                    self.errorMessage = error.localizedDescription
                }
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
    
}

struct StartReviewState: View {
    let dueCounts: DueCountsResponse?
    let isLoadingCounts: Bool
    let onStart: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("Ready to Review")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let dueCounts = dueCounts {
                    if dueCounts.total_count > 0 {
                        Text("Ready to practice!")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No saved words yet. Save some words to start reviewing.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            
            Button("Start Review") {
                onStart()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled((dueCounts?.total_count ?? 0) == 0)
        }
        .padding()
    }
}

struct ReviewSessionView: View {
    let currentWord: ReviewWord
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
                    } else if isLoadingAudio && wordDefinitions.isEmpty {
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
        // Only show loading if we don't already have audio for this word
        if wordDefinitions.isEmpty || wordDefinitions.first?.word != currentWord.word {
            isLoadingAudio = true
            
            // Get user's learning language for audio
            let learningLanguage = UserManager.shared.learningLanguage
            
            DictionaryService.shared.fetchAudioForText(currentWord.word, language: learningLanguage) { audioData in
                DispatchQueue.main.async {
                    self.isLoadingAudio = false
                    
                    if let audioData = audioData {
                        // Create a simple definition with just the word and audio data
                        let definition = Definition(
                            id: UUID(),
                            word: self.currentWord.word,
                            phonetic: nil,
                            translations: [],
                            meanings: [],
                            audioData: audioData,
                            hasWordAudio: true,
                            exampleAudioAvailability: [:]
                        )
                        self.wordDefinitions = [definition]
                    }
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

struct OverdueCountView: View {
    let dueCounts: DueCountsResponse
    
    var body: some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundColor(dueCounts.overdue_count > 0 ? .orange : .green)
                .font(.caption)
            
            if dueCounts.overdue_count > 0 {
                Text("\(dueCounts.overdue_count) words overdue")
                    .font(.subheadline)
                    .foregroundColor(.orange)
            } else {
                Text("No overdue words")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
            
            Spacer()
            
            Text("\(dueCounts.total_count) total")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    ReviewView()
}
