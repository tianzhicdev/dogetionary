//
//  FloatingActionMenu.swift
//  dogetionary
//
//  Floating action button menu for navigation
//

import SwiftUI

struct FloatingActionMenu: View {
    @Binding var isExpanded: Bool
    @Binding var selectedView: Int
    let practiceCount: Int
    let onItemTapped: (Int) -> Void

    // Detect reduce motion preference
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Animation state for practice alert
    @State private var isPulsing = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Dimmed overlay when expanded (tap to dismiss)
            if isExpanded {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeMenu()
                    }
                    .transition(.opacity)
            }

            VStack(spacing: 12) {
                if isExpanded {
                    // Menu items (appear with staggered animation)
                    ForEach(Array(menuItems.enumerated()), id: \.offset) { index, item in
                        FloatingMenuItem(
                            icon: item.icon,
                            label: item.label,
                            tag: item.tag,
                            badge: item.tag == 2 ? practiceCount : nil,
                            isSelected: selectedView == item.tag,
                            gradient: item.color,
                            onTap: {
                                handleItemTap(item.tag)
                            }
                        )
                        .transition(.scale.combined(with: .opacity))
                        .animation(
                            reduceMotion
                                ? .easeInOut(duration: 0.2)
                                : .spring(response: 0.3, dampingFraction: 0.7).delay(Double(index) * 0.05),
                            value: isExpanded
                        )
                    }
                }

                // Main FAB (always visible)
                Button(action: {
                    toggleMenu()
                }) {
                    ZStack(alignment: .topTrailing) {
                        // Main button - show brain icon when practice is due and not on practice view
                        let showBrainIcon = practiceCount > 0 && selectedView != 2 && !isExpanded

                        Image(systemName: isExpanded ? "xmark" : (showBrainIcon ? "brain.head.profile" : "line.3.horizontal"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(showBrainIcon ? AppTheme.errorColor : AppTheme.primaryBlue)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .scaleEffect(showBrainIcon && isPulsing ? 1.15 : 1.0)
                            .rotationEffect(.degrees(showBrainIcon && isPulsing ? 5 : 0))

                        // Badge for practice count on brain icon
                        if showBrainIcon {
                            Text("\(practiceCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .frame(minWidth: 20)
                                .background(AppTheme.warningColor)
                                .clipShape(Capsule())
                                .offset(x: 8, y: -4)
                        }
                    }
                }
                .accessibilityLabel(isExpanded ? "Close menu" : "Open menu")
                .accessibilityHint("Double tap to \(isExpanded ? "close" : "open") navigation menu")
                .onAppear {
                    if practiceCount > 0 && selectedView != 2 && !reduceMotion {
                        startPulseAnimation()
                    }
                }
                .onChange(of: practiceCount) { _, newCount in
                    if newCount > 0 && selectedView != 2 && !reduceMotion {
                        startPulseAnimation()
                    }
                }
                .onChange(of: isExpanded) { _, expanded in
                    // Restart animation when menu closes and practice is still due
                    if !expanded && practiceCount > 0 && selectedView != 2 && !reduceMotion {
                        startPulseAnimation()
                    }
                }
                .onChange(of: selectedView) { _, newView in
                    // Start/stop animation when navigating to/from practice view
                    if practiceCount > 0 && !reduceMotion {
                        if newView != 2 {
                            startPulseAnimation()
                        } else {
                            stopPulseAnimation()
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // Menu items configuration
    private var menuItems: [(icon: String, label: String, tag: Int, color: LinearGradient)] {
        [
            (icon: "magnifyingglass", label: "Search", tag: 0, color: AppTheme.primaryGradient),
            (icon: "calendar", label: "Schedule", tag: 1, color: AppTheme.feedbackSelectedGradient),
            (icon: "brain.head.profile", label: "Practice", tag: 2, color: AppTheme.feedbackCorrectGradient),
            (icon: "book.fill", label: "Vocabulary", tag: 3, color: LinearGradient(
                colors: [AppTheme.warningColor, AppTheme.yellowGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )),
            (icon: "trophy.fill", label: "Leaderboard", tag: 4, color: AppTheme.goldGradient),
            (icon: "gear", label: "Settings", tag: 5, color: LinearGradient(
                colors: [AppTheme.accentPurple, AppTheme.primaryBlue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        ]
    }

    private func toggleMenu() {
        // Check if brain icon is showing - if so, go directly to practice mode
        let showBrainIcon = practiceCount > 0 && selectedView != 2 && !isExpanded

        if showBrainIcon {
            // Navigate directly to practice mode
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()

            onItemTapped(2)  // Tag 2 = Practice view
        } else {
            // Normal menu toggle behavior
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }
    }

    private func closeMenu() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.7)) {
            isExpanded = false
        }
    }

    private func handleItemTap(_ tag: Int) {
        // Haptic feedback for selection
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()

        // Close menu and notify parent
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.7)) {
            isExpanded = false
        }

        // Slight delay before navigating to allow menu to close smoothly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onItemTapped(tag)
        }
    }

    private func startPulseAnimation() {
        // Reset animation state first to ensure it restarts
        isPulsing = false

        // Small delay to allow state reset, then start bouncy animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            withAnimation(
                .spring(response: 0.6, dampingFraction: 0.5)
                .repeatForever(autoreverses: true)
            ) {
                self.isPulsing = true
            }
        }
    }

    private func stopPulseAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPulsing = false
        }
    }
}

struct FloatingMenuItem: View {
    let icon: String
    let label: String
    let tag: Int
    var badge: Int? = nil
    var isSelected: Bool = false
    let gradient: LinearGradient
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Solid color text label
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 100, alignment: .leading)

                ZStack(alignment: .topTrailing) {
                    // Gradient background circle
                    Circle()
                        .fill(gradient)
                        .frame(width: 48, height: 48)
                        .opacity(isSelected ? 1.0 : 0.3)

                    // Solid white icon on top
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)

                    // Badge for practice count
                    if let badge = badge, badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(minWidth: 20)
                            .background(AppTheme.errorColor)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 200)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .accessibilityLabel("\(label)\(badge != nil && badge! > 0 ? ", \(badge!) items" : "")")
        .accessibilityHint("Double tap to navigate to \(label)")
    }
}

#Preview("Collapsed FAB") {
    ZStack {
        AppTheme.backgroundGradient.ignoresSafeArea()

        FloatingActionMenu(
            isExpanded: .constant(false),
            selectedView: .constant(0),
            practiceCount: 5,
            onItemTapped: { _ in }
        )
    }
}

#Preview("Expanded Menu") {
    ZStack {
        AppTheme.backgroundGradient.ignoresSafeArea()

        FloatingActionMenu(
            isExpanded: .constant(true),
            selectedView: .constant(2),
            practiceCount: 12,
            onItemTapped: { _ in }
        )
    }
}
