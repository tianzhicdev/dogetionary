//
//  WordDetailView.swift
//  dogetionary
//
//  Created by biubiu on 9/7/25.
//

import SwiftUI

struct WordDetailView: View {
    let savedWord: SavedWord
    @State private var selectedTab = 0
    @State private var definitions: [Definition] = []
    @State private var wordDetails: WordDetails?
    @State private var isLoadingDefinitions = false
    @State private var isLoadingStats = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ZStack {
            // Gradient background
            AppTheme.verticalGradient2
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom tab picker
                Picker("Tab", selection: $selectedTab) {
                    Text("DEFINITION").tag(0)
                    Text("PRACTICE STATS").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                // Tab content
                TabView(selection: $selectedTab) {
                // Definition tab
                DefinitionTabView(
                    savedWord: savedWord,
                    definitions: definitions,
                    isLoading: isLoadingDefinitions,
                    errorMessage: errorMessage
                )
                .tag(0)
                
                // Stats tab
                StatsTabView(
                    wordDetails: wordDetails,
                    isLoading: isLoadingStats,
                    errorMessage: errorMessage
                )
                .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
        }
        .navigationTitle(savedWord.word.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedTab == 0 {
                loadDefinitions()
            } else {
                loadWordDetails()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 0 && definitions.isEmpty {
                loadDefinitions()
            } else if newTab == 1 && wordDetails == nil {
                loadWordDetails()
            }
        }
        .onChange(of: appState.recentlyUnsavedWord) { _, unsavedWord in
            if let unsavedWord = unsavedWord,
               unsavedWord == savedWord.word {
                // Word was unsaved, dismiss this detail view
                dismiss()
            }
        }
    }
    
    private func loadDefinitions() {
        isLoadingDefinitions = true
        errorMessage = nil

        DictionaryService.shared.searchWord(
            savedWord.word,
            learningLanguage: savedWord.learning_language,
            nativeLanguage: savedWord.native_language
        ) { result in
            DispatchQueue.main.async {
                isLoadingDefinitions = false

                switch result {
                case .success(let definitions):
                    self.definitions = definitions
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func loadWordDetails() {
        isLoadingStats = true
        errorMessage = nil
        
        DictionaryService.shared.getWordDetails(wordID: savedWord.id) { result in
            DispatchQueue.main.async {
                isLoadingStats = false
                
                switch result {
                case .success(let details):
                    self.wordDetails = details
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct DefinitionTabView: View {
    let savedWord: SavedWord
    let definitions: [Definition]
    let isLoading: Bool
    let errorMessage: String?
    
    @State private var illustration: IllustrationResponse?
    @State private var isGeneratingIllustration = false
    @State private var illustrationError: String?
    @ObservedObject private var userManager = UserManager.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
//                // AI Illustration Section
//                AIIllustrationView(
//                    word: savedWord.word,
//                    language: userManager.learningLanguage,
//                    illustration: $illustration,
//                    isGenerating: $isGeneratingIllustration,
//                    error: $illustrationError
//                )
//                .padding(.horizontal)
                
                if isLoading {
                    ProgressView("Loading definitions...")
                        .padding()
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(AppTheme.warningColor)
                        Text("Error loading definitions")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(definitions) { (definition: Definition) in
                            DefinitionCard(definition: definition)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct StatsTabView: View {
    let wordDetails: WordDetails?
    let isLoading: Bool
    let errorMessage: String?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    ProgressView("Loading stats...")
                        .padding()
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(AppTheme.warningColor)
                        Text("Error loading stats")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if let details = wordDetails {
                    // Only show Forgetting Curve visualization
                    if !details.review_history.isEmpty {
                        ForgettingCurveView(
                            reviewHistory: details.review_history,
                            nextReviewDate: details.next_review_date,
                            createdAt: details.created_at,
                            wordId: details.id
                        )
                    } else {
                        EmptyHistorySection()
                    }
                    
                    if !details.review_history.isEmpty {
                        ReviewHistorySection(reviewHistory: details.review_history, createdAt: details.created_at)
                    }
                }
            }
            .padding()
        }
    }
}

struct WordInfoSection: View {
    let details: WordDetails
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Word Information")
            
            VStack(spacing: 12) {
                InfoRow(
                    label: "Word",
                    value: details.word,
                    style: .prominent
                )
                
                InfoRow(
                    label: "First Added",
                    value: formatDate(details.created_at, style: .full)
                )
                
                if let nextReviewDate = details.next_review_date {
                    InfoRow(
                        label: "Next Practice",
                        value: formatDate(nextReviewDate, style: .relative),
                        style: isOverdue(nextReviewDate) ? .warning : .normal
                    )
                }

                if let lastReviewed = details.last_reviewed_at {
                    InfoRow(
                        label: "Last Practice",
                        value: formatDate(lastReviewed, style: .relative)
                    )
                }
            }
        }
    }
    
    private func isOverdue(_ dateString: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return false }
        return date <= Date()
    }
}

struct ReviewHistorySection: View {
    let reviewHistory: [ReviewHistoryEntry]
    let createdAt: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Practice History")
            // Show practice history
            ForEach(Array(reviewHistory.enumerated()), id: \.offset) { index, entry in
                ReviewHistoryRow(
                    entry: entry,
                    reviewNumber: index + 1
                )
            }
            
            LazyVStack(spacing: 8) {
                // Show creation as the first entry
                HStack(spacing: 12) {
                    
                    // Creation icon
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(AppTheme.infoColor)
                    
                    // Date and details
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Created")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(AppTheme.infoColor)
                            
                            Spacer()
                            
                        
                            Text(formatDate(createdAt, style: .short))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                
            }
        }
    }
    
    private func formatDateShort(_ dateString: String) -> String {
        // Parse the date string
        let formatter = DateFormatter()
        
        // Try multiple formats
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]
        
        var date: Date?
        for format in formats {
            formatter.dateFormat = format
            if let parsedDate = formatter.date(from: dateString) {
                date = parsedDate
                break
            }
        }
        
        guard let date = date else { return dateString }
        
        // Format for display (short style to match ReviewHistoryRow)
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
}

struct ReviewHistoryRow: View {
    let entry: ReviewHistoryEntry
    let reviewNumber: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Review number
//            Text("\(reviewNumber)")
//                .font(.caption)
//                .fontWeight(.medium)
//                .foregroundColor(.secondary)
//                .frame(width: 20)
            
            // Success/Failure indicator
            Image(systemName: entry.response ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundColor(entry.response ? AppTheme.successColor : AppTheme.errorColor)
            
            // Date and details
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.response ? "Correct" : "Incorrect")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(entry.response ? AppTheme.successColor : AppTheme.errorColor)
                    
                    Spacer()
                    
                    Text(formatDate(entry.reviewed_at, style: .short))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let responseTime = entry.response_time_ms {
                    Text("Response time: \(formatResponseTime(responseTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private func formatResponseTime(_ ms: Int) -> String {
        let seconds = Double(ms) / 1000.0
        if seconds < 1.0 {
            return "\(ms)ms"
        } else {
            return String(format: "%.1fs", seconds)
        }
    }
}

struct ReviewStatsSection: View {
    let details: WordDetails
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Practice Statistics")

            VStack(spacing: 12) {
                InfoRow(
                    label: "Successful Practice",
                    value: "\(details.review_count)"
                )

                InfoRow(
                    label: "Total Practice",
                    value: "\(details.review_history.count)"
                )
                
                if !details.review_history.isEmpty {
                    let successRate = Double(details.review_history.filter { $0.response }.count) / Double(details.review_history.count)
                    InfoRow(
                        label: "Success Rate",
                        value: "\(Int(successRate * 100))%",
                        style: successRate >= 0.8 ? .success : (successRate >= 0.5 ? .normal : .warning)
                    )
                }
                
                InfoRow(
                    label: "Current Interval",
                    value: "\(details.interval_days) day\(details.interval_days == 1 ? "" : "s")"
                )
                
            }
        }
    }
}

struct EmptyHistorySection: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("No Practice Yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("This word hasn't been practiced yet. It will appear in your practice queue when due.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.warningColor)
            
            Text("Error Loading Details")
                .font(.headline)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.headline)
            .fontWeight(.semibold)
    }
}

struct InfoRow: View {
    enum Style {
        case normal
        case prominent
        case success
        case warning
    }
    
    let label: String
    let value: String
    let style: Style
    
    init(label: String, value: String, style: Style = .normal) {
        self.label = label
        self.value = value
        self.style = style
    }
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(style == .prominent ? .semibold : .medium)
                .foregroundColor(foregroundColor)
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .normal:
            return .primary
        case .prominent:
            return .primary
        case .success:
            return AppTheme.successColor
        case .warning:
            return AppTheme.warningColor
        }
    }
}

// MARK: - Date Formatting Helpers

private func formatDate(_ dateString: String, style: DateStyle) -> String {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: dateString) else {
        return dateString
    }
    
    switch style {
    case .full:
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .full
        displayFormatter.timeStyle = .medium  // Shows seconds precision max
        return displayFormatter.string(from: date)
        
    case .short:
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .medium  // Shows seconds precision max
        return displayFormatter.string(from: date)
        
    case .relative:
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < -86400 { // More than 1 day in the future
            let days = Int(-timeInterval / 86400)
            return "in \(days) day\(days == 1 ? "" : "s")"
        } else if timeInterval < -3600 { // More than 1 hour in the future
            let hours = Int(-timeInterval / 3600)
            return "in \(hours) hour\(hours == 1 ? "" : "s")"
        } else if timeInterval < 0 { // In the future but less than 1 hour
            return "soon"
        } else if timeInterval < 60 { // Less than 1 minute ago
            return "just now"
        } else if timeInterval < 3600 { // Less than 1 hour ago
            let minutes = Int(timeInterval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if timeInterval < 86400 { // Less than 1 day ago
            let hours = Int(timeInterval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else { // More than 1 day ago
            let days = Int(timeInterval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}

private enum DateStyle {
    case full
    case short
    case relative
}

#Preview {
    NavigationView {
        WordDetailView(savedWord: SavedWord(
            id: 1,
            word: "example",
            learning_language: "en",
            native_language: "zh",
            metadata: nil,
            created_at: "2025-09-06T10:00:00Z",
            review_count: 2,
            correct_reviews: 1,
            incorrect_reviews: 1,
            word_progress_level: 3,
            interval_days: 6,
            next_review_date: "2025-09-13",
            last_reviewed_at: "2025-09-07T14:30:00Z"
        ))
    }
}
