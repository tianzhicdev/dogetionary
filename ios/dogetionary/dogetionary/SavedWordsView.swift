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
    
    var body: some View {
        NavigationView {
            TabView {
                // Stats Tab (now first)
                StatsView()
                    .tabItem {
                        Image(systemName: "chart.bar.fill")
                        Text("Stats")
                    }
                
                // Words Tab
                SavedWordsListView(
                    savedWords: savedWords,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    onRefresh: { await loadSavedWords() }
                )
                .tabItem {
                    Image(systemName: "list.bullet")
                    Text("Words")
                }
            }
            .onAppear {
                Task {
                    await loadSavedWords()
                }
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
                        // Sort by next_review_date ascending (soonest first)
                        self.savedWords = words.sorted { word1, word2 in
                            // Handle nil values - put words without reviews at the end
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
}

struct SavedWordsListView: View {
    let savedWords: [SavedWord]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () async -> Void
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading saved words...")
                    .padding()
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
            } else {
                List(savedWords) { savedWord in
                    NavigationLink(destination: WordDetailView(savedWord: savedWord)) {
                        SavedWordRow(savedWord: savedWord)
                    }
                }
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .refreshable {
            await onRefresh()
        }
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
                
                // Weekly Review Chart
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
    let streak_days: Int
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
            StatCard(title: "Total Reviews", value: "\(stats.total_reviews)", icon: "checkmark.circle.fill", color: .blue)
            StatCard(title: "Streak", value: "\(stats.streak_days) days", icon: "flame.fill", color: .orange)
            StatCard(title: "Avg/Week", value: String(format: "%.1f", stats.avg_reviews_per_week), icon: "calendar", color: .green)
            StatCard(title: "Avg/Day", value: String(format: "%.1f", stats.avg_reviews_per_active_day), icon: "chart.bar.fill", color: .purple)
        }
        
        // Week over week change
        HStack {
            Image(systemName: stats.week_over_week_change >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .foregroundColor(stats.week_over_week_change >= 0 ? .green : .red)
            Text(String(format: "%+.0f%% vs last week", stats.week_over_week_change))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(stats.week_over_week_change >= 0 ? .green : .red)
        }
        .padding(.top, 8)
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
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(savedWord.word)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                HStack {
                    if let nextReviewDate = savedWord.next_review_date {
                        Text("Next review \(formatDateOnly(nextReviewDate))")
                            .font(.caption)
                            .foregroundColor(isOverdue(nextReviewDate) ? .red : .secondary)
                    } else {
                        Text("No reviews yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(savedWord.review_count) review\(savedWord.review_count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
    
    private func formatDateOnly(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .none
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    private func isOverdue(_ dateString: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            return date < Date()
        }
        return false
    }
}

#Preview {
    SavedWordsView()
}
