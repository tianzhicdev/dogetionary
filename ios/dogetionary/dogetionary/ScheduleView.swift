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
    @State private var selectedDays = 7
    @State private var onlyNewWords = true  // Default to only showing days with new words
    @State private var hasLoadedInitially = false

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
                    VStack(spacing: 0) {
                        // Toggle control
                        Picker("View Mode", selection: $onlyNewWords) {
                            Text("Only New Words").tag(true)
                            Text("Full Schedule").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .padding()

                        ScheduleRangeListView(schedules: schedules)
                    }
                } else {
                    NoScheduleView(message: "No schedule available. Enable test preparation to create a schedule.")
                }
            }
            .navigationTitle("Study Schedule")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Days", selection: $selectedDays) {
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                        }
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
            .task(id: "\(selectedDays)-\(onlyNewWords)") {
                // Only load if not already loading and either first load or parameters changed
                guard !isLoading else { return }
                if !hasLoadedInitially || hasLoadedInitially {
                    await loadScheduleRangeAsync()
                    hasLoadedInitially = true
                }
            }
            .refreshable {
                await loadScheduleRangeAsync()
            }
        }
    }

    private func loadScheduleRangeAsync() async {
        // Prevent concurrent loads
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        await withCheckedContinuation { continuation in
            DictionaryService.shared.getScheduleRange(days: selectedDays, onlyNewWords: onlyNewWords) { result in
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

struct ScheduleRangeListView: View {
    let schedules: [DailyScheduleEntry]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(schedules, id: \.date) { entry in
                    DailyScheduleCard(entry: entry)
                }
            }
            .padding()
        }
    }
}

struct DailyScheduleCard: View {
    let entry: DailyScheduleEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with date and summary
            Button(action: {
                withAnimation {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatDate(entry.date))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        if let summary = entry.summary {
                            Text("\(summary.total_words) words total")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Summary badges
                    if let summary = entry.summary {
                        HStack(spacing: 8) {
                            if summary.total_new > 0 {
                                Badge(count: summary.total_new, color: .blue, icon: "plus.circle.fill")
                            }
                            if summary.total_test_practice > 0 {
                                Badge(count: summary.total_test_practice, color: .orange, icon: "target")
                            }
                            if summary.total_non_test_practice > 0 {
                                Badge(count: summary.total_non_test_practice, color: .green, icon: "repeat.circle.fill")
                            }
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded content showing actual words
            if isExpanded {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 16) {
                    // New Words
                    if !entry.new_words.isEmpty {
                        WordListSection(
                            title: "New Words",
                            icon: "plus.circle.fill",
                            color: .blue,
                            words: entry.new_words
                        )
                    }

                    // Test Practice Words
                    if !entry.test_practice_words.isEmpty {
                        PracticeWordListSection(
                            title: "Test Practice",
                            icon: "target",
                            color: .orange,
                            words: entry.test_practice_words
                        )
                    }

                    // Non-Test Practice Words
                    if !entry.non_test_practice_words.isEmpty {
                        PracticeWordListSection(
                            title: "Other Practice",
                            icon: "repeat.circle.fill",
                            color: .green,
                            words: entry.non_test_practice_words
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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

struct Badge: View {
    let count: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .cornerRadius(6)
    }
}

struct WordListSection: View {
    let title: String
    let icon: String
    let color: Color
    let words: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("(\(words.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(words, id: \.self) { word in
                    Text(word)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemBackground))
                        .cornerRadius(6)
                }
            }
        }
    }
}

struct PracticeWordListSection: View {
    let title: String
    let icon: String
    let color: Color
    let words: [SchedulePracticeWord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("(\(words.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(words) { word in
                    HStack(spacing: 4) {
                        Text(word.word)
                            .font(.caption)
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(Int(word.expected_retention * 100))%")
                            .font(.caption2)
                            .foregroundColor(retentionColor(word.expected_retention))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemBackground))
                    .cornerRadius(6)
                }
            }
        }
    }

    private func retentionColor(_ retention: Double) -> Color {
        if retention < 0.4 {
            return .red
        } else if retention < 0.6 {
            return .orange
        } else {
            return .green
        }
    }
}

// Flow layout for wrapping words
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                     y: bounds.minY + result.frames[index].minY),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

struct ScheduleContentView: View {
    let entry: DailyScheduleEntry

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Summary Card
                if let summary = entry.summary {
                    ScheduleSummaryCard(summary: summary, date: entry.date)
                        .padding(.horizontal)
                        .padding(.top)
                }

                // New Words Section
                if !entry.new_words.isEmpty {
                    ScheduleSection(
                        title: "New Words",
                        icon: "plus.circle.fill",
                        color: .blue,
                        count: entry.new_words.count
                    ) {
                        ForEach(entry.new_words, id: \.self) { word in
                            NewWordRow(word: word)
                        }
                    }
                    .padding(.horizontal)
                }

                // Test Practice Words Section
                if !entry.test_practice_words.isEmpty {
                    ScheduleSection(
                        title: "Test Practice",
                        icon: "target",
                        color: .orange,
                        count: entry.test_practice_words.count
                    ) {
                        ForEach(entry.test_practice_words) { practiceWord in
                            PracticeWordRow(word: practiceWord, isTestWord: true)
                        }
                    }
                    .padding(.horizontal)
                }

                // Non-Test Practice Words Section
                if !entry.non_test_practice_words.isEmpty {
                    ScheduleSection(
                        title: "Other Practice",
                        icon: "repeat.circle.fill",
                        color: .green,
                        count: entry.non_test_practice_words.count
                    ) {
                        ForEach(entry.non_test_practice_words) { practiceWord in
                            PracticeWordRow(word: practiceWord, isTestWord: false)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 40)
            }
        }
    }
}

struct ScheduleSummaryCard: View {
    let summary: ScheduleSummary
    let date: String

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Schedule")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(formatDate(date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundColor(.blue)
            }

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SummaryStatItem(
                    title: "New Words",
                    value: "\(summary.total_new)",
                    icon: "plus.circle.fill",
                    color: .blue
                )
                SummaryStatItem(
                    title: "Practice",
                    value: "\(summary.total_test_practice + summary.total_non_test_practice)",
                    icon: "repeat.circle.fill",
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .long
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct SummaryStatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct ScheduleSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let count: Int
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }

            VStack(spacing: 8) {
                content()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

struct NewWordRow: View {
    let word: String

    var body: some View {
        HStack {
            Text(word)
                .font(.body)
                .fontWeight(.medium)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct PracticeWordRow: View {
    let word: SchedulePracticeWord
    let isTestWord: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(word.word)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text(String(format: "%.0f%%", word.expected_retention * 100))
                        .font(.caption)
                }
                .foregroundColor(retentionColor(word.expected_retention))

                Text("•")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Review #\(word.review_number)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func retentionColor(_ retention: Double) -> Color {
        if retention < 0.4 {
            return .red
        } else if retention < 0.6 {
            return .orange
        } else {
            return .green
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
