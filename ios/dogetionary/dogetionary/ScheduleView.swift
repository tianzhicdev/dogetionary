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
            Group {
                if isLoading {
                    ProgressView("Loading schedule...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !schedules.isEmpty {
                    SimpleScheduleListView(schedules: schedules)
                } else {
                    // Empty state
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        NoScheduleView(message: "No schedule available. Enable test preparation to create a schedule.")
                    }
                }
            }
            .navigationTitle("SuperMemo Schedule")
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

        // Load schedule range for 60 days, only days with tasks
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

struct SimpleScheduleListView: View {
    let schedules: [DailyScheduleEntry]

    // Filter out days with no tasks
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filteredSchedules, id: \.date) { entry in
                    SimpleDayRow(entry: entry)

                    if entry.date != filteredSchedules.last?.date {
                        Divider()
                            .padding(.leading, 8)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct SimpleDayRow: View {
    let entry: DailyScheduleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date header
            HStack {
                Text(formatDate(entry.date))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                // Count badge
                Text("\(totalWordCount) words")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }

            // Words grouped by type
            VStack(alignment: .leading, spacing: 6) {
                if let newWords = entry.new_words, !newWords.isEmpty {
                    WordGroup(label: "New", color: .red, words: newWords)
                }

                if let testPractice = entry.test_practice_words, !testPractice.isEmpty {
                    WordGroup(label: "Test", color: .green, words: testPractice.map { $0.word })
                }

                if let nonTestPractice = entry.non_test_practice_words, !nonTestPractice.isEmpty {
                    WordGroup(label: "Practice", color: .blue, words: nonTestPractice.map { $0.word })
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var totalWordCount: Int {
        let newCount = entry.new_words?.count ?? 0
        let testCount = entry.test_practice_words?.count ?? 0
        let nonTestCount = entry.non_test_practice_words?.count ?? 0
        return newCount + testCount + nonTestCount
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "EEEE, MMM d"
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct WordGroup: View {
    let label: String
    let color: Color
    let words: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Label with color indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .frame(width: 65, alignment: .leading)

            // Words
            Text(words.joined(separator: ", "))
                .font(.body)
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct NoScheduleView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Schedule")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ScheduleView()
}
