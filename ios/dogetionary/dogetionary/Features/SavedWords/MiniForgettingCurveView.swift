//
//  MiniForgettingCurveView.swift
//  dogetionary
//
//  Created by Claude Code on 12/20/24.
//

import SwiftUI
import Charts

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

/// Mini sparkline-style forgetting curve for saved words list
struct MiniForgettingCurveView: View {
    let wordId: Int
    @State private var curveData: ForgettingCurveResponse?
    @State private var isLoading = false
    @State private var hasError = false

    var body: some View {
        Group {
            if isLoading {
                // Loading placeholder
                Rectangle()
                    .fill(AppTheme.panelFill.opacity(0.3))
                    .frame(width: 50, height: 18)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                    )
            } else if hasError || curveData == nil {
                // Error or no data placeholder
                Rectangle()
                    .fill(AppTheme.panelFill.opacity(0.2))
                    .frame(width: 50, height: 18)
                    .overlay(
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.smallTitleText.opacity(0.5))
                    )
            } else if let data = curveData {
                miniChart(data: data)
            }
        }
        .onAppear {
            loadCurveData()
        }
    }

    @ViewBuilder
    private func miniChart(data: ForgettingCurveResponse) -> some View {
        let points = prepareChartData(data: data)

        if points.isEmpty {
            // No reviews yet - show placeholder
            Rectangle()
                .fill(AppTheme.panelFill.opacity(0.2))
                .frame(width: 50, height: 18)
                .overlay(
                    Text("—")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.smallTitleText.opacity(0.5))
                )
        } else {
            Chart {
                // Historical forgetting curve (non-projection points only)
                ForEach(points.filter { !$0.isProjection && !$0.isReview }) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Retention", point.retention)
                    )
                    .foregroundStyle(AppTheme.bodyText)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

                // Projection curve (grey line)
                ForEach(points.filter { $0.isProjection }) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Retention", point.retention)
                    )
                    .foregroundStyle(AppTheme.selectableTint.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }

                // Review markers at 100% retention
                ForEach(points.filter { $0.isReview }) { point in
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Retention", 100.0)
                    )
                    .foregroundStyle(point.isCorrect ? AppTheme.successColor : AppTheme.errorColor)
                    .symbolSize(20)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...100)
            .frame(width: 50, height: 18)
        }
    }

    private func prepareChartData(data: ForgettingCurveResponse) -> [ChartDataPoint] {
        var points: [ChartDataPoint] = []

        print("🔍 MiniForgettingCurve: Processing word_id=\(data.word_id), word=\(data.word)")
        print("🔍 MiniForgettingCurve: forgetting_curve count=\(data.forgetting_curve.count)")
        print("🔍 MiniForgettingCurve: all_markers count=\(data.all_markers?.count ?? 0)")

        // Convert backend curve points to chart data (use same logic as ForgettingCurveView)
        for point in data.forgetting_curve {
            guard let pointDate = parseDateString(point.date) else {
                print("❌ MiniForgettingCurve: Failed to parse curve point date: \(point.date)")
                continue
            }

            print("🔍 MiniForgettingCurve: Curve point - date=\(point.date), is_projection=\(point.is_projection ?? false), retention=\(point.retention)")

            points.append(ChartDataPoint(
                date: pointDate,
                retention: point.retention,
                isProjection: point.is_projection ?? false,
                isReview: false,
                isCorrect: false
            ))
        }

        // Add review markers from all_markers (same as full curve view)
        if let allMarkers = data.all_markers {
            for marker in allMarkers where marker.type == "review" {
                guard let markerDate = parseDateString(marker.date) else {
                    print("❌ MiniForgettingCurve: Failed to parse marker date: \(marker.date)")
                    continue
                }

                points.append(ChartDataPoint(
                    date: markerDate,
                    retention: 100.0, // Reviews displayed at 100% retention
                    isProjection: false,
                    isReview: true,
                    isCorrect: marker.success ?? false
                ))
                print("✅ MiniForgettingCurve: Added review marker - date=\(marker.date), success=\(marker.success ?? false)")
            }
        }

        print("🔍 MiniForgettingCurve: Total points prepared: \(points.count)")
        return points.sorted { $0.date < $1.date }
    }

    private func loadCurveData() {
        isLoading = true
        hasError = false

        print("🔄 MiniForgettingCurve: Loading curve data for word_id=\(wordId)")

        DictionaryService.shared.getForgettingCurve(wordId: wordId) { result in
            DispatchQueue.main.async {
                isLoading = false

                switch result {
                case .success(let data):
                    print("✅ MiniForgettingCurve: Successfully loaded curve data for word=\(data.word)")
                    self.curveData = data
                case .failure(let error):
                    print("❌ MiniForgettingCurve: Failed to load curve data for word_id=\(self.wordId): \(error)")
                    self.hasError = true
                }
            }
        }
    }
}

// MARK: - Supporting Types

private struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let retention: Double
    let isProjection: Bool
    let isReview: Bool
    let isCorrect: Bool
}

// MARK: - Preview

#Preview("Mini Forgetting Curve") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack(spacing: 20) {
            Text("Mini Forgetting Curve Preview")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(AppTheme.bodyText)

            // Different states
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Loading:")
                        .foregroundColor(AppTheme.smallTitleText)
                    MiniForgettingCurveView(wordId: 1)
                        .onAppear {
                            // This will trigger loading state
                        }
                }

                HStack {
                    Text("With data:")
                        .foregroundColor(AppTheme.smallTitleText)
                    MiniForgettingCurveView(wordId: 237)
                }

                HStack {
                    Text("Scaled 2x:")
                        .foregroundColor(AppTheme.smallTitleText)
                    MiniForgettingCurveView(wordId: 237)
                        .scaleEffect(2.0)
                }
            }
            .padding()
            .background(AppTheme.panelFill)
            .cornerRadius(8)
        }
        .padding()
    }
}
