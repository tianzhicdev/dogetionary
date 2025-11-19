//
//  ScheduleView.swift
//  dogetionary
//
//  Created by Claude on schedule feature implementation
//

import SwiftUI

struct ScheduleView: View {
    @State private var schedules: [DailyScheduleEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasLoadedInitially = false
    @State private var userHasSchedule = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Simple gradient background
                LinearGradient(
                    colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Group {
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading schedule...")
                                .foregroundColor(.secondary)
                        }
                    } else if let error = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)
                            Text(error)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding()
                        }
                    } else if !schedules.isEmpty {
                        SimpleScheduleListView(schedules: schedules)
                    } else {
                        if userHasSchedule {
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.green)
                                Text("All caught up!")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text("No tasks scheduled for the next 60 days.")
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        } else {
                            NoScheduleView(message: "No schedule available. Enable test preparation to create a schedule.")
                        }
                    }
                }
            }
            .navigationTitle("Study Schedule")
            .navigationBarTitleDisplayMode(.large)
            .task {
                guard !isLoading && !hasLoadedInitially else { return }
                await loadScheduleRangeAsync()
                hasLoadedInitially = true
            }
            .refreshable {
                await loadScheduleRangeAsync()
            }
        }
    }

    private func loadScheduleRangeAsync() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        // Refresh schedule
        await withCheckedContinuation { continuation in
            DictionaryService.shared.refreshSchedule { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("✅ Schedule refreshed successfully")
                    case .failure(let error):
                        print("⚠️ Failed to refresh schedule: \(error.localizedDescription)")
                    }
                    continuation.resume()
                }
            }
        }

        // Check if user has any schedule
        await withCheckedContinuation { continuation in
            DictionaryService.shared.getTodaySchedule { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let entry):
                        self.userHasSchedule = entry.user_has_schedule ?? entry.has_schedule
                    case .failure:
                        self.userHasSchedule = false
                    }
                    continuation.resume()
                }
            }
        }

        // Load schedule range
        await withCheckedContinuation { continuation in
            DictionaryService.shared.getScheduleRange(days: 60, onlyNewWords: false) { result in
                DispatchQueue.main.async {
                    self.isLoading = false

                    switch result {
                    case .success(let response):
                        self.schedules = response.schedules
                    case .failure(let error):
                        self.errorMessage = error.localizedDescription
                    }

                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Schedule List

struct SimpleScheduleListView: View {
    let schedules: [DailyScheduleEntry]

    private var filteredSchedules: [DailyScheduleEntry] {
        schedules.filter { entry in
            let hasNewWords = (entry.new_words?.isEmpty == false)
            let hasTestPractice = (entry.test_practice_words?.isEmpty == false)
            let hasNonTestPractice = (entry.non_test_practice_words?.isEmpty == false)
            return hasNewWords || hasTestPractice || hasNonTestPractice
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(filteredSchedules, id: \.date) { entry in
                    DayCard(entry: entry)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Day Card

struct DayCard: View {
    let entry: DailyScheduleEntry

    private var isToday: Bool {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: entry.date) else { return false }
        return Calendar.current.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Date badge
                VStack(spacing: 2) {
                    Text(dayOfMonth)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isToday ? .white : Color(red: 0.3, green: 0.4, blue: 0.9))
                    Text(monthAbbreviation)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isToday ? .white.opacity(0.9) : Color(red: 0.3, green: 0.4, blue: 0.9).opacity(0.7))
                }
                .frame(width: 60, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isToday ?
                              LinearGradient(
                                colors: [Color(red: 0.4, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.4, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              ) :
                              LinearGradient(
                                colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color(red: 0.92, green: 0.95, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                        )
                )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(dayOfWeek)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.primary)

                        if isToday {
                            Text("TODAY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(red: 0.5, green: 0.45, blue: 1.0))
                                .cornerRadius(4)
                        }
                    }

                    HStack(spacing: 8) {
                        if let newCount = entry.new_words?.count, newCount > 0 {
                            TaskBadge(count: newCount, label: "New", color: Color(red: 1.0, green: 0.6, blue: 0.4))
                        }
                        if let testCount = entry.test_practice_words?.count, testCount > 0 {
                            TaskBadge(count: testCount, label: "Test", color: Color(red: 0.4, green: 0.8, blue: 0.6))
                        }
                        if let practiceCount = entry.non_test_practice_words?.count, practiceCount > 0 {
                            TaskBadge(count: practiceCount, label: "Practice", color: Color(red: 0.5, green: 0.7, blue: 1.0))
                        }
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(Color.white)

            Divider()

            // Word lists
            VStack(spacing: 12) {
                if let newWords = entry.new_words, !newWords.isEmpty {
                    WordSection(
                        label: "New Words",
                        words: newWords,
                        backgroundColor: Color(red: 1.0, green: 0.95, blue: 0.9),
                        textColor: Color(red: 0.8, green: 0.4, blue: 0.2)
                    )
                }

                if let testWords = entry.test_practice_words, !testWords.isEmpty {
                    WordSection(
                        label: "Test Practice",
                        words: testWords.map { $0.word },
                        backgroundColor: Color(red: 0.9, green: 0.98, blue: 0.95),
                        textColor: Color(red: 0.2, green: 0.6, blue: 0.4)
                    )
                }

                if let practiceWords = entry.non_test_practice_words, !practiceWords.isEmpty {
                    WordSection(
                        label: "Review Practice",
                        words: practiceWords.map { $0.word },
                        backgroundColor: Color(red: 0.95, green: 0.97, blue: 1.0),
                        textColor: Color(red: 0.3, green: 0.5, blue: 0.9)
                    )
                }
            }
            .padding(16)
            .background(Color(red: 0.98, green: 0.99, blue: 1.0))
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private var dayOfWeek: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: entry.date) else { return "" }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        return dayFormatter.string(from: date)
    }

    private var dayOfMonth: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: entry.date) else { return "" }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d"
        return dayFormatter.string(from: date)
    }

    private var monthAbbreviation: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: entry.date) else { return "" }
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        return monthFormatter.string(from: date).uppercased()
    }
}

// MARK: - Task Badge

struct TaskBadge: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(6)
    }
}

// MARK: - Word Section

struct WordSection: View {
    let label: String
    let words: [String]
    let backgroundColor: Color
    let textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("(\(words.count))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Text(words.joined(separator: ", "))
                .font(.system(size: 15))
                .foregroundColor(textColor)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(backgroundColor)
        .cornerRadius(10)
    }
}

// MARK: - Empty State

struct NoScheduleView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.95, green: 0.97, blue: 1.0))
                    .frame(width: 100, height: 100)

                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 50))
                    .foregroundColor(Color(red: 0.4, green: 0.5, blue: 1.0))
            }

            Text("No Schedule Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ScheduleView()
}
