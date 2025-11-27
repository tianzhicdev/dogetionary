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
    @State private var userHasSchedule = false
    @State private var testType: String?
    @State private var userName: String?
    @State private var isCreatingSchedule = false
    @ObservedObject private var userManager = UserManager.shared

    /// When true, shows without NavigationStack wrapper (for embedding in onboarding)
    var embedded: Bool = false

    var body: some View {
        if embedded {
            scheduleContent
        } else {
            NavigationStack {
                scheduleContent
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var scheduleContent: some View {
        ZStack {
            // Simple gradient background
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                            Text("Loading schedule...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxHeight: .infinity)
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
                        .frame(maxHeight: .infinity)
                    } else if !schedules.isEmpty || userManager.learningLanguage == "en" {
                        SimpleScheduleListView(
                            schedules: schedules,
                            showConfigHeader: userManager.learningLanguage == "en",
                            activeTestType: $userManager.activeTestType,
                            targetDays: $userManager.targetDays,
                            isCreatingSchedule: isCreatingSchedule,
                            userHasSchedule: userHasSchedule,
                            onTestTypeChange: { old, new in
                                Task {
                                    await handleTestTypeChange(from: old, to: new)
                                }
                            },
                            onTargetDaysChange: {
                                Task {
                                    await handleTargetDaysChange()
                                }
                            }
                        )
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
                            .frame(maxHeight: .infinity)
                        } else {
                            NoScheduleView(message: "No schedule available.")
                        }
                    }
                }
            }
        }
        .task {
            // Always refresh when view appears (navigating to Schedule tab)
            await loadScheduleRangeAsync()
        }
        .refreshable {
            await loadScheduleRangeAsync()
        }
    }

    private func handleTestTypeChange(from oldValue: TestType?, to newValue: TestType?) async {
        guard !isCreatingSchedule else { return }

        // If changed to None or from one test to another, update backend and recreate schedule
        isCreatingSchedule = true

        // Step 1: Update test settings in backend (this ensures only one test is enabled)
        await updateTestSettingsInBackend(testType: newValue, targetDays: userManager.targetDays)

        // Step 2: Create new schedule if test type is selected
        if let testType = newValue {
            // Create schedule with selected test type
            await createSchedule(testType: testType.rawValue, targetDays: userManager.targetDays)
        }
        // Note: If newValue is nil, updateTestSettings already deleted the schedule in backend

        // Step 3: Reload schedule to reflect changes
        await loadScheduleRangeAsync()
        isCreatingSchedule = false

        // Step 4: Notify other views that test settings changed
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .testSettingsChanged, object: nil)
        }
    }

    private func handleTargetDaysChange() async {
        guard !isCreatingSchedule, let testType = userManager.activeTestType else { return }

        isCreatingSchedule = true

        // Step 1: Update test settings in backend
        await updateTestSettingsInBackend(testType: testType, targetDays: userManager.targetDays)

        // Step 2: Recreate schedule with new target days
        await createSchedule(testType: testType.rawValue, targetDays: userManager.targetDays)

        // Step 3: Reload schedule
        await loadScheduleRangeAsync()
        isCreatingSchedule = false

        // Step 4: Notify other views that test settings changed
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .testSettingsChanged, object: nil)
        }
    }

    private func createSchedule(testType: String, targetDays: Int) async {
        await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            guard let targetDate = calendar.date(byAdding: .day, value: targetDays, to: Date()) else {
                print("❌ Failed to calculate target end date")
                continuation.resume()
                return
            }

            // Format as YYYY-MM-DD string (backend expects this format)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let targetEndDateString = formatter.string(from: targetDate)

            DictionaryService.shared.createSchedule(testType: testType, targetEndDate: targetEndDateString) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("✅ Schedule created successfully")
                    case .failure(let error):
                        print("⚠️ Failed to create schedule: \(error.localizedDescription)")
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func updateTestSettingsInBackend(testType: TestType?, targetDays: Int) async {
        await withCheckedContinuation { continuation in
            let userID = UserManager.shared.getUserID()

            print("📝 Updating test settings - testType: \(testType?.rawValue ?? "nil"), targetDays: \(targetDays)")

            DictionaryService.shared.updateTestSettings(
                userID: userID,
                testType: testType,
                targetDays: targetDays
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("✅ Test settings updated successfully")
                    case .failure(let error):
                        print("⚠️ Failed to update test settings: \(error.localizedDescription)")
                    }
                    continuation.resume()
                }
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
                        self.testType = response.test_type
                        self.userName = response.user_name
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
    let showConfigHeader: Bool
    @Binding var activeTestType: TestType?
    @Binding var targetDays: Int
    let isCreatingSchedule: Bool
    let userHasSchedule: Bool
    let onTestTypeChange: (TestType?, TestType?) -> Void
    let onTargetDaysChange: () -> Void

    private var filteredSchedules: [DailyScheduleEntry] {
        schedules.filter { entry in
            let hasNewWords = (entry.new_words?.isEmpty == false) || (entry.new_words_completed?.isEmpty == false)
            let hasTestPractice = (entry.test_practice_words?.isEmpty == false) || (entry.test_practice_words_completed?.isEmpty == false)
            let hasNonTestPractice = (entry.non_test_practice_words?.isEmpty == false) || (entry.non_test_practice_words_completed?.isEmpty == false)
            return hasNewWords || hasTestPractice || hasNonTestPractice
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Test prep configuration header (scrolls with content)
                if showConfigHeader {
                    VStack(spacing: 12) {
                        // Test type picker
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "graduationcap.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("Test Level")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }

                            Menu {
                                Button(action: { activeTestType = nil }) {
                                    HStack {
                                        Text("None")
                                        if activeTestType == nil {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Divider()
                                Button(action: { activeTestType = .toeflBeginner }) {
                                    HStack {
                                        Text("TOEFL Beginner")
                                        if activeTestType == .toeflBeginner {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Button(action: { activeTestType = .toeflIntermediate }) {
                                    HStack {
                                        Text("TOEFL Intermediate")
                                        if activeTestType == .toeflIntermediate {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Button(action: { activeTestType = .toeflAdvanced }) {
                                    HStack {
                                        Text("TOEFL Advanced")
                                        if activeTestType == .toeflAdvanced {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Divider()
                                Button(action: { activeTestType = .ieltsBeginner }) {
                                    HStack {
                                        Text("IELTS Beginner")
                                        if activeTestType == .ieltsBeginner {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Button(action: { activeTestType = .ieltsIntermediate }) {
                                    HStack {
                                        Text("IELTS Intermediate")
                                        if activeTestType == .ieltsIntermediate {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Button(action: { activeTestType = .ieltsAdvanced }) {
                                    HStack {
                                        Text("IELTS Advanced")
                                        if activeTestType == .ieltsAdvanced {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                if DebugConfig.showTianzTest {
                                    Divider()
                                    Button(action: { activeTestType = .tianz }) {
                                        HStack {
                                            Text("Tianz Test")
                                            if activeTestType == .tianz {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(testTypeLabel)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .onChange(of: activeTestType) { oldValue, newValue in
                                onTestTypeChange(oldValue, newValue)
                            }
                        }

                        // Target days picker (only show if test selected)
                        if activeTestType != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    Text("Study Duration")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                }

                                Menu {
                                    ForEach(1...200, id: \.self) { days in
                                        Button(action: { targetDays = days }) {
                                            HStack {
                                                Text("\(days) days → \(formattedEndDate(days: days))")
                                                if targetDays == days {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text("\(targetDays) days → \(formattedEndDate(days: targetDays))")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .onChange(of: targetDays) { _, _ in
                                    onTargetDaysChange()
                                }
                            }
                        }

                        if isCreatingSchedule {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Updating schedule...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // Show empty state message when no schedules but config header is visible
                if filteredSchedules.isEmpty && showConfigHeader {
                    VStack(spacing: 16) {
                        if activeTestType == nil {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No test selected")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Select a test level above to create your study schedule")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else if !userHasSchedule {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)
                            Text("No schedule created")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("Please wait while we create your study schedule")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("All caught up!")
                                .font(.title3)
                                .fontWeight(.semibold)
                            Text("No tasks scheduled for the next 60 days")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }

                ForEach(filteredSchedules, id: \.date) { entry in
                    DayCard(entry: entry)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical, showConfigHeader ? 0 : 16)
        }
    }

    private func formattedEndDate(days: Int) -> String {
        let calendar = Calendar.current
        guard let endDate = calendar.date(byAdding: .day, value: days, to: Date()) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: endDate)
    }

    private var testTypeLabel: String {
        guard let type = activeTestType else { return "None" }
        switch type {
        case .toeflBeginner: return "TOEFL Beginner"
        case .toeflIntermediate: return "TOEFL Intermediate"
        case .toeflAdvanced: return "TOEFL Advanced"
        case .ieltsBeginner: return "IELTS Beginner"
        case .ieltsIntermediate: return "IELTS Intermediate"
        case .ieltsAdvanced: return "IELTS Advanced"
        case .tianz: return "Tianz Test"
        }
    }
}

// MARK: - Day Card

struct DayCard: View {
    let entry: DailyScheduleEntry

    private var isToday: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: entry.date) else { return false }
        return Calendar.current.isDateInToday(date)
    }

    private var testLabel: String {
        guard let testType = entry.test_type else { return "Test" }
        if testType == "BOTH" {
            return "Test"
        }
        return testType
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
                        let newTotal = (entry.new_words?.count ?? 0) + (entry.new_words_completed?.count ?? 0)
                        let newCompleted = entry.new_words_completed?.count ?? 0
                        if newTotal > 0 {
                            TaskBadge(count: newTotal, completed: newCompleted, label: "New", color: Color(red: 1.0, green: 0.6, blue: 0.4))
                        }

                        let testTotal = (entry.test_practice_words?.count ?? 0) + (entry.test_practice_words_completed?.count ?? 0)
                        let testCompleted = entry.test_practice_words_completed?.count ?? 0
                        if testTotal > 0 {
                            TaskBadge(count: testTotal, completed: testCompleted, label: testLabel, color: Color(red: 0.4, green: 0.8, blue: 0.6))
                        }

                        let practiceTotal = (entry.non_test_practice_words?.count ?? 0) + (entry.non_test_practice_words_completed?.count ?? 0)
                        let practiceCompleted = entry.non_test_practice_words_completed?.count ?? 0
                        if practiceTotal > 0 {
                            TaskBadge(count: practiceTotal, completed: practiceCompleted, label: "Custom", color: Color(red: 0.5, green: 0.7, blue: 1.0))
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
                // New words section (show if there are remaining OR completed words)
                let newWords = entry.new_words ?? []
                let newWordsCompleted = entry.new_words_completed ?? []
                if !newWords.isEmpty || !newWordsCompleted.isEmpty {
                    WordSection(
                        label: "New Words",
                        words: newWords,
                        completedWords: newWordsCompleted,
                        backgroundColor: Color(red: 1.0, green: 0.95, blue: 0.9),
                        textColor: Color(red: 0.8, green: 0.4, blue: 0.2)
                    )
                }

                // Test practice section
                let testWords = entry.test_practice_words ?? []
                let testWordsCompleted = entry.test_practice_words_completed ?? []
                if !testWords.isEmpty || !testWordsCompleted.isEmpty {
                    WordSection(
                        label: "\(testLabel) Practice",
                        words: testWords.map { $0.word },
                        completedWords: testWordsCompleted.map { $0.word },
                        backgroundColor: Color(red: 0.9, green: 0.98, blue: 0.95),
                        textColor: Color(red: 0.2, green: 0.6, blue: 0.4)
                    )
                }

                // Non-test practice section
                let practiceWords = entry.non_test_practice_words ?? []
                let practiceWordsCompleted = entry.non_test_practice_words_completed ?? []
                if !practiceWords.isEmpty || !practiceWordsCompleted.isEmpty {
                    WordSection(
                        label: "Custom Practice",
                        words: practiceWords.map { $0.word },
                        completedWords: practiceWordsCompleted.map { $0.word },
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: entry.date) else { return "" }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        return dayFormatter.string(from: date)
    }

    private var dayOfMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: entry.date) else { return "" }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d"
        return dayFormatter.string(from: date)
    }

    private var monthAbbreviation: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: entry.date) else { return "" }
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        return monthFormatter.string(from: date).uppercased()
    }
}

// MARK: - Task Badge

struct TaskBadge: View {
    let count: Int
    let completed: Int
    let label: String
    let color: Color

    init(count: Int, completed: Int = 0, label: String, color: Color) {
        self.count = count
        self.completed = completed
        self.label = label
        self.color = color
    }

    var body: some View {
        HStack(spacing: 4) {
            if completed > 0 {
                Text("\(completed)/\(count)")
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            } else {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(completed == count && count > 0 ? .green : color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((completed == count && count > 0 ? Color.green : color).opacity(0.15))
        .cornerRadius(6)
    }
}

// MARK: - Word Section

struct WordSection: View {
    let label: String
    let words: [String]
    let completedWords: [String]
    let backgroundColor: Color
    let textColor: Color

    init(label: String, words: [String], completedWords: [String] = [], backgroundColor: Color, textColor: Color) {
        self.label = label
        self.words = words
        self.completedWords = completedWords
        self.backgroundColor = backgroundColor
        self.textColor = textColor
    }

    private var totalCount: Int {
        words.count + completedWords.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                if completedWords.isEmpty {
                    Text("(\(words.count))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text("(\(completedWords.count)/\(totalCount) done)")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }
            }

            // Completed words with strikethrough
            if !completedWords.isEmpty {
                Text(completedWords.joined(separator: ", "))
                    .font(.system(size: 15))
                    .strikethrough(true, color: .gray)
                    .foregroundColor(.gray)
                    .lineSpacing(4)
            }

            // Remaining words
            if !words.isEmpty {
                Text(words.joined(separator: ", "))
                    .font(.system(size: 15))
                    .foregroundColor(textColor)
                    .lineSpacing(4)
            }
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
