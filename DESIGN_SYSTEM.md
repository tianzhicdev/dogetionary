# Design System - Centralized Styling

## Principle

All cosmetic properties (colors, fonts, spacing, borders, shadows, etc.) must be centralized in `AppTheme` using **semantic naming** based on **what the property is for** and **which component it belongs to**.

### ❌ Bad (Hardcoded)
```swift
Text(user.name)
    .font(.system(size: 16, weight: .semibold))
    .foregroundColor(.primary)
    .padding(.horizontal, 12)
```

### ✅ Good (Centralized)
```swift
Text(user.name)
    .font(AppTheme.leaderboard.userName.font)
    .foregroundColor(AppTheme.leaderboard.userName.textColor)
    .padding(.horizontal, AppTheme.leaderboard.userName.paddingHorizontal)
```

## Structure

### Component-Based Namespace
```swift
struct AppTheme {
    struct ComponentName {
        struct elementName {
            static let font = Font.system(size: 16, weight: .semibold)
            static let textColor = Color.primary
            static let cornerRadius: CGFloat = 12
            static let padding: CGFloat = 16
        }
    }
}
```

### Usage
```swift
// Access via: AppTheme.<component>.<element>.<property>
AppTheme.leaderboard.userName.font
AppTheme.review.questionCard.cornerRadius
AppTheme.settings.sectionHeader.font
```

## Covered Properties

All cosmetic properties should be centralized:

- **Typography**: font size, weight, design
- **Colors**: foreground, background, tint, stroke, fill
- **Spacing**: padding, margins, spacing between elements
- **Borders**: width, color, style
- **Corners**: radius for all elements
- **Shadows**: color, radius, offset
- **Sizes**: frame widths/heights, icon sizes
- **Opacity**: alpha/transparency values
- **Animation**: durations, curves

## Migration Steps

### 1. Audit Component
Identify all hardcoded styling properties in the component:
- Scan for `.font()`, `.foregroundColor()`, `.padding()`, `.cornerRadius()`, etc.
- Document each property with its current value and location

### 2. Design AppTheme Namespace
Create logical grouping for the component:
```swift
struct ComponentName {
    struct element1 {
        static let font = ...
        static let textColor = ...
    }
    struct element2 {
        static let cornerRadius = ...
    }
}
```

### 3. Add to ThemeConstants.swift
Add the namespace structure to `AppTheme` in ThemeConstants.swift

### 4. Replace in Component
Replace all hardcoded values with `AppTheme.<component>.<element>.<property>`

### 5. Test & Verify
- Build app
- Visual check (ensure no regressions)
- Verify all properties are centralized

## Naming Conventions

### Components (PascalCase)
- `Leaderboard`, `Review`, `Settings`, `Search`, `SavedWords`, `Schedule`

### Elements (camelCase)
- `userName`, `scoreText`, `rankBadge`, `sectionHeader`, `optionButton`

### Properties (camelCase)
- `font`, `textColor`, `backgroundColor`, `cornerRadius`, `padding`, `shadowRadius`

### Special Cases
- For "current user" vs "other users": `currentUserName`, `userName`
- For states: `selectedTextColor`, `disabledTextColor`
- For sub-elements: `button.primary`, `button.secondary`

## Benefits

1. **Consistency**: All components use the same styling system
2. **Maintainability**: Change theme in one place
3. **Scalability**: Easy to add new components
4. **Clarity**: Semantic names explain purpose
5. **Type Safety**: Compiler catches typos
6. **Performance**: Static constants, no runtime overhead

## Examples

### Leaderboard
```swift
struct Leaderboard {
    struct userName {
        static let font = Font.system(size: 16, weight: .semibold)
        static let textColor = Color.primary
    }
    struct currentUserRow {
        static let backgroundColor = Color.blue.opacity(0.1)
    }
    struct rankBadge {
        static let cornerRadius: CGFloat = 2
    }
}
```

### Settings
```swift
struct Settings {
    struct sectionHeader {
        static let font = Font.headline
        static let textColor = LinearGradient(...)
    }
    struct textField {
        static let cornerRadius: CGFloat = 8
        static let padding: CGFloat = 12
    }
}
```

## Migration Status

- [x] LeaderboardView
- [x] SettingsView
- [ ] ReviewView
- [ ] SearchView
- [ ] SavedWordsView
- [ ] ScheduleView
- [ ] PronunciationPracticeView
- [ ] Shared Components

## Notes

- Keep existing generic constants (e.g., `AppTheme.cornerRadiusBase`) for shared values
- Component-specific overrides take precedence
- Document any deviations from standard patterns
- Always verify build after migration
