//
//  DebugOverlayView.swift
//  dogetionary
//
//  Global debug overlay with draggable bug icon
//  Shows: Question queue, Network calls, Local state
//

import SwiftUI

struct DebugOverlayView: View {
    @State private var isExpanded = false
    @State private var position = CGPoint(x: 50, y: 100)
    @State private var selectedTab = 0
    @GestureState private var dragOffset = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isExpanded {
                    // Full debug panel
                    VStack(spacing: 0) {
                        // Header with tabs
                        HStack(spacing: 0) {
                            TabButton(title: "Queue", isSelected: selectedTab == 0) {
                                selectedTab = 0
                            }
                            TabButton(title: "Network", isSelected: selectedTab == 1) {
                                selectedTab = 1
                            }
                            TabButton(title: "State", isSelected: selectedTab == 2) {
                                selectedTab = 2
                            }

                            Spacer()

                            // Close button
                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    isExpanded = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.gray)
                            }
                            .padding(.trailing, 8)
                        }
                        .padding(.top, 8)
                        .background(.ultraThinMaterial)

                        Divider()

                        // Tab content
                        TabView(selection: $selectedTab) {
                            QuestionQueueDebugTab()
                                .tag(0)

                            NetworkCallsDebugTab()
                                .tag(1)

                            LocalStateDebugTab()
                                .tag(2)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                    .frame(width: min(geometry.size.width - 40, 380), height: min(geometry.size.height - 100, 550))
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.3), radius: 10)
                    .position(
                        x: min(max(position.x + dragOffset.width, 200), geometry.size.width - 200),
                        y: min(max(position.y + dragOffset.height, 300), geometry.size.height - 300)
                    )
                    .gesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                position.x += value.translation.width
                                position.y += value.translation.height

                                // Keep within bounds
                                position.x = min(max(position.x, 200), geometry.size.width - 200)
                                position.y = min(max(position.y, 300), geometry.size.height - 300)
                            }
                    )
                } else {
                    // Collapsed: just bug icon
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded = true
                        }
                    }) {
                        Image(systemName: "ladybug.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 5)
                    }
                    .position(
                        x: min(max(position.x + dragOffset.width, 30), geometry.size.width - 30),
                        y: min(max(position.y + dragOffset.height, 50), geometry.size.height - 50)
                    )
                    .gesture(
                        DragGesture()
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                position.x += value.translation.width
                                position.y += value.translation.height

                                // Keep within bounds
                                position.x = min(max(position.x, 30), geometry.size.width - 30)
                                position.y = min(max(position.y, 50), geometry.size.height - 50)
                            }
                    )
                }
            }
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(isSelected ? .white : .gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AppTheme.selectableTint : Color.clear)
                .cornerRadius(6)
        }
    }
}

// MARK: - Question Queue Tab

struct QuestionQueueDebugTab: View {
    @ObservedObject private var queueManager = QuestionQueueManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Header stats
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Queue Count")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(queueManager.queueCount)")
                            .font(.title2.bold())
                            .foregroundColor(AppTheme.selectableTint)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total Available")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(queueManager.totalAvailable)")
                            .font(.title2.bold())
                            .foregroundColor(.green)
                    }

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Has More")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Image(systemName: queueManager.hasMore ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(queueManager.hasMore ? .green : .gray)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Queue status
                if queueManager.isFetching {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Fetching...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                }

                if let error = queueManager.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal)
                }

                // Question list
                if queueManager.questionQueue.isEmpty {
                    Text("No questions in queue")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding()
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(queueManager.questionQueue.enumerated()), id: \.element.word) { index, question in
                            QuestionQueueRow(index: index, question: question)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Question Queue Row

struct QuestionQueueRow: View {
    let index: Int
    let question: BatchReviewQuestion
    @ObservedObject private var videoService = VideoService.shared

    private func getVideoState() -> VideoDownloadState? {
        guard question.question.question_type == "video_mc",
              let videoId = question.question.video_id else {
            return nil
        }
        return videoService.getDownloadState(videoId: videoId)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Position
            Text("\(index)")
                .font(.caption.monospaced())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(sourceColor))

            // Word
            Text(question.word)
                .font(.caption.bold())
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            // Question type badge
            Text(questionTypeLabel)
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(questionTypeColor)
                .cornerRadius(4)

            // Video download status with detailed badge
            if let videoState = getVideoState() {
                VideoStatusBadge(state: videoState)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private var sourceColor: Color {
        switch question.source {
        case "new": return .blue
        case "test_practice": return .orange
        case "non_test_practice": return .green
        case "not_due_yet": return .purple
        default: return .gray
        }
    }

    private var questionTypeLabel: String {
        switch question.question.question_type {
        case "recognition": return "RECOG"
        case "mc_definition": return "MC-DEF"
        case "mc_word": return "MC-WRD"
        case "fill_blank": return "FILL"
        case "pronounce_sentence": return "PRON"
        case "video_mc": return "VIDEO"
        default: return question.question.question_type.uppercased()
        }
    }

    private var questionTypeColor: Color {
        switch question.question.question_type {
        case "recognition": return .blue
        case "mc_definition": return .green
        case "mc_word": return .purple
        case "fill_blank": return .orange
        case "pronounce_sentence": return .pink
        case "video_mc": return .red
        default: return .gray
        }
    }
}

// MARK: - Network Calls Tab

struct NetworkCallsDebugTab: View {
    @ObservedObject private var networkLogger = NetworkLogger.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header with clear button
            HStack {
                Text("\(networkLogger.recentCalls.count) calls")
                    .font(.caption)
                    .foregroundColor(.gray)

                Spacer()

                Button(action: {
                    networkLogger.clearLogs()
                }) {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))

            if networkLogger.recentCalls.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "network.slash")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No network calls logged")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(networkLogger.recentCalls) { call in
                        NetworkCallRow(call: call)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Network Call Row

struct NetworkCallRow: View {
    let call: NetworkLogger.NetworkCall
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                // Request details
                VStack(alignment: .leading, spacing: 4) {
                    Text("REQUEST")
                        .font(.caption2.bold())
                        .foregroundColor(.gray)

                    Text("\(call.method) \(call.url)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.primary)

                    if let body = call.requestBody {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(body)
                                .font(.caption2.monospaced())
                                .foregroundColor(.blue)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.vertical, 4)

                Divider()

                // Response details
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("RESPONSE")
                            .font(.caption2.bold())
                            .foregroundColor(.gray)

                        Spacer()

                        if let status = call.responseStatus {
                            Text("\(status)")
                                .font(.caption2.bold())
                                .foregroundColor(call.statusColor)
                        }

                        Text(call.durationString)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }

                    if let error = call.error {
                        Text("Error: \(error)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    if let body = call.responseBody {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(body)
                                .font(.caption2.monospaced())
                                .foregroundColor(.green)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.vertical, 8)
        } label: {
            HStack(spacing: 8) {
                // Status indicator
                Circle()
                    .fill(call.statusColor)
                    .frame(width: 8, height: 8)

                // Method badge
                Text(call.method)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)

                // Endpoint
                Text(call.url.components(separatedBy: "/").suffix(2).joined(separator: "/"))
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // Timestamp
                Text(call.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Local State Tab

struct LocalStateDebugTab: View {
    @ObservedObject private var userManager = UserManager.shared
    @ObservedObject private var queueManager = QuestionQueueManager.shared
    @State private var appState = AppState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // UserManager state
                StateSection(title: "UserManager") {
                    StateRow(key: "User ID", value: userManager.userID)
                    StateRow(key: "User Name", value: userManager.userName.isEmpty ? "(empty)" : userManager.userName)
                    StateRow(key: "Learning Language", value: userManager.learningLanguage)
                    StateRow(key: "Native Language", value: userManager.nativeLanguage)
                    StateRow(key: "Practice Count", value: "\(userManager.practiceCount)")
                    StateRow(key: "Completed Onboarding", value: "\(userManager.hasCompletedOnboarding)")
                }

                // AppState
                StateSection(title: "AppState") {
                    StateRow(key: "Navigate to Review", value: "\(appState.shouldNavigateToReview)")
                    StateRow(key: "Test Settings Changed", value: "\(appState.testSettingsChanged)")
                    StateRow(key: "Environment Changed", value: "\(appState.environmentChanged)")
                    StateRow(key: "Should Refresh Saved", value: "\(appState.shouldRefreshSavedWords)")
                }

                // QuestionQueue
                StateSection(title: "QuestionQueue") {
                    StateRow(key: "Queue Count", value: "\(queueManager.queueCount)")
                    StateRow(key: "Has More", value: "\(queueManager.hasMore)")
                    StateRow(key: "Is Fetching", value: "\(queueManager.isFetching)")
                    StateRow(key: "Total Available", value: "\(queueManager.totalAvailable)")
                    StateRow(key: "Debug Mode", value: "\(queueManager.debugMode)")
                }

                // Configuration
                StateSection(title: "Configuration") {
                    StateRow(key: "Base URL", value: Configuration.effectiveBaseURL)
                    StateRow(key: "Environment", value: Configuration.environment == .development ? "Development" : "Production")
                    StateRow(key: "Developer Mode", value: "\(DebugConfig.isDeveloperModeEnabled)")
                }

                // Video Cache
                StateSection(title: "Video Cache") {
                    let (fileCount, sizeBytes) = VideoService.shared.getCacheInfo()
                    StateRow(key: "Cached Videos", value: "\(fileCount)")
                    StateRow(key: "Cache Size", value: String(format: "%.1f MB", Double(sizeBytes) / 1024 / 1024))
                }
            }
            .padding()
        }
    }
}

// MARK: - State Section

struct StateSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(AppTheme.selectableTint)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

// MARK: - State Row

struct StateRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack {
            Text(key)
                .font(.caption)
                .foregroundColor(.gray)

            Spacer()

            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Video Status Badge

struct VideoStatusBadge: View {
    let state: VideoDownloadState

    var body: some View {
        HStack(spacing: 2) {
            // Icon
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundColor(statusColor)

            // Status text
            Text(statusText)
                .font(.caption2.monospacedDigit())
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(statusColor.opacity(0.15))
        )
    }

    private var iconName: String {
        switch state {
        case .notStarted:
            return "hourglass"
        case .downloading:
            return "arrow.down.circle.fill"
        case .cached:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch state {
        case .notStarted:
            return .gray
        case .downloading:
            return .blue
        case .cached:
            return .green
        case .failed:
            return .red
        }
    }

    private var statusText: String {
        switch state {
        case .notStarted:
            return "⏳"

        case .downloading(let progress, let startTime, let bytesDownloaded, let totalBytes):
            let elapsed = Date().timeIntervalSince(startTime)
            let progressPercent = Int(progress * 100)

            if let totalBytes = totalBytes, totalBytes > 0 {
                let downloadedMB = Double(bytesDownloaded) / 1024 / 1024
                let totalMB = Double(totalBytes) / 1024 / 1024
                let speed = elapsed > 0 ? downloadedMB / elapsed : 0
                return String(format: "%d%% %.1fs %.1fMB/s", progressPercent, elapsed, speed)
            } else {
                return String(format: "%d%% %.1fs", progressPercent, elapsed)
            }

        case .cached(_, let duration, let fileSize):
            let sizeMB = Double(fileSize) / 1024 / 1024
            if duration > 0 {
                return String(format: "%.1fs %.1fMB", duration, sizeMB)
            } else {
                return String(format: "%.1fMB", sizeMB)
            }

        case .failed(_, let retryCount, let duration):
            if let duration = duration {
                return String(format: "❌×%d %.1fs", retryCount, duration)
            } else {
                return String(format: "❌×%d", retryCount)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()

        DebugOverlayView()
    }
}
