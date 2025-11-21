//
//  TestProgressBar.swift
//  dogetionary
//
//  Created by Claude Code on 11/18/25.
//

import SwiftUI

struct TestProgressBar: View {
    let progress: Double // 0.0 to 1.0
    let totalWords: Int
    let savedWords: Int
    let testType: String
    let streakDays: Int  // Streak days

    @State private var animatedProgress: Double = 0.0
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with test type badge and details toggle
            HStack {
                // Test type badge
                HStack(spacing: 4) {
                    Image(systemName: "target")
                        .font(.system(size: 12, weight: .semibold))
                    Text(testType)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(gradientForTestType)
                )

                Spacer()

                // Progress percentage
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                // Expand/collapse button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showDetails.toggle()
                    }
                }) {
                    Image(systemName: showDetails ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 20)

                // Animated progress fill with gradient
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradientColors),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * animatedProgress, height: 20)
                        .overlay(
                            // Shimmer effect
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.0),
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.0)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * animatedProgress)
                                .mask(
                                    RoundedRectangle(cornerRadius: 8)
                                        .frame(width: geometry.size.width * animatedProgress)
                                )
                                .offset(x: showDetails ? 0 : -100)
                                .animation(
                                    Animation.linear(duration: 1.5)
                                        .repeatForever(autoreverses: false),
                                    value: showDetails
                                )
                        )
                }
                .frame(height: 20)

                // Progress text overlay
                HStack {
                    Spacer()
                    Text("\(savedWords) / \(totalWords)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(animatedProgress > 0.5 ? .white : .primary)
                        .padding(.trailing, 8)
                }
            }

            // Detailed stats (expandable)
            if showDetails {
                VStack(spacing: 8) {
                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(totalWords - savedWords)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.orange)
                        }

                        Spacer()

                        VStack(alignment: .center, spacing: 4) {
                            Text("Streak")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(streakDays > 0 ? .orange : .gray)
                                    .font(.system(size: 14))
                                Text("\(streakDays)")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(streakDays > 0 ? .orange : .gray)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Completed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(savedWords)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.green)
                        }
                    }

                    // Motivational message
                    HStack {
                        Image(systemName: motivationalIcon)
                            .foregroundColor(motivationalColor)
                        Text(motivationalMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { oldValue, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedProgress = newValue
            }
        }
    }

    // MARK: - Computed Properties

    private var gradientColors: [Color] {
        switch testType {
        case "TOEFL":
            return [Color.blue, Color.cyan]
        case "IELTS":
            return [Color.purple, Color.pink]
        case "BOTH":
            return [Color.blue, Color.purple, Color.pink]
        default:
            return [Color.green, Color.blue]
        }
    }

    private var gradientForTestType: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: gradientColors),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var motivationalMessage: String {
        let percentage = progress * 100
        switch percentage {
        case 0..<10:
            return "Every journey begins with a single step!"
        case 10..<25:
            return "Great start! Keep the momentum going."
        case 25..<50:
            return "You're making solid progress!"
        case 50..<75:
            return "More than halfway there! You've got this!"
        case 75..<90:
            return "Almost there! The finish line is in sight."
        case 90..<100:
            return "Final sprint! You're so close!"
        default:
            return "Congratulations! You've mastered all words!"
        }
    }

    private var motivationalIcon: String {
        let percentage = progress * 100
        switch percentage {
        case 0..<25:
            return "flag.fill"
        case 25..<50:
            return "flame.fill"
        case 50..<75:
            return "bolt.fill"
        case 75..<100:
            return "star.fill"
        default:
            return "trophy.fill"
        }
    }

    private var motivationalColor: Color {
        let percentage = progress * 100
        switch percentage {
        case 0..<25:
            return .blue
        case 25..<50:
            return .orange
        case 50..<75:
            return .purple
        case 75..<100:
            return .yellow
        default:
            return .green
        }
    }
}

// Preview
struct TestProgressBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TestProgressBar(
                progress: 0.15,
                totalWords: 3500,
                savedWords: 525,
                testType: "TOEFL",
                streakDays: 5
            )

            TestProgressBar(
                progress: 0.67,
                totalWords: 2800,
                savedWords: 1876,
                testType: "IELTS",
                streakDays: 12
            )

            TestProgressBar(
                progress: 0.92,
                totalWords: 5000,
                savedWords: 4600,
                testType: "BOTH",
                streakDays: 0
            )
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
