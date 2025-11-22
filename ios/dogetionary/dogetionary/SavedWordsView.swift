//
//  SavedWordsView.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import SwiftUI

struct SavedWordsView: View {
    @State private var savedWords: [SavedWord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSchedule = false
    @State private var selectedView = 0  // 0 = Schedule, 1 = Words

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented control for switching views (only show if user has schedule)
                if hasSchedule {
                    Picker("View", selection: $selectedView) {
                        Text("Schedule").tag(0)
                        Text("Words").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.systemBackground))
                }

                // Content based on selection
                if selectedView == 0 && hasSchedule {
                    ScheduleView()
                } else {
                    SavedWordsListView(
                        savedWords: $savedWords,
                        isLoading: isLoading,
                        errorMessage: errorMessage,
                        onRefresh: { await loadSavedWords() },
                        onDelete: { word in await deleteSavedWord(word) },
                        onToggleKnown: { word in await toggleKnownStatus(word) }
                    )
                }
            }
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            Task {
                await loadSavedWords()
                checkSchedule()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshSavedWords)) { _ in
            Task {
                await loadSavedWords()
                checkSchedule()
            }
        }
    }
    
    @MainActor
    private func loadSavedWords() async {
        isLoading = true
        errorMessage = nil

        await withCheckedContinuation { continuation in
            DictionaryService.shared.getSavedWords { result in
                DispatchQueue.main.async {
                    self.isLoading = false

                    switch result {
                    case .success(let words):
                        // Sort: known words at bottom, then by next_review_date ascending
                        self.savedWords = words.sorted { word1, word2 in
                            // Known words go to the bottom
                            if word1.is_known != word2.is_known {
                                return !word1.is_known // non-known words first
                            }

                            // Within same known status, sort by next_review_date
                            guard let date1 = word1.next_review_date else { return false }
                            guard let date2 = word2.next_review_date else { return true }

                            // Parse dates and compare
                            let formatter = ISO8601DateFormatter()
                            guard let d1 = formatter.date(from: date1),
                                  let d2 = formatter.date(from: date2) else { return false }

                            return d1 < d2
                        }
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }

                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func deleteSavedWord(_ word: SavedWord) async {
        DictionaryService.shared.unsaveWord(wordID: word.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Remove word from local array
                    self.savedWords.removeAll { $0.id == word.id }

                    // Track deletion analytics
                    AnalyticsManager.shared.track(action: .savedDeleteWord, metadata: [
                        "word": word.word,
                        "word_id": word.id
                    ])
                case .failure(let error):
                    self.errorMessage = "Failed to delete word: \(error.localizedDescription)"
                }
            }
        }
    }

    private func checkSchedule() {
        DictionaryService.shared.getTodaySchedule { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let entry):
                    // Use user_has_schedule (whether user created any schedule)
                    // NOT has_schedule (whether today has tasks)
                    self.hasSchedule = entry.user_has_schedule ?? entry.has_schedule
                case .failure:
                    self.hasSchedule = false
                }
            }
        }
    }

    @MainActor
    private func toggleKnownStatus(_ word: SavedWord) async {
        let newKnownStatus = !word.is_known
        DictionaryService.shared.markWordAsKnown(wordID: word.id, isKnown: newKnownStatus) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Update local state
                    if let index = self.savedWords.firstIndex(where: { $0.id == word.id }) {
                        self.savedWords[index].is_known = newKnownStatus
                    }

                    // Re-sort to move known words to bottom
                    self.savedWords.sort { word1, word2 in
                        if word1.is_known != word2.is_known {
                            return !word1.is_known
                        }
                        guard let date1 = word1.next_review_date else { return false }
                        guard let date2 = word2.next_review_date else { return true }
                        let formatter = ISO8601DateFormatter()
                        guard let d1 = formatter.date(from: date1),
                              let d2 = formatter.date(from: date2) else { return false }
                        return d1 < d2
                    }

                    // Track analytics
                    AnalyticsManager.shared.track(
                        action: newKnownStatus ? .savedMarkKnown : .savedMarkLearning,
                        metadata: ["word": word.word, "word_id": word.id]
                    )
                case .failure(let error):
                    self.errorMessage = "Failed to update word: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct SavedWordsListView: View {
    @Binding var savedWords: [SavedWord]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () async -> Void
    let onDelete: (SavedWord) async -> Void
    let onToggleKnown: (SavedWord) async -> Void

    @State private var filterText = ""

    private var filteredWords: [SavedWord] {
        if filterText.isEmpty {
            return savedWords
        } else {
            return savedWords.filter { $0.word.lowercased().contains(filterText.lowercased()) }
        }
    }

    var body: some View {
        ZStack {
            // Soft blue gradient background
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Group {
                if isLoading {
                    ProgressView("Loading saved words...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if savedWords.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No Saved Words")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Words you save will appear here")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Filter text bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Filter words...", text: $filterText)
                                .font(.body)
                            if !filterText.isEmpty {
                                Button(action: {
                                    filterText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        // Word list
                        ScrollView {
                            LazyVStack(spacing: AppTheme.cardSpacing) {
                                ForEach(filteredWords) { savedWord in
                                    NavigationLink(destination: WordDetailView(savedWord: savedWord)
                                        .onAppear {
                                            // Track saved word view details when navigation happens
                                            AnalyticsManager.shared.track(action: .savedViewDetails, metadata: [
                                                "word": savedWord.word,
                                                "review_count": savedWord.review_count,
                                                "is_overdue": isOverdue(savedWord.next_review_date ?? "")
                                            ])
                                        }
                                    ) {
                                        SavedWordRow(
                                            savedWord: savedWord,
                                            onToggleKnown: { Task { await onToggleKnown(savedWord) } },
                                            onDelete: { Task { await onDelete(savedWord) } }
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .refreshable {
            await onRefresh()
        }
    }

    private func isOverdue(_ dateString: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            return date < Date()
        }
        return false
    }
}

struct StatsView: View {
    @State private var reviewDates: Set<String> = []
    @State private var progressData: ProgressFunnelData?
    @State private var reviewStats: ReviewStatsData?
    @State private var weeklyReviews: [DailyReviewCount] = []
    @State private var isLoading = false
    @State private var currentDate = Date()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Progress Funnel at top
                if let progressData = progressData {
                    HorizontalProgressBarChart(data: progressData)
                        .padding(.horizontal)
                        .padding(.top)
                }
                
                // Stats Cards
                if let stats = reviewStats {
                    StatsCardsView(stats: stats)
                        .padding(.horizontal)
                }
                
                // Weekly Practice Chart
                if !weeklyReviews.isEmpty {
                    WeeklyReviewChart(dailyCounts: weeklyReviews)
                        .padding(.horizontal)
                }
                
                // Calendar with integrated navigation
                VStack(spacing: 0) {
                    HStack {
                        Button(action: {
                            currentDate = Calendar.current.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
                            loadReviewDates()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.leading)
                        
                        Spacer()
                        
                        Text(monthYearString(from: currentDate))
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Button(action: {
                            currentDate = Calendar.current.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
                            loadReviewDates()
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.trailing)
                    }
                    .padding(.vertical, 8)
                    
                    MonthlyCalendarView(
                        currentDate: $currentDate,
                        reviewDates: reviewDates
                    )
                }
                
                Spacer(minLength: 40)
            }
        }
        .onAppear {
            loadReviewDates()
            loadProgressData()
            loadReviewStats()
            loadWeeklyReviews()
        }
        .onChange(of: currentDate) { _, _ in
            loadReviewDates()
        }
    }
    
    private func loadReviewDates() {
        isLoading = true
        
        let calendar = Calendar.current
        let startOfMonth = calendar.dateInterval(of: .month, for: currentDate)?.start ?? currentDate
        let endOfMonth = calendar.dateInterval(of: .month, for: currentDate)?.end ?? currentDate
        
        DictionaryService.shared.getReviewActivity(from: startOfMonth, to: endOfMonth) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let dates):
                    self.reviewDates = Set(dates)
                case .failure(let error):
                    print("Failed to load review dates: \(error)")
                    self.reviewDates = []
                }
            }
        }
    }
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func loadProgressData() {
        DictionaryService.shared.getProgressFunnelData { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    self.progressData = data
                case .failure(let error):
                    print("Failed to load progress data: \(error)")
                    self.progressData = nil
                }
            }
        }
    }
    
    private func loadReviewStats() {
        DictionaryService.shared.getReviewStatistics { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let stats):
                    self.reviewStats = stats
                case .failure(let error):
                    print("Failed to load review stats: \(error)")
                }
            }
        }
    }
    
    private func loadWeeklyReviews() {
        DictionaryService.shared.getWeeklyReviewCounts { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let counts):
                    self.weeklyReviews = counts
                case .failure(let error):
                    print("Failed to load weekly reviews: \(error)")
                }
            }
        }
    }
}

struct ReviewStatsData: Codable {
    let total_reviews: Int
    let avg_reviews_per_week: Double
    let avg_reviews_per_active_day: Double
    let week_over_week_change: Double
}

struct DailyReviewCount: Codable, Identifiable {
    let date: String
    let count: Int
    
    var id: String { date }
}

struct StatsCardsView: View {
    let stats: ReviewStatsData
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Total Practice", value: "\(stats.total_reviews)", icon: "checkmark.circle.fill", color: .blue)
            StatCard(title: "Week Change", value: String(format: "%+.0f%%", stats.week_over_week_change), icon: stats.week_over_week_change >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill", color: stats.week_over_week_change >= 0 ? .green : .red)
            StatCard(title: "Avg/Week", value: String(format: "%.1f", stats.avg_reviews_per_week), icon: "calendar", color: .green)
            StatCard(title: "Avg/Day", value: String(format: "%.1f", stats.avg_reviews_per_active_day), icon: "chart.bar.fill", color: .purple)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

struct WeeklyReviewChart: View {
    let dailyCounts: [DailyReviewCount]
    
    private var maxCount: Int {
        dailyCounts.map { $0.count }.max() ?? 1
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(dailyCounts) { day in
                    VStack(spacing: 4) {
                        // Count on top of bar
                        Text("\(day.count)")
                            .font(.caption2)
                            .fontWeight(.medium)
                        
                        // Bar
                        Rectangle()
                            .fill(Color.blue.opacity(0.7))
                            .frame(height: CGFloat(day.count) / CGFloat(maxCount) * 50)
                            .cornerRadius(4)
                        
                        // Day label
                        Text(dayLabel(from: day.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 100)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private func dayLabel(from dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: dateString) {
            formatter.dateFormat = "E"
            return formatter.string(from: date)
        }
        return ""
    }
}

struct ProgressFunnelData: Codable {
    let stage1_count: Int  // Any successful review
    let stage2_count: Int  // 2+ continuous successes in past 7 days
    let stage3_count: Int  // 3+ successes in past 14 days
    let stage4_count: Int  // 4+ successes in past 28 days
    let total_words: Int
}

struct HorizontalProgressBarChart: View {
    let data: ProgressFunnelData
    
    private let stageLabels = ["Recognized", "Familiar", "Remembered", "Unforgettable"]
    
    private func greenColor(for index: Int) -> Color {
        // Light green to dark green gradient
        let greenValues: [Color] = [
            Color(red: 0.6, green: 0.9, blue: 0.6),  // Light green
            Color(red: 0.4, green: 0.8, blue: 0.4),  // Medium-light green
            Color(red: 0.2, green: 0.7, blue: 0.2),  // Medium-dark green
            Color(red: 0.0, green: 0.6, blue: 0.0)   // Dark green
        ]
        return greenValues[index]
    }
    
    private var maxCount: Int {
        max(data.stage1_count, data.stage2_count, data.stage3_count, data.stage4_count, 1)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack (alignment: .bottom, spacing: 4){
                ForEach(0..<4) { index in
                    let counts = [data.stage1_count, data.stage2_count, data.stage3_count, data.stage4_count]
                    let count = counts[index]
                    
                    VStack(spacing: 4) {
                        // Bar with count on top
//                        VStack(spacing: 2) {
                            // Count on top of bar
                            Text("\(count)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                            
                            // Bar
//                            VStack {
//                                Spacer(minLength: 0)
                                Rectangle()
                                    .fill(greenColor(for: index))
                                    .frame(height: CGFloat(count) / CGFloat(maxCount) * 80)
                                    .cornerRadius(4)
//                            }
//                            .frame(height: 80)
//                        }
                        
                        // Label
                        Text(stageLabels[index])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
//                    VStack(spacing: 4) {
//                        // Count on top of bar
//                        Text("\(day.count)")
//                            .font(.caption2)
//                            .fontWeight(.medium)
//                        
//                        // Bar
//                        Rectangle()
//                            .fill(Color.blue.opacity(0.7))
//                            .frame(height: CGFloat(day.count) / CGFloat(maxCount) * 50)
//                            .cornerRadius(4)
//                        
//                        // Day label
//                        Text(dayLabel(from: day.date))
//                            .font(.caption2)
//                            .foregroundColor(.secondary)
//                    }
                    
                    if index < 3 {
                        Spacer()
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// Removed ProgressSegment - replaced with bar chart


struct MonthlyCalendarView: View {
    @Binding var currentDate: Date
    let reviewDates: Set<String>
    
    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 8) {
            // Days of week header
            HStack {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { daySymbol in
                    Text(daySymbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        CalendarDayView(
                            date: date,
                            hasReview: reviewDates.contains(dateFormatter.string(from: date)),
                            isToday: calendar.isDateInToday(date),
                            isCurrentMonth: calendar.isDate(date, equalTo: currentDate, toGranularity: .month)
                        )
                    } else {
                        // Empty cell for padding
                        Text("")
                            .frame(width: 36, height: 36)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDate),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start) else {
            return []
        }
        
        let monthLastDay = calendar.date(byAdding: DateComponents(day: -1), to: monthInterval.end)!
        guard let monthLastWeek = calendar.dateInterval(of: .weekOfYear, for: monthLastDay) else {
            return []
        }
        
        var days: [Date?] = []
        var current = monthFirstWeek.start
        
        while current <= monthLastWeek.end {
            if calendar.isDate(current, equalTo: currentDate, toGranularity: .month) {
                days.append(current)
            } else {
                days.append(nil)
            }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        
        return days
    }
}

struct CalendarDayView: View {
    let date: Date
    let hasReview: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(backgroundColor)
                .frame(width: 32, height: 32)
            
            // Day number
            Text(dayFormatter.string(from: date))
                .font(.system(size: 14, weight: textWeight))
                .foregroundColor(textColor)
        }
        .frame(width: 36, height: 36)
        .opacity(isCurrentMonth ? 1.0 : 0.3)
    }
    
    private var backgroundColor: Color {
        if hasReview {
            return Color.green.opacity(0.8)
        } else if isToday {
            return Color.blue.opacity(0.3)
        } else {
            return Color.clear
        }
    }
    
    private var textColor: Color {
        if hasReview {
            return .white
        } else if isToday {
            return .blue
        } else {
            return .primary
        }
    }
    
    private var textWeight: Font.Weight {
        if hasReview || isToday {
            return .semibold
        } else {
            return .regular
        }
    }
}

struct SavedWordRow: View {
    let savedWord: SavedWord
    var onToggleKnown: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @ObservedObject private var userManager = UserManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // Word name with test badges
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(savedWord.word)
                        .font(AppTheme.titleFont)
                        .foregroundColor(.primary)

                    // Show test labels only if user has enabled tests
                    testLabels
                }

                // Review counts
                HStack(spacing: 8) {
                    // Incorrect reviews
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.4))
                        Text("\(savedWord.incorrect_reviews)")
                            .font(AppTheme.badgeLabelFont)
                            .foregroundColor(.secondary)
                    }

                    // Correct reviews
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.testPracticeColor)
                        Text("\(savedWord.correct_reviews)")
                            .font(AppTheme.badgeLabelFont)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // 7-box progress bar (from backend: 1-7 scale)
            WordProgressBar(progressLevel: savedWord.word_progress_level)

            // Action menu button
            if onToggleKnown != nil || onDelete != nil {
                Menu {
                    if let onToggleKnown = onToggleKnown {
                        Button {
                            onToggleKnown()
                        } label: {
                            if savedWord.is_known {
                                Label("Still Learning", systemImage: "book.fill")
                            } else {
                                Label("Already Learned", systemImage: "checkmark.circle.fill")
                            }
                        }
                    }

                    if let onDelete = onDelete {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(AppTheme.cardPadding)
        .background(savedWord.is_known ? Color(red: 0.9, green: 0.98, blue: 0.9) : AppTheme.cardBackground)
        .cornerRadius(AppTheme.cardCornerRadius)
        .shadow(color: AppTheme.cardShadowColor, radius: AppTheme.cardShadowRadius, x: 0, y: 2)
    }

    @ViewBuilder
    private var testLabels: some View {
        HStack(spacing: 4) {
            if userManager.toeflEnabled && (savedWord.is_toefl == true) {
                Text("TOEFL")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(4)
            }

            if userManager.ieltsEnabled && (savedWord.is_ielts == true) {
                Text("IELTS")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.4, green: 0.8, blue: 0.6), Color.green],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(4)
            }
        }
    }
}

// MARK: - 7-Box Progress Bar

struct WordProgressBar: View {
    let progressLevel: Int  // 1-7 scale from backend

    // Color for each box based on index and progress level
    private func colorForBox(at index: Int) -> LinearGradient {
        // Boxes are filled from left to right up to progressLevel
        let isFilled = (index + 1) <= progressLevel

        if !isFilled {
            // Empty box - light gray
            return LinearGradient(
                colors: [Color(red: 0.92, green: 0.94, blue: 0.97), Color(red: 0.88, green: 0.90, blue: 0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        // Filled boxes: red (1-2), yellow (3-5), green (6-7)
        let boxNumber = index + 1
        if boxNumber <= 2 {
            // Red boxes (low progress)
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.4, blue: 0.4), Color(red: 0.9, green: 0.3, blue: 0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if boxNumber <= 5 {
            // Yellow boxes (medium progress)
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.8, blue: 0.2), Color(red: 0.95, green: 0.7, blue: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            // Green boxes (high progress)
            return LinearGradient(
                colors: [Color(red: 0.4, green: 0.8, blue: 0.5), Color(red: 0.3, green: 0.7, blue: 0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(colorForBox(at: index))
                    .frame(width: 8, height: 24)
            }
        }
    }
}

#Preview {
    SavedWordsView()
}
