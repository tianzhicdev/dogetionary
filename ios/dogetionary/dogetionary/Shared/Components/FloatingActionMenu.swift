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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Dimmed overlay when expanded (tap to dismiss)
            if isExpanded {
                AppTheme.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeMenu()
                    }
                    .transition(.opacity)
            }

            VStack(spacing: 2) {
                if isExpanded {
                    // Menu items (appear with staggered animation)
                    ForEach(Array(menuItems.enumerated()), id: \.offset) { index, item in
                        FloatingMenuItem(
                            icon: item.icon,
                            label: item.label,
                            tag: item.tag,
                            badge: item.tag == 2 ? practiceCount : nil,
                            isSelected: selectedView == item.tag,
                            shouldHighlight: item.tag == 2 && practiceCount > 0 && selectedView != 2,
                            shouldWiggle: item.tag == 2 && practiceCount > 0 && selectedView != 2,
                            gradient: item.color,
                            onTap: {
                                handleItemTap(item.tag)
                            }
                        )
                        .transition(.scale.combined(with: .opacity))
                        .animation(
                            reduceMotion
                                ? .easeInOut(duration: AppConstants.Animation.easeShortDuration)
                                : .spring(response: AppConstants.Animation.springResponse, dampingFraction: AppConstants.Animation.springDamping).delay(Double(index) * 0.05),
                            value: isExpanded
                        )
                    }
                }

                // Main FAB (always visible)
                Button(action: {
                    toggleMenu()
                }) {
                    Image(systemName: isExpanded ? "xmark" : "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppTheme.bgPrimary)
                        .frame(width: 56, height: 56)
                        .background(AppTheme.accentCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .accessibilityLabel(isExpanded ? "Close menu" : "Open menu")
                .accessibilityHint("Double tap to \(isExpanded ? "close" : "open") navigation menu")
            }
            .padding(16)
        }
    }

    // Menu items configuration
    private var menuItems: [(icon: String, label: String, tag: Int, color: LinearGradient)] {
        [
            (icon: "magnifyingglass", label: "Search", tag: 0, color: LinearGradient(
                colors: [AppTheme.accentCyan, AppTheme.neonPurple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )),
            (icon: "brain.head.profile", label: "Practice", tag: 2, color: LinearGradient(
                colors: [AppTheme.accentPink, AppTheme.neonPurple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )),
            (icon: "book.fill", label: "Vocabulary", tag: 3, color: LinearGradient(
                colors: [AppTheme.neonPurple, AppTheme.accentCyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )),
            (icon: "gear", label: "Settings", tag: 5, color: LinearGradient(
                colors: [AppTheme.accentCyan, AppTheme.accentPink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        ]
    }

    private func toggleMenu() {
        // Normal menu toggle behavior
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        withAnimation(reduceMotion ? .easeInOut(duration: AppConstants.Animation.easeShortDuration) : .spring(response: AppConstants.Animation.springResponse, dampingFraction: AppConstants.Animation.springDamping)) {
            isExpanded.toggle()
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
}

struct FloatingMenuItem: View {
    let icon: String
    let label: String
    let tag: Int
    var badge: Int? = nil
    var isSelected: Bool = false
    var shouldHighlight: Bool = false
    var shouldWiggle: Bool = false
    let gradient: LinearGradient
    let onTap: () -> Void

    // Detect reduce motion preference
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Animation state for wiggle
    @State private var isWiggling = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Solid color text label
                Text(label.uppercased())
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.bodyText)
                    .frame(width: 120, alignment: .leading)
                    

                ZStack(alignment: .topTrailing) {

                    // Solid white icon on top
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppTheme.selectableTint)
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(shouldWiggle && isWiggling ? 5 : 0))

                    // Badge for practice count
                    if let badge = badge, badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AppTheme.bgPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(minWidth: 20)
                            .background(AppTheme.electricYellow)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 200)
            .background(shouldHighlight ? gradient : AppTheme.verticalGradient2)
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .cornerRadius(4)
        }
        .accessibilityLabel("\(label)\(badge != nil && badge! > 0 ? ", \(badge!) items" : "")")
        .accessibilityHint("Double tap to navigate to \(label)")
        .onAppear {
            if shouldWiggle && !reduceMotion {
                startWiggleAnimation()
            }
        }
        .onChange(of: shouldWiggle) { _, newValue in
            if newValue && !reduceMotion {
                startWiggleAnimation()
            } else {
                stopWiggleAnimation()
            }
        }
    }

    private func startWiggleAnimation() {
        // Reset animation state first to ensure it restarts
        isWiggling = false

        // Small delay to allow state reset, then start wiggle animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            withAnimation(
                .spring(response: 0.6, dampingFraction: 0.5)
                .repeatForever(autoreverses: true)
            ) {
                self.isWiggling = true
            }
        }
    }

    private func stopWiggleAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            isWiggling = false
        }
    }
}

#Preview("Collapsed FAB") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        FloatingActionMenu(
            isExpanded: .constant(false),
            selectedView: .constant(0),
            practiceCount: 5,
            onItemTapped: { _ in }
        )
    }
}

#Preview("Expanded Menu - Search Selected") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        FloatingActionMenu(
            isExpanded: .constant(true),
            selectedView: .constant(0),
            practiceCount: 12,
            onItemTapped: { _ in }
        )
    }
}

#Preview("Expanded Menu - Practice Selected") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        FloatingActionMenu(
            isExpanded: .constant(true),
            selectedView: .constant(2),
            practiceCount: 25,
            onItemTapped: { _ in }
        )
    }
}

#Preview("Expanded Menu - Vocabulary Selected") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        FloatingActionMenu(
            isExpanded: .constant(true),
            selectedView: .constant(3),
            practiceCount: 8,
            onItemTapped: { _ in }
        )
    }
}

#Preview("Expanded Menu - Leaderboard Selected") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        FloatingActionMenu(
            isExpanded: .constant(true),
            selectedView: .constant(4),
            practiceCount: 0,
            onItemTapped: { _ in }
        )
    }
}

#Preview("Collapsed with Practice Button") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        FloatingActionMenu(
            isExpanded: .constant(false),
            selectedView: .constant(0),
            practiceCount: 42,
            onItemTapped: { _ in }
        )
    }
}

#Preview("Collapsed - No Practice Available") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        FloatingActionMenu(
            isExpanded: .constant(false),
            selectedView: .constant(3),
            practiceCount: 0,
            onItemTapped: { _ in }
        )
    }
}

#Preview("Expanded Menu - High Practice Count") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        FloatingActionMenu(
            isExpanded: .constant(true),
            selectedView: .constant(1),
            practiceCount: 99,
            onItemTapped: { _ in }
        )
    }
}

#Preview("Individual Menu Item - Search") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack(spacing: 16) {
            FloatingMenuItem(
                icon: "magnifyingglass",
                label: "Search",
                tag: 0,
                isSelected: false,
                gradient: LinearGradient(
                    colors: [AppTheme.accentCyan, AppTheme.neonPurple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                onTap: { }
            )

            FloatingMenuItem(
                icon: "magnifyingglass",
                label: "Search",
                tag: 0,
                isSelected: true,
                gradient: LinearGradient(
                    colors: [AppTheme.accentCyan, AppTheme.neonPurple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                onTap: { }
            )
        }
    }
}

#Preview("Individual Menu Item - Practice with Badge") {
    ZStack {
        AppTheme.verticalGradient2.ignoresSafeArea()

        VStack(spacing: 16) {
            FloatingMenuItem(
                icon: "brain.head.profile",
                label: "Practice",
                tag: 2,
                badge: 15,
                isSelected: false,
                gradient: LinearGradient(
                    colors: [AppTheme.accentPink, AppTheme.neonPurple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                onTap: { }
            )

            FloatingMenuItem(
                icon: "brain.head.profile",
                label: "Practice",
                tag: 2,
                badge: 99,
                isSelected: true,
                gradient: LinearGradient(
                    colors: [AppTheme.accentPink, AppTheme.neonPurple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                onTap: { }
            )
        }
    }
}
