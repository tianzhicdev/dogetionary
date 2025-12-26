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
//                .background(.clear)
//                .foregroundStyle(AppTheme.buttonForegroundCyan)

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
        .errorToast(message: errorMessage) {
            errorMessage = nil
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Customize segmented control colors using UIKit appearance API
            let appearance = UISegmentedControl.appearance()

            // Selected segment background (cyan)
            appearance.selectedSegmentTintColor = UIColor(AppTheme.bodyText)

            // Unselected text color (cyan)
            appearance.setTitleTextAttributes([
                .foregroundColor: UIColor(AppTheme.bodyText)
            ], for: .normal)

            // Selected text color (white for contrast on cyan background)
            appearance.setTitleTextAttributes([
                .foregroundColor: UIColor.white
            ], for: .selected)

            // Background of entire control (transparent for dark gradient)
            appearance.backgroundColor = UIColor.clear

            // Load data
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
                    ProgressView()
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
                    ProgressView()
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
                        EmptyStateView(
                            icon: "clock",
                            title: "No Practice Yet",
                            message: "This word hasn't been practiced yet. It will appear in your practice queue when due."
                        )
                        .padding(.vertical, 24)
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


struct ReviewHistorySection: View {
    let reviewHistory: [ReviewHistoryEntry]
    let createdAt: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("Practice History")
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
                                .foregroundColor(AppTheme.selectableTint)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                
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
                        .foregroundColor(AppTheme.selectableTint)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
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
            SectionHeader("Practice Statistics")

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

// MARK: - Preview Data

private struct PreviewData {
    static var wordDetailsWithHistory: WordDetails {
        let json = """
        {
            "id": 1,
            "word": "ephemeral",
            "learning_language": "en",
            "created_at": "2025-09-01T10:00:00Z",
            "review_count": 5,
            "interval_days": 8,
            "next_review_date": "2025-12-15T10:00:00Z",
            "last_reviewed_at": "2025-12-07T14:30:00Z",
            "review_history": [
                {
                    "response": true,
                    "response_time_ms": 3500,
                    "reviewed_at": "2025-09-01T10:00:00Z"
                },
                {
                    "response": true,
                    "response_time_ms": 2800,
                    "reviewed_at": "2025-09-02T10:00:00Z"
                },
                {
                    "response": false,
                    "response_time_ms": 5200,
                    "reviewed_at": "2025-09-04T10:00:00Z"
                },
                {
                    "response": true,
                    "response_time_ms": 2100,
                    "reviewed_at": "2025-09-05T10:00:00Z"
                },
                {
                    "response": true,
                    "response_time_ms": 1900,
                    "reviewed_at": "2025-12-07T14:30:00Z"
                },
                {
                    "response": true,
                    "response_time_ms": 1650,
                    "reviewed_at": "2025-12-08T09:15:00Z"
                }
            ]
        }
        """
        return try! JSONDecoder().decode(WordDetails.self, from: json.data(using: .utf8)!)
    }

    static var wordDetailsNoHistory: WordDetails {
        let json = """
        {
            "id": 2,
            "word": "serendipity",
            "learning_language": "en",
            "created_at": "2025-12-08T10:00:00Z",
            "review_count": 0,
            "interval_days": 0,
            "next_review_date": null,
            "last_reviewed_at": null,
            "review_history": []
        }
        """
        return try! JSONDecoder().decode(WordDetails.self, from: json.data(using: .utf8)!)
    }
}

// MARK: - Previews

#Preview("Word Detail - Full View") {
    NavigationStack {
        WordDetailView(savedWord: SavedWord(
            id: 1,
            word: "ephemeral",
            learning_language: "en",
            native_language: "zh",
            metadata: nil,
            created_at: "2025-09-06T10:00:00Z",
            review_count: 5,
            correct_reviews: 4,
            incorrect_reviews: 1,
            word_progress_level: 3,
            interval_days: 8,
            next_review_date: "2025-12-15T10:00:00Z",
            last_reviewed_at: "2025-12-07T14:30:00Z"
        ))
    }
    .environment(AppState.shared)
}

#Preview("Definition Tab - Loading") {
    NavigationStack {
        ZStack {
            AppTheme.verticalGradient2.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Tab", selection: .constant(0)) {
                    Text("DEFINITION").tag(0)
                    Text("PRACTICE STATS").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                DefinitionTabView(
                    savedWord: SavedWord(
                        id: 1,
                        word: "ephemeral",
                        learning_language: "en",
                        native_language: "zh",
                        metadata: nil,
                        created_at: "2025-09-06T10:00:00Z",
                        review_count: 0,
                        correct_reviews: 0,
                        incorrect_reviews: 0,
                        word_progress_level: 0,
                        interval_days: 0,
                        next_review_date: nil,
                        last_reviewed_at: nil
                    ),
                    definitions: [],
                    isLoading: true,
                    errorMessage: nil
                )
            }
        }
    }
    .environment(AppState.shared)
}

#Preview("Definition Tab - With Error") {
    NavigationStack {
        ZStack {
            AppTheme.verticalGradient2.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Tab", selection: .constant(0)) {
                    Text("DEFINITION").tag(0)
                    Text("PRACTICE STATS").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
//                .tint(AppTheme.selectableTint)
                .foregroundStyle(AppTheme.selectableTint)
                .padding()

                DefinitionTabView(
                    savedWord: SavedWord(
                        id: 1,
                        word: "xyzabc",
                        learning_language: "en",
                        native_language: "zh",
                        metadata: nil,
                        created_at: "2025-09-06T10:00:00Z",
                        review_count: 0,
                        correct_reviews: 0,
                        incorrect_reviews: 0,
                        word_progress_level: 0,
                        interval_days: 0,
                        next_review_date: nil,
                        last_reviewed_at: nil
                    ),
                    definitions: [],
                    isLoading: false,
                    errorMessage: "Word not found in dictionary"
                )
            }
        }
    }
    .environment(AppState.shared)
}

#Preview("Stats Tab - With Data") {
    NavigationStack {
        ZStack {
            AppTheme.verticalGradient2.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Tab", selection: .constant(1)) {
                    Text("DEFINITION").tag(0)
                    Text("PRACTICE STATS").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                ScrollView {
                    StatsTabView(
                        wordDetails: PreviewData.wordDetailsWithHistory,
                        isLoading: false,
                        errorMessage: nil
                    )
                }
            }
        }
    }
    .environment(AppState.shared)
}

#Preview("Stats Tab - No History") {
    NavigationStack {
        ZStack {
            AppTheme.verticalGradient2.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Tab", selection: .constant(1)) {
                    Text("DEFINITION").tag(0)
                    Text("PRACTICE STATS").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                StatsTabView(
                    wordDetails: PreviewData.wordDetailsNoHistory,
                    isLoading: false,
                    errorMessage: nil
                )
            }
        }
    }
    .environment(AppState.shared)
}

#Preview("Stats Tab - Loading") {
    NavigationStack {
        ZStack {
            AppTheme.verticalGradient2.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Tab", selection: .constant(1)) {
                    Text("DEFINITION").tag(0)
                    Text("PRACTICE STATS").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                StatsTabView(
                    wordDetails: nil,
                    isLoading: true,
                    errorMessage: nil
                )
            }
        }
    }
    .environment(AppState.shared)
}

#Preview("Stats Tab - Error") {
    NavigationStack {
        ZStack {
            AppTheme.verticalGradient2.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Tab", selection: .constant(1)) {
                    Text("DEFINITION").tag(0)
                    Text("PRACTICE STATS").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                StatsTabView(
                    wordDetails: nil,
                    isLoading: false,
                    errorMessage: "Failed to load word details"
                )
            }
        }
    }
    .environment(AppState.shared)
}
