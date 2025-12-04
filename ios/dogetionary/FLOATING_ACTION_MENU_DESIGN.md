# Floating Action Menu Design

**Date**: 2025-12-03
**Status**: Design Phase
**Goal**: Replace bottom tab bar with a floating action button (FAB) that opens a menu

---

## Current Implementation Analysis

### Current Structure (ContentView.swift)
```swift
VStack {
    AppBanner()

    TabView(selection: $selectedTab) {
        DictionaryTabView(selectedTab: $selectedTab)  // Tag 0
            .tabItem { Image(systemName: "magnifyingglass"); Text("Dictionary") }

        ScheduleView()  // Tag 1
            .tabItem { Image(systemName: "calendar"); Text("Schedule") }

        ReviewView()  // Tag 2
            .tabItem { Image(systemName: "brain.head.profile"); Text("Practice") }
            .badge(userManager.practiceCount)

        LeaderboardView()  // Tag 3
            .tabItem { Image(systemName: "trophy.fill"); Text("Leaderboard") }

        SettingsView()  // Tag 4
            .tabItem { Image(systemName: "gear"); Text("Settings") }
    }
}
```

### DictionaryTabView Structure
```swift
VStack {
    // Segmented picker at top
    Picker("View", selection: $selectedView) {
        Text("Search").tag(0)
        Text("Saved").tag(1)
    }
    .pickerStyle(.segmented)

    // Content
    if selectedView == 0 {
        SearchView(selectedTab: $selectedTab, showProgressBar: true)
    } else {
        SavedWordsListView(...)
    }
}
```

**Key Findings**:
1. ✅ Bottom tab bar takes up significant vertical space
2. ✅ SearchView is the primary use case (Dictionary tab)
3. ✅ "Saved Words" is currently a secondary view within Dictionary tab
4. ✅ Practice badge shows count (important to preserve)
5. ✅ All 5 tabs are top-level navigation

---

## Proposed Design

### Design Goals
1. **Maximize content area** - Remove bottom tab bar to gain ~50pt vertical space
2. **Keep Search prominent** - Make SearchView the default/main view
3. **Elevate Saved Words** - Make it a top-level menu item (not buried in picker)
4. **Maintain accessibility** - All features remain easily accessible
5. **Visual clarity** - Menu items clearly labeled with icons

### Visual Mockup

```
┌─────────────────────────────────┐
│   App Banner                    │
├─────────────────────────────────┤
│                                 │
│   SearchView                    │
│   (Always Visible)              │
│                                 │
│   - Search bar                  │
│   - Test Progress (if any)      │
│   - Definition results          │
│                                 │
│                                 │
│                                 │
│                      ┌──────┐   │ ← When closed: Single FAB
│                      │  ⋮   │   │
│                      └──────┘   │
└─────────────────────────────────┘

When FAB is tapped (expanded state):
┌─────────────────────────────────┐
│                                 │
│   SearchView                    │
│                                 │
│              ┌──────────────┐   │
│              │ 📅 Schedule  │   │
│              ├──────────────┤   │
│              │ 🧠 Practice₃ │   │ ← Badge with count
│              ├──────────────┤   │
│              │ 📖 Saved     │   │ ← NEW: Extracted from Dictionary tab
│              ├──────────────┤   │
│              │ 🏆 Board     │   │
│              ├──────────────┤   │
│              │ ⚙️  Settings │   │
│              └──────────────┘   │
│                      [✕]        │ ← Close button (or tap outside)
└─────────────────────────────────┘
```

### Menu Items (5 items)
1. **Schedule** - Calendar icon - Navigate to ScheduleView
2. **Practice** - Brain icon + badge - Navigate to ReviewView (shows practice count)
3. **Saved Words** - Book icon - Navigate to SavedWordsListView (NEW top-level)
4. **Leaderboard** - Trophy icon - Navigate to LeaderboardView
5. **Settings** - Gear icon - Navigate to SettingsView

---

## Implementation Plan

### Phase 1: Create Floating Action Menu Component

**New File**: `FloatingActionMenu.swift`

**Features**:
- Floating button in bottom-right corner (16pt margin)
- Expand/collapse animation with spring physics
- Menu items appear with staggered animation
- Tap outside to dismiss (using overlay)
- Haptic feedback on open/close

**Component Structure**:
```swift
struct FloatingActionMenu: View {
    @Binding var isExpanded: Bool
    @Binding var selectedView: Int
    let practiceCount: Int
    let onItemTapped: (Int) -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Dimmed overlay when expanded
            if isExpanded {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { isExpanded = false }
                    }
            }

            VStack(spacing: 12) {
                if isExpanded {
                    // Menu items (appear with staggered animation)
                    FloatingMenuItem(icon: "calendar", label: "Schedule", tag: 1)
                    FloatingMenuItem(icon: "brain.head.profile", label: "Practice", tag: 2, badge: practiceCount)
                    FloatingMenuItem(icon: "book.fill", label: "Saved", tag: 3)
                    FloatingMenuItem(icon: "trophy.fill", label: "Board", tag: 4)
                    FloatingMenuItem(icon: "gear", label: "Settings", tag: 5)
                }

                // Main FAB (always visible)
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "xmark" : "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(AppTheme.primaryColor)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
            }
            .padding(16)
        }
    }
}

struct FloatingMenuItem: View {
    let icon: String
    let label: String
    let tag: Int
    var badge: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 16, weight: .medium))

            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 48, height: 48)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(radius: 2)

                if let badge = badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(AppTheme.warningColor)
                        .clipShape(Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(radius: 2)
    }
}
```

---

### Phase 2: Refactor ContentView

**Changes to ContentView.swift**:

1. **Remove TabView** - Replace with direct view switching
2. **Add navigation state** - Track which view is active
3. **Make SearchView default** - Always show as main content
4. **Add floating menu** - Overlay on top of content

**New Structure**:
```swift
struct ContentView: View {
    @StateObject private var userManager = UserManager.shared
    @State private var selectedView = 0  // 0 = Search (default)
    @State private var isMenuExpanded = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main content
            VStack(spacing: 0) {
                AppBanner()

                // View switcher
                Group {
                    switch selectedView {
                    case 0: SearchView(showProgressBar: true)
                    case 1: ScheduleView()
                    case 2: ReviewView()
                    case 3: SavedWordsView()  // NEW: Extracted saved words
                    case 4: LeaderboardView()
                    case 5: SettingsView()
                    default: SearchView(showProgressBar: true)
                    }
                }
            }

            // Floating Action Menu (overlay)
            FloatingActionMenu(
                isExpanded: $isMenuExpanded,
                selectedView: $selectedView,
                practiceCount: userManager.practiceCount,
                onItemTapped: { tag in
                    selectedView = tag
                    withAnimation { isMenuExpanded = false }
                }
            )
        }
        .onAppear { ... }
    }
}
```

---

### Phase 3: Create SavedWordsView (New Top-Level View)

**New File**: `SavedWordsView.swift`

Extract saved words functionality from DictionaryTabView into standalone view:

```swift
struct SavedWordsView: View {
    @State private var savedWords: [SavedWord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            SavedWordsListView(
                savedWords: $savedWords,
                isLoading: isLoading,
                errorMessage: errorMessage,
                onRefresh: { await loadSavedWords() },
                onDelete: { word in await deleteSavedWord(word) },
                onToggleKnown: { word in await toggleKnownStatus(word) }
            )
            .navigationTitle("Saved Words")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            Task { await loadSavedWords() }
        }
    }

    // Copy loadSavedWords, deleteSavedWord, toggleKnownStatus from DictionaryTabView
}
```

---

### Phase 4: Update DictionaryTabView

**Changes to DictionaryTabView**:
- **Remove** segmented picker (no longer needed)
- **Remove** saved words view
- **Show only** SearchView

**Simplified Structure**:
```swift
struct DictionaryTabView: View {
    var body: some View {
        SearchView(showProgressBar: true)
    }
}
```

Actually, since we're making SearchView the main view, we can eliminate DictionaryTabView entirely and use SearchView directly in ContentView.

---

## Files to Create/Modify

### New Files (2)
1. ✅ **FloatingActionMenu.swift** - Floating button + menu component
2. ✅ **SavedWordsView.swift** - Standalone saved words view

### Modified Files (2)
1. ✅ **ContentView.swift** - Replace TabView with view switching + floating menu
2. ✅ **SearchView.swift** - Minor: Remove `selectedTab` binding (no longer needed for navigation)

### Files to Delete (1)
1. ❌ **DictionaryTabView** - No longer needed (functionality absorbed into ContentView)

---

## Animation & UX Details

### Opening Animation
```swift
// Staggered appearance of menu items
ForEach(Array(menuItems.enumerated()), id: \.offset) { index, item in
    FloatingMenuItem(...)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7)
            .delay(Double(index) * 0.05), value: isExpanded)
}
```

### Closing Animation
- Reverse stagger (last item disappears first)
- Spring physics with dampingFraction: 0.7
- Background overlay fades out

### Haptic Feedback
```swift
// On menu open
let generator = UIImpactFeedbackGenerator(style: .medium)
generator.impactOccurred()

// On item tap
let selectionGenerator = UISelectionFeedbackGenerator()
selectionGenerator.selectionChanged()
```

---

## Accessibility

1. **VoiceOver Support**:
   - FAB labeled: "Menu" / "Close Menu"
   - Each menu item properly labeled
   - Badge counts announced

2. **Dynamic Type**:
   - Menu item labels scale with text size
   - FAB size remains constant (touch target)

3. **Reduce Motion**:
   - Respect UIAccessibility.isReduceMotionEnabled
   - Use fade transitions instead of spring animations

---

## Benefits

### Space Efficiency
- **Gain**: ~50pt vertical space (bottom tab bar removal)
- **Use case**: More content visible in SearchView and other views

### User Experience
- **Fewer taps**: Search is immediately accessible (no tab switch)
- **Better hierarchy**: Saved Words elevated to top level
- **Modern UX**: Floating action pattern (familiar from Material Design)

### Maintainability
- **Simpler navigation**: Direct view switching vs TabView coordination
- **Less state**: No need to track selectedTab across multiple views
- **Cleaner code**: Remove DictionaryTabView complexity

---

## Testing Checklist

### Functional Tests
- [ ] FAB appears in bottom-right corner (all views)
- [ ] Menu expands/collapses with smooth animation
- [ ] All 5 menu items appear correctly
- [ ] Practice badge shows correct count
- [ ] Tapping menu item navigates to correct view
- [ ] Tapping outside menu closes it
- [ ] SearchView is default view on app launch
- [ ] Back navigation works correctly
- [ ] Saved words view loads data correctly

### Visual Tests
- [ ] Menu items properly aligned
- [ ] Shadow/elevation looks correct
- [ ] Badge positioning on Practice item
- [ ] Overlay dimming when expanded
- [ ] Animations smooth (60fps)
- [ ] No layout jumps or glitches

### Edge Cases
- [ ] Multiple rapid taps on FAB (no animation glitch)
- [ ] Rotate device while menu open (menu adjusts)
- [ ] Low memory warning (state preserved)
- [ ] Notification arrives while menu open (menu closes)
- [ ] VoiceOver enabled (all controls accessible)

### Integration Tests
- [ ] Analytics tracking still works (navigation events)
- [ ] Notification navigation to Practice still works
- [ ] Practice count refresh still works
- [ ] Settings changes reflected correctly
- [ ] Deep linking still works (if applicable)

---

## Risks & Mitigation

### Risk 1: User Confusion (Navigation Change)
**Mitigation**:
- Add onboarding tooltip: "Menu moved here"
- First launch animation to draw attention to FAB

### Risk 2: Accidental Menu Opens
**Mitigation**:
- Require deliberate tap (not swipe)
- Add slight delay before expanding

### Risk 3: Menu Obscures Content
**Mitigation**:
- Use semi-transparent overlay
- Ensure FAB doesn't cover critical content in any view

### Risk 4: Performance (Animation Lag)
**Mitigation**:
- Use GeometryReader sparingly
- Preload menu items
- Test on older devices (iPhone 8, etc.)

---

## Migration Plan

### Step 1: Create Components (Day 1)
- Build FloatingActionMenu.swift
- Build SavedWordsView.swift
- Test in isolation (SwiftUI Previews)

### Step 2: Integrate (Day 1)
- Modify ContentView.swift
- Remove DictionaryTabView
- Test navigation flow

### Step 3: Polish (Day 2)
- Add animations
- Add haptic feedback
- Add accessibility support

### Step 4: Test (Day 2)
- Run through testing checklist
- Fix any bugs
- Performance testing on device

### Step 5: Deploy
- Internal testing (TestFlight)
- Monitor analytics for user behavior changes
- Gather feedback

---

## Analytics to Monitor

**Navigation Events**:
- `fab_opened` - Count of menu opens
- `fab_item_tapped` - Which items are most used
- `search_view_time` - Time spent in search (should increase)
- `saved_words_accessed` - Compare with old "Saved" tab usage

**User Behavior**:
- Session length (expect slight increase due to better UX)
- Bounce rate (expect slight decrease)
- Feature discovery (more users finding Saved Words)

---

## Future Enhancements

1. **Customizable Menu**: Let users reorder menu items
2. **Recent Items**: Show last 2 accessed views as quick actions
3. **Contextual FAB**: Different menu items based on current view
4. **Gestures**: Swipe up on FAB to auto-expand
5. **Themes**: Match FAB color to user's theme preference

---

## References

- [Material Design: Floating Action Button](https://material.io/components/buttons-floating-action-button)
- [Apple HIG: Navigation](https://developer.apple.com/design/human-interface-guidelines/navigation)
- [SwiftUI Animation Best Practices](https://developer.apple.com/documentation/swiftui/animation)

---

**Status**: ✅ Design Complete - Ready for Implementation
**Estimated Effort**: 2 days (1 day dev + 1 day test/polish)
