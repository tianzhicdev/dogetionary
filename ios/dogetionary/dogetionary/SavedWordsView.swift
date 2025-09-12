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
                
                // Stats Tab
                StatsView()
                    .tabItem {
                        Image(systemName: "chart.bar.fill")
                        Text("Stats")
                    }
            }
            .navigationTitle("Saved Words")
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
    @State private var isLoading = false
    @State private var currentDate = Date()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Review Activity Section
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Review Activity")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Green dates show days with reviews")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)
                    
                    // Monthly Calendar
                    MonthlyCalendarView(
                        currentDate: $currentDate,
                        reviewDates: reviewDates
                    )
                    
                    // Month Navigation
                    HStack {
                        Button(action: {
                            currentDate = Calendar.current.date(byAdding: .month, value: -1, to: currentDate) ?? currentDate
                            loadReviewDates()
                        }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Previous")
                            }
                        }
                        
                        Spacer()
                        
                        Text(monthYearString(from: currentDate))
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Button(action: {
                            currentDate = Calendar.current.date(byAdding: .month, value: 1, to: currentDate) ?? currentDate
                            loadReviewDates()
                        }) {
                            HStack {
                                Text("Next")
                                Image(systemName: "chevron.right")
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                    .padding(.horizontal)
                
                // Progress Funnel Section
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Memorization Progress")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Words progressing through learning stages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let progressData = progressData {
                        ProgressFunnelView(data: progressData)
                    } else if isLoading {
                        ProgressView("Loading progress data...")
                            .padding()
                    } else {
                        Text("No progress data available")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                
                Spacer(minLength: 40)
            }
        }
        .onAppear {
            loadReviewDates()
            loadProgressData()
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
        isLoading = true
        
        DictionaryService.shared.getProgressFunnelData { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
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
}

struct ProgressFunnelData: Codable {
    let stage1_count: Int  // Any successful review
    let stage2_count: Int  // 2+ continuous successes in past 7 days
    let stage3_count: Int  // 3+ successes in past 14 days
    let stage4_count: Int  // 4+ successes in past 28 days
    let total_words: Int
}

struct ProgressFunnelView: View {
    let data: ProgressFunnelData
    
    private let stages = [
        ("Started Learning", "Any successful review", Color.blue.opacity(0.6)),
        ("Building Memory", "2+ successes in 7 days", Color.green.opacity(0.6)),
        ("Strengthening", "3+ successes in 14 days", Color.orange.opacity(0.6)),
        ("Mastered", "4+ successes in 28 days", Color.purple.opacity(0.6))
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Funnel visualization
            GeometryReader { geometry in
                ZStack {
                    // Background funnel shape
                    FunnelShape()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    
                    // Funnel stages
                    VStack(spacing: 0) {
                        FunnelStageView(
                            label: stages[0].0,
                            count: data.stage1_count,
                            description: stages[0].1,
                            color: stages[0].2,
                            width: geometry.size.width,
                            isTop: true
                        )
                        
                        FunnelStageView(
                            label: stages[1].0,
                            count: data.stage2_count,
                            description: stages[1].1,
                            color: stages[1].2,
                            width: geometry.size.width * 0.75,
                            isTop: false
                        )
                        
                        FunnelStageView(
                            label: stages[2].0,
                            count: data.stage3_count,
                            description: stages[2].1,
                            color: stages[2].2,
                            width: geometry.size.width * 0.5,
                            isTop: false
                        )
                        
                        FunnelStageView(
                            label: stages[3].0,
                            count: data.stage4_count,
                            description: stages[3].1,
                            color: stages[3].2,
                            width: geometry.size.width * 0.25,
                            isTop: false
                        )
                    }
                }
            }
            .frame(height: 320)
            .padding(.horizontal)
            
            // Legend
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<4) { index in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(stages[index].2)
                            .frame(width: 12, height: 12)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stages[index].0)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(stages[index].1)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text("\(getCountForStage(index)) words")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(stages[index].2)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
    
    private func getCountForStage(_ index: Int) -> Int {
        switch index {
        case 0: return data.stage1_count
        case 1: return data.stage2_count
        case 2: return data.stage3_count
        case 3: return data.stage4_count
        default: return 0
        }
    }
}

struct FunnelStageView: View {
    let label: String
    let count: Int
    let description: String
    let color: Color
    let width: CGFloat
    let isTop: Bool
    
    var body: some View {
        ZStack {
            // Stage background
            Rectangle()
                .fill(color)
                .frame(width: width, height: 70)
                .cornerRadius(isTop ? 12 : 0, corners: isTop ? [.topLeft, .topRight] : [])
            
            // Stage content
            VStack(spacing: 4) {
                Text("\(count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
}

struct FunnelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Define funnel trapezoid
        let topWidth = rect.width
        let bottomWidth = rect.width * 0.25
        let topY = rect.minY
        let bottomY = rect.maxY
        
        path.move(to: CGPoint(x: rect.midX - topWidth/2, y: topY))
        path.addLine(to: CGPoint(x: rect.midX + topWidth/2, y: topY))
        path.addLine(to: CGPoint(x: rect.midX + bottomWidth/2, y: bottomY))
        path.addLine(to: CGPoint(x: rect.midX - bottomWidth/2, y: bottomY))
        path.closeSubpath()
        
        return path
    }
}

// Helper extension for corner radius on specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

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
