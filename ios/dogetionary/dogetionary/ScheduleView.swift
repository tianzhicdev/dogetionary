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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(schedules, id: \.date) { entry in
                    SimpleDayRow(entry: entry)
                }
            }
            .padding()
        }
    }
}

struct SimpleDayRow: View {
    let entry: DailyScheduleEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Date
            Text(formatDate(entry.date))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(width: 120, alignment: .leading)

            // Words in colored text
            Text(wordsString)
                .font(.body)
                .lineLimit(nil)
        }
        .padding(.vertical, 4)
    }

    private var wordsString: AttributedString {
        var result = AttributedString()

        // New words in red
        if let newWords = entry.new_words, !newWords.isEmpty {
            var newWordsText = AttributedString(newWords.joined(separator: ", "))
            newWordsText.foregroundColor = .red
            result.append(newWordsText)
        }

        // Test practice words in green
        if let testPractice = entry.test_practice_words, !testPractice.isEmpty {
            if !result.characters.isEmpty {
                result.append(AttributedString(", "))
            }
            let testWords = testPractice.map { $0.word }.joined(separator: ", ")
            var testWordsText = AttributedString(testWords)
            testWordsText.foregroundColor = .green
            result.append(testWordsText)
        }

        // Non-test practice words in blue
        if let nonTestPractice = entry.non_test_practice_words, !nonTestPractice.isEmpty {
            if !result.characters.isEmpty {
                result.append(AttributedString(", "))
            }
            let nonTestWords = nonTestPractice.map { $0.word }.joined(separator: ", ")
            var nonTestWordsText = AttributedString(nonTestWords)
            nonTestWordsText.foregroundColor = .blue
            result.append(nonTestWordsText)
        }

        return result
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "MMM d"
            return displayFormatter.string(from: date)
        }
        return dateString
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
