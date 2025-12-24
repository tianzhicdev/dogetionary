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
            // Cyberpunk gradient background - matches SettingsView
            AppTheme.verticalGradient2
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(AppTheme.accentCyan)
                            Text("LOADING SCHEDULE...")
                                .foregroundColor(AppTheme.smallTitleText)
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
                                    .foregroundColor(AppTheme.accentCyan)
                                Text("ALL CAUGHT UP!")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppTheme.smallTitleText)
                                Text("NO TASKS SCHEDULED FOR THE NEXT 60 DAYS.")
                                    .foregroundColor(AppTheme.smallTextColor1)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            EmptyStateView(
                                icon: "calendar.badge.plus",
                                title: "No Schedule Yet",
                                message: "No schedule available."
                            )
                        }
                    }
                }
            }
        }
        .errorToast(message: errorMessage) {
            errorMessage = nil
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

        isCreatingSchedule = true

        // UserManager's activeTestType didSet will automatically sync to server
        // No need to call updateTestSettingsInBackend - it's already handled!

        // Wait briefly for sync to complete
        try? await Task.sleep(nanoseconds: AppConstants.Delay.scheduleRefresh) // 0.5 seconds

        // Reload schedule to reflect changes (schedule is calculated on-the-fly from preferences)
        await loadScheduleRangeAsync()
        isCreatingSchedule = false

        // Note: testSettingsChanged notification is already posted by UserManager.syncTestSettingsToServer()
    }

    private func handleTargetDaysChange() async {
        guard !isCreatingSchedule, let _ = userManager.activeTestType else { return }

        isCreatingSchedule = true

        // UserManager's targetDays didSet will automatically sync to server
        // No need to call updateTestSettingsInBackend - it's already handled!

        // Wait briefly for sync to complete
        try? await Task.sleep(nanoseconds: AppConstants.Delay.scheduleRefresh) // 0.5 seconds

        // Reload schedule (schedule is calculated on-the-fly from preferences)
        await loadScheduleRangeAsync()
        isCreatingSchedule = false

        // Note: testSettingsChanged notification is already posted by UserManager.syncTestSettingsToServer()
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
                                Text("TEST LEVEL")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(AppTheme.smallTitleText)
                            }

                            Menu {
                                Button(action: { activeTestType = nil }) {
                                    HStack {
                                        Text("NONE")
                                        if activeTestType == nil {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Divider()
                                Button(action: { activeTestType = .toeflBeginner }) {
                                    HStack {
                                        Text("TOEFL BEGINNER")
                                        if activeTestType == .toeflBeginner {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Button(action: { activeTestType = .toeflIntermediate }) {
                                    HStack {
                                        Text("TOEFL INTERMEDIATE")
                                        if activeTestType == .toeflIntermediate {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Button(action: { activeTestType = .toeflAdvanced }) {
                                    HStack {
                                        Text("TOEFL ADVANCED")
                                        if activeTestType == .toeflAdvanced {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Divider()
                                Button(action: { activeTestType = .ieltsBeginner }) {
                                    HStack {
                                        Text("IELTS BEGINNER")
                                        if activeTestType == .ieltsBeginner {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Button(action: { activeTestType = .ieltsIntermediate }) {
                                    HStack {
                                        Text("IELTS INTERMEDIATE")
                                        if activeTestType == .ieltsIntermediate {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Button(action: { activeTestType = .ieltsAdvanced }) {
                                    HStack {
                                        Text("IELTS ADVANCED")
                                        if activeTestType == .ieltsAdvanced {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Divider()
                                Button(action: { activeTestType = .businessEnglish }) {
                                    HStack {
                                        Text("BUSINESS ENGLISH")
                                        if activeTestType == .businessEnglish {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                Button(action: { activeTestType = .everydayEnglish }) {
                                    HStack {
                                        Text("EVERYDAY ENGLISH")
                                        if activeTestType == .everydayEnglish {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                                if DebugConfig.showDemoTest {
                                    Divider()
                                    Button(action: { activeTestType = .demo }) {
                                        HStack {
                                            Text("DEMO BUNDLE")
                                            if activeTestType == .demo {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(testTypeLabel.uppercased())
                                        .font(.subheadline)
                                        .foregroundColor(AppTheme.textFieldUserInput)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.smallTitleText)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(AppTheme.textFieldBackgroundColor)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(AppTheme.textFieldBorderColor, lineWidth: 1)
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
                                    Text("STUDY DURATION")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(AppTheme.smallTitleText)
                                }

                                Menu {
                                    ForEach(1...365, id: \.self) { days in
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
                                        Text("\(targetDays) DAYS → \(formattedEndDate(days: targetDays).uppercased())")
                                            .font(.subheadline)
                                            .foregroundColor(AppTheme.textFieldUserInput)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption2)
                                            .foregroundColor(AppTheme.smallTitleText)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(AppTheme.textFieldBackgroundColor)
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(AppTheme.textFieldBorderColor, lineWidth: 1)
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
                                    .tint(AppTheme.accentCyan)
                                Text("UPDATING SCHEDULE...")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.smallTextColor1)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16)
                    .background(AppTheme.clear)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // Show empty state message when no schedules but config header is visible
                if filteredSchedules.isEmpty && showConfigHeader {
                    VStack(spacing: 16) {
                        if activeTestType == nil {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 48))
                                .foregroundColor(AppTheme.accentCyan)
                            Text("NO TEST SELECTED")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.smallTitleText)
                            Text("SELECT A TEST LEVEL ABOVE TO CREATE YOUR STUDY SCHEDULE")
                                .foregroundColor(AppTheme.smallTextColor1)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else if !userHasSchedule {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 48))
                                .foregroundColor(AppTheme.selectableTint)
                            Text("NO SCHEDULE CREATED")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.smallTitleText)
                            Text("PLEASE WAIT WHILE WE CREATE YOUR STUDY SCHEDULE")
                                .foregroundColor(AppTheme.smallTextColor1)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(AppTheme.accentCyan)
                            Text("ALL CAUGHT UP!")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.smallTitleText)
                            Text("NO TASKS SCHEDULED FOR THE NEXT 60 DAYS")
                                .foregroundColor(AppTheme.smallTextColor1)
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
        case .demo: return "Demo Bundle"
        case .businessEnglish: return "Business English"
        case .everydayEnglish: return "Everyday English"
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
        return testType.replacingOccurrences(of: "_", with: " ")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Date badge
                VStack(spacing: 2) {
                    Text(dayOfMonth)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppTheme.smallTitleText)
                    Text(monthAbbreviation.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.smallTitleText)
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(dayOfWeek)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppTheme.smallTitleText)

                        if isToday {
                            Text("TODAY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(AppTheme.bgPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(AppTheme.accentPurple)
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(AppTheme.bgPrimary)

//            Divider()
//                .background(AppTheme.accentCyan.opacity(0.3))

            // Word lists
            VStack(spacing: 12) {
                // New words section (show if there are remaining OR completed words)
                let newWords = entry.new_words ?? []
                let newWordsCompleted = entry.new_words_completed ?? []
                if !newWords.isEmpty || !newWordsCompleted.isEmpty {
                    WordSection(
                        label: "NEW WORDS",
                        words: newWords,
                        completedWords: newWordsCompleted,
                        backgroundColor: AppTheme.clear,
                        textColor: AppTheme.accentCyan
                    )
                }

                // Test practice section
                let testWords = entry.test_practice_words ?? []
                let testWordsCompleted = entry.test_practice_words_completed ?? []
                if !testWords.isEmpty || !testWordsCompleted.isEmpty {
                    WordSection(
                        label: "\(testLabel.uppercased()) PRACTICE",
                        words: testWords.map { $0.word },
                        completedWords: testWordsCompleted.map { $0.word },
                        backgroundColor: AppTheme.clear,
                        textColor: AppTheme.accentCyan
                    )
                }

                // Non-test practice section
                let practiceWords = entry.non_test_practice_words ?? []
                let practiceWordsCompleted = entry.non_test_practice_words_completed ?? []
                if !practiceWords.isEmpty || !practiceWordsCompleted.isEmpty {
                    WordSection(
                        label: "CUSTOM PRACTICE",
                        words: practiceWords.map { $0.word },
                        completedWords: practiceWordsCompleted.map { $0.word },
                        backgroundColor: AppTheme.clear,
                        textColor: AppTheme.accentCyan
                    )
                }
            }
            .padding(16)
            .background(AppTheme.bgPrimary)
        }
        .background(Color.clear)
        .cornerRadius(10)
//        .overlay(
//            RoundedRectangle(cornerRadius: 4)
//                .stroke(AppTheme.accentCyan.opacity(0.3), lineWidth: 1)
//        )
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
                    .foregroundColor(AppTheme.accentCyan)
            } else {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
            }
            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(completed == count && count > 0 ? AppTheme.accentCyan : AppTheme.smallTitleText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(AppTheme.panelFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(completed == count && count > 0 ? AppTheme.accentCyan : AppTheme.selectableTint.opacity(0.3), lineWidth: 1)
                )
        )
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
                    .foregroundColor(AppTheme.accentPink)
                if completedWords.isEmpty {
                    Text("(\(words.count))")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.accentPink)
                } else {
                    Text("(\(completedWords.count)/\(totalCount) DONE)")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.accentPink)
                }
            }

            // Completed words with strikethrough
            if !completedWords.isEmpty {
                Text(completedWords.joined(separator: "  "))
                    .font(.system(size: 15))
                    .strikethrough(true, color: AppTheme.smallTextColor1)
                    .foregroundColor(AppTheme.smallTextColor1)
                    .lineSpacing(4)
            }

            // Remaining words
            if !words.isEmpty {
                Text(words.joined(separator: "  "))
                    .font(.system(size: 20))
                    .foregroundColor(textColor)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(backgroundColor)
//        .cornerRadius(4)
//        .overlay(
//            RoundedRectangle(cornerRadius: 4)
//                .stroke(AppTheme.accentCyan.opacity(0.2), lineWidth: 1)
//        )
    }
}

// MARK: - Empty State


#Preview {
    ScheduleView()
}
