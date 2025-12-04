//
//  ForgettingCurveView.swift
//  dogetionary
//
//  Created for displaying spaced repetition forgetting curve
//

import SwiftUI
import Charts
import os.log

private let logger = Logger(subsystem: "com.dogetionary.app", category: "ForgettingCurve")

// Helper function for parsing dates consistently
private func parseDateString(_ dateString: String) -> Date? {
    // Primary format used by the backend
    let backendFormatter = DateFormatter()
    backendFormatter.dateFormat = "yyyy-MM-dd"
    
    // Fallback formats
    let iso8601Formatter = ISO8601DateFormatter()
    let altFormatter = DateFormatter()
    altFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    let microsecondFormatter = DateFormatter()
    microsecondFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
    
    return backendFormatter.date(from: dateString) ??
           iso8601Formatter.date(from: dateString) ??
           altFormatter.date(from: dateString) ??
           microsecondFormatter.date(from: dateString)
}

private func formatShortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "M/d"
    return formatter.string(from: date)
}

struct ForgettingCurveView: View {
    let reviewHistory: [ReviewHistoryEntry]
    let nextReviewDate: String?
    let createdAt: String
    let wordId: Int
    
    @State private var selectedPoint: CurveDataPoint?
    @State private var curveData: [CurveDataPoint] = []
    @State private var reviewMarkers: [ReviewMarker] = []
    @State private var allMarkers: [AllMarker] = []
    @State private var backendNextReviewDate: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Get min and max dates for chart bounds
    private var dateRange: (min: Date, max: Date) {
        // Start from word creation date
        guard let creationDate = parseDateString(createdAt) else {
            let now = Date()
            return (now, now.addingTimeInterval(86400))
        }
        
        // End at last review date, or 30 days from creation if no reviews
        let endDate: Date
        if !reviewHistory.isEmpty {
            let reviewDates = reviewHistory.compactMap { parseDateString($0.reviewed_at) }
            endDate = reviewDates.max() ?? creationDate.addingTimeInterval(30 * 86400)
        } else {
            endDate = creationDate.addingTimeInterval(30 * 86400)
        }
        
        return (creationDate, endDate)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title with debug info
            VStack(alignment: .leading, spacing: 4) {
                Text("Memory Retention Curve")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if isLoading {
                    Text("Loading curve data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let error = errorMessage {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(AppTheme.errorColor)
                }
            }
            
            // Chart
            if #available(iOS 16.0, *) {
                Chart {
                    // Historical forgetting curve (solid line)
                    ForEach(curveData.filter { !$0.isProjection }) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Retention", point.retention)
                        )
//                        .foregroundStyle(Color.blue.gradient)
//                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    
                    // Projection curve (grey dotted line to next review)
                    ForEach(curveData.filter { $0.isProjection }) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Retention", point.retention)
                        )
//                        .foregroundStyle(Color.gray)
//                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    }
                    
                    // Creation markers
                    ForEach(allMarkers.filter { $0.type == "creation" }, id: \.date) { marker in
                        if let date = parseDateString(marker.date) {
                            PointMark(
                                x: .value("Date", date),
                                y: .value("Retention", 100.0)
                            )
                            .foregroundStyle(AppTheme.infoColor)
                            .symbol(.diamond)
                            .symbolSize(120)
                        }
                    }
                    
                    // Review markers
                    ForEach(allMarkers.filter { $0.type == "review" }, id: \.date) { marker in
                        if let date = parseDateString(marker.date) {
                            PointMark(
                                x: .value("Date", date),
                                y: .value("Retention", 100.0)
                            )
                            .foregroundStyle(marker.success == true ? AppTheme.successColor : AppTheme.errorColor)
                            .symbolSize(100)
                            
                            RuleMark(x: .value("Date", date))
                                .foregroundStyle(Color.gray.opacity(AppTheme.strongOpacity))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                        }
                    }
                    
                    // Next review markers - always at 25% retention
                    ForEach(allMarkers.filter { $0.type == "next_review" }, id: \.date) { marker in
                        if let date = parseDateString(marker.date) {
                            PointMark(
                                x: .value("Date", date),
                                y: .value("Retention", 100.0)  // Always at 25% as requested
                            )
                            .foregroundStyle(AppTheme.warningColor)
                            .symbol(.diamond)
                            .symbolSize(150)

                            RuleMark(x: .value("Date", date))
                                .foregroundStyle(AppTheme.warningColor.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        }
                    }
                    
                    // Remove next review from main chart - will show as separate bar below
                    
                    // Retention threshold lines
                    RuleMark(y: .value("Good", 80))
                        .foregroundStyle(AppTheme.successColor.opacity(AppTheme.mediumHighOpacity))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    RuleMark(y: .value("Warning", 60))
                        .foregroundStyle(AppTheme.warningColor.opacity(AppTheme.mediumHighOpacity))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .frame(height: 200)
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(formatAxisDate(date))
                                    .font(.caption2)
                            }
                            AxisGridLine()
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        if let retention = value.as(Double.self) {
                            AxisValueLabel {
                                Text("\(Int(retention))%")
                                    .font(.caption2)
                            }
                            AxisGridLine()
                        }
                    }
                }
            } else {
                // Fallback for iOS 15 and below - simple text representation
                FallbackCurveView(reviewHistory: reviewHistory, nextReviewDate: nextReviewDate)
            }
            
            // Legend
            HStack(spacing: 12) {
                ForgettingCurveLegendItem(color: AppTheme.infoColor, shape: .diamond, text: "Created")
                ForgettingCurveLegendItem(color: AppTheme.successColor, text: "Correct")
                ForgettingCurveLegendItem(color: AppTheme.errorColor, text: "Incorrect")
                ForgettingCurveLegendItem(color: AppTheme.warningColor, shape: .diamond, text: "Next Review")
            }
            .font(.caption)
            
            // Next review indicator (use backend data if available)
            if let backendNextReview = backendNextReviewDate,
               let nextDate = parseDateString(backendNextReview) {
                NextReviewBarView(nextReviewDate: nextDate)
            } else if let nextReview = nextReviewDate,
               let nextDate = parseDateString(nextReview) {
                NextReviewBarView(nextReviewDate: nextDate)
            }
            
            // Review timeline (simplified)
//            ReviewTimelineView(reviewHistory: reviewHistory, createdAt: createdAt)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .onAppear {
            loadForgettingCurve()
        }
    }
    
    private func loadForgettingCurve() {
        isLoading = true
        errorMessage = nil
        
        // Use DictionaryService to call the new forgetting curve API
        DictionaryService.shared.getForgettingCurve(wordId: wordId) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let response):
                    // Convert backend response to CurveDataPoint array
                    curveData = response.forgetting_curve.map { point in
                        CurveDataPoint(
                            date: parseDateString(point.date) ?? Date(),
                            retention: point.retention, // Backend already returns percentage (0-100)
                            isProjection: point.is_projection ?? false
                        )
                    }
                    // Store review markers, all markers, and next review date from backend
                    reviewMarkers = response.review_markers ?? []
                    allMarkers = response.all_markers ?? []
                    backendNextReviewDate = response.next_review_date
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    curveData = [] // Fallback to empty curve
                }
            }
        }
    }
    
    private func calculateRetention(at targetDate: Date) -> Double {
        // Debug: Print review dates
        let reviewDates = reviewHistory.compactMap { parseDateString($0.reviewed_at) }
        if reviewDates.isEmpty {
            logger.debug("No valid review dates found!")
            for review in reviewHistory {
                logger.debug("Raw review date string: '\(review.reviewed_at, privacy: .public)'")
                logger.debug("Attempted parse result: \(String(describing: parseDateString(review.reviewed_at)), privacy: .private)")
            }
            return 0.0
        }

        // Get the first review date to handle pre-learning period
        guard let firstReviewDate = reviewDates.min() else {
            logger.debug("Could not find minimum date")
            return 0.0
        }
        
        // If asking for retention before first review, assume perfect initial memory
        if targetDate < firstReviewDate {
            return 1.0 // 100% retention when word was just learned
        }
        
        // Find all reviews before or at targetDate
        var relevantReviews: [(Date, Bool, Int)] = []
        
        for (index, review) in reviewHistory.enumerated() {
            if let reviewDate = parseDateString(review.reviewed_at) {
                if reviewDate <= targetDate {
                    relevantReviews.append((reviewDate, review.response, index))
                }
            }
        }
        
        // If no reviews before this date (shouldn't happen now), start at 100%
        guard !relevantReviews.isEmpty else {
            return 1.0
        }
        
        // Sort by date and get the most recent review
        relevantReviews.sort { $0.0 < $1.0 }
        guard let lastReview = relevantReviews.last else {
            return 1.0  // Defensive fallback, though guard above should prevent this
        }
        let (lastReviewDate, wasCorrect, _) = lastReview
        
        // Calculate days since last review
        let daysSinceReview = max(0, targetDate.timeIntervalSince(lastReviewDate) / 86400)
        
        // Base retention immediately after review
        let baseRetention: Double = wasCorrect ? 0.95 : 0.70
        
        // Decay rate based on total number of reviews (more reviews = slower forgetting)
        let totalReviews = relevantReviews.count
        let decayRate: Double
        switch totalReviews {
        case 1: decayRate = 0.15     // Fast decay for first review
        case 2: decayRate = 0.10     // Slower decay
        case 3...4: decayRate = 0.07 // Even slower
        default: decayRate = 0.04    // Very slow for well-learned words
        }
        
        // Apply exponential decay: retention = base * e^(-rate * days)
        let retention = baseRetention * exp(-decayRate * daysSinceReview)
        
        // Ensure retention is between 0 and 1
        return max(0.1, min(1.0, retention)) // Minimum 10% to keep curve visible
    }
    
    private func getRetentionAtReview(index: Int) -> Double {
        // Get retention just before the review
        guard index < reviewHistory.count else { return 0 }
        
        if index == 0 {
            return 100 // First review starts at 100%
        }
        
        guard let reviewDate = parseDateString(reviewHistory[index].reviewed_at) else {
            return 50 // Fallback value
        }
        
        // Calculate retention just before this review (1 second before to avoid same timestamp)
        let retentionFraction = calculateRetention(at: reviewDate.addingTimeInterval(-1))
        return retentionFraction * 100
    }
    
    private func getProjectedRetention(at date: Date) -> Double {
        return calculateRetention(at: date) * 100
    }
    
    private func formatAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if date > now {
            let days = calendar.dateComponents([.day], from: now, to: date).day ?? 0
            if days <= 7 {
                return "+\(days)d"
            } else {
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
        } else {
            let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            if days <= 7 {
                return "-\(days)d"
            } else {
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
        }
    }
    
}

struct CurveDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let retention: Double
    let isProjection: Bool
}

struct ForgettingCurveLegendItem: View {
    let color: Color
    var shape: SymbolShape = .circle
    let text: String

    enum SymbolShape {
        case circle
        case diamond
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if shape == .diamond {
                Image(systemName: "diamond.fill")
                    .foregroundColor(color)
                    .font(.caption)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(text)
                .foregroundColor(.secondary)
        }
    }
}

struct NextReviewBarView: View {
    let nextReviewDate: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next Review")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack {
                Rectangle()
                    .fill(AppTheme.warningColor)
                    .frame(width: 60, height: 8)
                    .cornerRadius(4)

                Text(formatDate(nextReviewDate))
                    .font(.caption)
                    .foregroundColor(AppTheme.warningColor)
                
                Spacer()
                
                let daysFromNow = Calendar.current.dateComponents([.day], from: Date(), to: nextReviewDate).day ?? 0
                Text(daysFromNow == 0 ? "Today" : 
                     daysFromNow == 1 ? "Tomorrow" : 
                     daysFromNow > 0 ? "in \(daysFromNow) days" : "\(-daysFromNow) days overdue")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
//
//struct ReviewTimelineView: View {
//    let reviewHistory: [ReviewHistoryEntry]
//    let createdAt: String
//    
//    var body: some View {
//        VStack(alignment: .leading, spacing: 8) {
//Text("Review History")
//                .font(.caption)
//                .fontWeight(.medium)
//                .foregroundColor(.secondary)
//            
//            HStack(spacing: 4) {
//                // Start marker (word creation with date)
//                VStack(spacing: 2) {
//                    Image(systemName: "plus.circle.fill")
//                        .font(.caption2)
//                        .foregroundColor(.blue)
//                    if let creationDate = parseDateString(createdAt) {
//                        Text(formatShortDate(creationDate))
//                            .font(.system(size: 8))
//                            .foregroundColor(.secondary)
//                    } else {
//                        Text("Created")
//                            .font(.system(size: 8))
//                            .foregroundColor(.secondary)
//                    }
//                }
//                
//                // Review markers
//                ForEach(Array(reviewHistory.prefix(10).enumerated()), id: \.offset) { index, review in
//                    VStack(spacing: 2) {
//                        Text("|")
//                            .font(.caption)
//                            .fontWeight(.bold)
//                            .foregroundColor(review.response ? .green : .red)
//                        Text("\(index + 1)")
//                            .font(.system(size: 8))
//                            .foregroundColor(.secondary)
//                    }
//                }
//                
//                if reviewHistory.count > 10 {
//                    Text("...")
//                        .font(.caption)
//                        .foregroundColor(.secondary)
//                }
//                
//                Spacer()
//            }
//        }
//    }
//}

// Fallback view for iOS 15 and below
struct FallbackCurveView: View {
    let reviewHistory: [ReviewHistoryEntry]
    let nextReviewDate: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Performance")
                .font(.subheadline)
                .fontWeight(.medium)
            
            // Simple bar representation of reviews
            HStack(spacing: 4) {
                ForEach(Array(reviewHistory.enumerated()), id: \.0) { index, review in
                    VStack {
                        Rectangle()
                            .fill(review.response ? AppTheme.successColor : AppTheme.errorColor)
                            .frame(width: 20, height: review.response ? 40 : 20)
                        Text("\(index + 1)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let nextDate = nextReviewDate {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.orange)
                    Text("Next: \(formatDate(nextDate, style: .relative))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(height: 200)
        .background(Color(UIColor.systemGray5))
        .cornerRadius(8)
    }
    
    private func formatDate(_ dateString: String, style: DateStyle) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        return displayFormatter.string(from: date)
    }
    
    private enum DateStyle {
        case relative
    }
}

#Preview {
    ForgettingCurveView(
        reviewHistory: [
            ReviewHistoryEntry(
                response: true,
                response_time_ms: 2000,
                reviewed_at: "2025-01-05 14:30:00"
            ),
            ReviewHistoryEntry(
                response: true,
                response_time_ms: 1500,
                reviewed_at: "2025-01-08 10:15:00"
            ),
            ReviewHistoryEntry(
                response: false,
                response_time_ms: 3000,
                reviewed_at: "2025-01-12 16:45:00"
            ),
            ReviewHistoryEntry(
                response: true,
                response_time_ms: 1000,
                reviewed_at: "2025-01-14 09:20:00"
            )
        ],
        nextReviewDate: "2025-01-18 10:00:00",
        createdAt: "2025-01-01 12:00:00",
        wordId: 1
    )
    .padding()
}
