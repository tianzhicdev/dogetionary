# Onboarding Journey Redesign - Research & Implementation Plan

## Executive Summary

**Goal**: Simplify onboarding by removing learning language selection and adding a "daily time commitment" slider.

**Proposed Changes**:
1. **Remove**: Learning language selection (hardcode to English)
2. **Update**: Page 2 wording from "Are you studying for a test?" → "Choose a program" (default to Demo)
3. **Add**: Page 3 - "How much time can you commit everyday?" (10 mins → 8 hours slider)
4. **Keep**: Pages for native language, name, spaced repetition declaration, and logo

**Impact**: Medium - requires database schema change, iOS UI updates, and backend validation updates.

---

## Current Onboarding Flow Analysis

### Current Pages (8 pages total with test selected):

**Page 0**: Learning Language Selection
- Title: "WHAT LANGUAGE ARE YOU LEARNING?"
- UI: Wheel picker with all available languages
- Default: "en" (English)
- Lottie animation: "globe2"
- **Status**: 🔴 REMOVE

**Page 1**: Native Language Selection
- Title: "WHAT IS YOUR NATIVE LANGUAGE?"
- UI: Wheel picker (excludes learning language)
- Default: "fr" (French)
- **Status**: ✅ KEEP (will become Page 0)

**Page 2**: Test Prep Selection (English only)
- Title: "ARE YOU STUDYING FOR A TEST?"
- UI: Wheel picker with test types + "NONE"
- Options: TOEFL_BEGINNER, TOEFL_INTERMEDIATE, TOEFL_ADVANCED, IELTS_*, DEMO, etc.
- Shows word counts fetched from backend
- **Status**: ✅ KEEP (becomes Page 1)
- **Changes**:
  - New title: "CHOOSE A PROGRAM"
  - Default selection: DEMO (instead of nil/NONE)

**Page 3**: Study Duration (if test selected)
- Title: "HOW LONG DO YOU WANT TO MASTER THE VOCABULARY?"
- UI: Slider 1-365 days
- Default: 30 days
- Shows: "~X NEW WORDS PER DAY" calculation
- **Status**: 🔄 REPLACE
- **New Page 3**: Time commitment slider

**Page 4**: Username
- Title: "GIVE YOURSELF A COOL NAME"
- UI: TextField with random default name
- **Status**: ✅ KEEP (becomes Page 3)

**Page 5**: Schedule Preview (if test selected)
- Shows ScheduleView embedded
- **Status**: 🤔 REVIEW (still useful with time commitment?)

**Page 6**: Declaration Page
- Title: "SPACED REPITITION" (typo: should be REPETITION)
- Shows declaration image + explanation
- **Status**: ✅ KEEP (becomes Page 4 or 5)

**Page 7**: Motivation/Logo Page
- Shows app logo
- Text: "This won't be easy. But if you persist, you will achieve mastery."
- Button: "START"
- **Status**: ✅ KEEP (final page)

---

## New Onboarding Flow (Proposed)

### New Pages (6-7 pages):

**Page 0**: Native Language ← (was Page 1)
- Title: "WHAT IS YOUR NATIVE LANGUAGE?"
- UI: Wheel picker
- Lottie: "globe2" (can reuse the globe animation)
- Learning language: Hardcoded to "en" (English)

**Page 1**: Choose Program ← (was Page 2)
- Title: "CHOOSE A PROGRAM" (NEW WORDING)
- UI: Wheel picker with test types
- **Default**: DEMO (CHANGED)
- Options: DEMO, TOEFL_BEGINNER/INTERMEDIATE/ADVANCED, IELTS_*, BUSINESS_ENGLISH, EVERYDAY_ENGLISH
- Shows word counts

**Page 2**: Daily Time Commitment ← (NEW PAGE)
- Title: "HOW MUCH TIME CAN YOU COMMIT EVERYDAY?"
- UI: Slider from 10 minutes → 8 hours (480 minutes)
- Display: "X HOURS Y MINUTES" or "X MINUTES"
- Default: 30 minutes
- **Note**: This replaces the study duration page

**Page 3**: Username ← (was Page 4)
- Title: "GIVE YOURSELF A COOL NAME"
- No changes

**Page 4**: Spaced Repetition Declaration ← (was Page 6)
- Title: "SPACED REPETITION" (fix typo)
- No changes

**Page 5**: Logo/Motivation ← (was Page 7)
- Final page
- Button: "START"
- No changes

---

## Database Changes Required

### New Column: `daily_time_commitment_minutes`

**Location**: `user_preferences` table

**SQL Migration**:
```sql
ALTER TABLE user_preferences
ADD COLUMN daily_time_commitment_minutes INTEGER DEFAULT 30;
```

**Details**:
- Type: `INTEGER`
- Default: `30` (30 minutes)
- Range: `10` to `480` (10 minutes to 8 hours)
- Nullable: `NO` (has default)

**Rationale**:
- Stores user's daily study time commitment in minutes
- Used for:
  - Scheduling daily word additions
  - Calculating realistic study plans
  - Personalizing notifications ("You have 30 mins committed, 5 words waiting")
  - Future: AI-powered pacing adjustments

### Modified Column: `learning_language`

**Current**: User-selectable via onboarding/settings
**New**: Hardcoded to `'en'` in onboarding (still changeable in settings for future flexibility)

**No schema change needed** - just application logic change.

### Database Schema After Changes:

```sql
CREATE TABLE user_preferences (
    user_id UUID PRIMARY KEY,
    learning_language VARCHAR(10) DEFAULT 'en',  -- Still user-changeable in settings
    native_language VARCHAR(10) DEFAULT 'zh',
    user_name VARCHAR(255),
    user_motto TEXT,

    -- NEW: Time commitment
    daily_time_commitment_minutes INTEGER DEFAULT 30,  -- 🆕 NEW COLUMN

    -- Test preparation settings (existing)
    toefl_beginner_enabled BOOLEAN DEFAULT FALSE,
    toefl_intermediate_enabled BOOLEAN DEFAULT FALSE,
    toefl_advanced_enabled BOOLEAN DEFAULT FALSE,
    ielts_beginner_enabled BOOLEAN DEFAULT FALSE,
    ielts_intermediate_enabled BOOLEAN DEFAULT FALSE,
    ielts_advanced_enabled BOOLEAN DEFAULT FALSE,
    demo_enabled BOOLEAN DEFAULT FALSE,
    business_english_enabled BOOLEAN DEFAULT FALSE,
    everyday_english_enabled BOOLEAN DEFAULT FALSE,

    -- Target days (existing)
    toefl_beginner_target_days INTEGER DEFAULT 30,
    toefl_intermediate_target_days INTEGER DEFAULT 30,
    toefl_advanced_target_days INTEGER DEFAULT 30,
    ielts_beginner_target_days INTEGER DEFAULT 30,
    ielts_intermediate_target_days INTEGER DEFAULT 30,
    ielts_advanced_target_days INTEGER DEFAULT 30,
    target_end_date DATE,

    -- Notification settings (existing)
    push_notifications_enabled BOOLEAN DEFAULT TRUE,
    email_notifications_enabled BOOLEAN DEFAULT FALSE,
    daily_reminder_time TIME DEFAULT '09:00:00',
    weekly_report_enabled BOOLEAN DEFAULT TRUE,
    streak_notifications_enabled BOOLEAN DEFAULT TRUE,
    timezone VARCHAR(50) DEFAULT 'UTC',

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

---

## iOS Changes Required

### Files to Modify: 3 files

#### 1. `OnboardingView.swift` (Major changes)

**Current state variables to modify**:
```swift
// REMOVE - hardcode to "en"
@State private var selectedLearningLanguage = "en"

// KEEP
@State private var selectedNativeLanguage = "fr"

// UPDATE DEFAULT - currently nil, should default to DEMO
@State private var selectedTestType: TestType? = nil

// REMOVE - replace with time commitment
@State private var selectedStudyDuration: Double = 30

// ADD - new state for time commitment
@State private var dailyTimeCommitmentMinutes: Double = 30  // 🆕 NEW
```

**Changes needed**:

**A. Remove Page 0 (Learning Language)**
```swift
// DELETE lines 77-85:
languageSelectionPage(
    title: "WHAT LANGUAGE ARE YOU LEARNING?",
    description: "CHOOSE THE LANGUAGE YOU WANT TO LEARN AND IMPROVE",
    lottieAnimation: "globe2",
    selectedLanguage: $selectedLearningLanguage,
    excludeLanguage: selectedNativeLanguage
)
.tag(0)
```

**B. Update Page 1 (Native Language) - becomes Page 0**
```swift
// MODIFY to add Lottie animation:
languageSelectionPage(
    title: "WHAT IS YOUR NATIVE LANGUAGE?",
    description: "CHOOSE YOUR NATIVE LANGUAGE FOR TRANSLATIONS",
    lottieAnimation: "globe2",  // 🆕 ADD THIS
    selectedLanguage: $selectedNativeLanguage,
    excludeLanguage: "en"  // 🆕 CHANGE: always exclude English
)
.tag(0)  // 🆕 CHANGE: was tag(1), now tag(0)
```

**C. Update Page 2 (Test Prep) - becomes Page 1**
```swift
// MODIFY title:
Text("CHOOSE A PROGRAM")  // 🆕 CHANGE from "ARE YOU STUDYING FOR A TEST?"

// DEFAULT to DEMO:
@State private var selectedTestType: TestType? = .demo  // 🆕 CHANGE from nil

// Update tag:
.tag(1)  // 🆕 CHANGE from tag(2)
```

**D. Replace Page 3 (Study Duration) with Time Commitment**
```swift
// DELETE studyDurationPage entirely

// ADD NEW timeCommitmentPage:
private var timeCommitmentPage: some View {
    VStack(spacing: 24) {
        VStack(spacing: 20) {
            Text("HOW MUCH TIME CAN YOU COMMIT EVERYDAY?")
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.gradient1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)

        Spacer()

        VStack(spacing: 32) {
            // Time display
            VStack(spacing: 8) {
                if dailyTimeCommitmentMinutes >= 60 {
                    let hours = Int(dailyTimeCommitmentMinutes) / 60
                    let minutes = Int(dailyTimeCommitmentMinutes) % 60
                    HStack(spacing: 8) {
                        Text("\(hours)")
                            .font(.system(size: 80, weight: .bold))
                            .foregroundStyle(AppTheme.gradient1)
                        Text("HR")
                            .font(.title2)
                            .foregroundColor(AppTheme.smallTitleText)
                        if minutes > 0 {
                            Text("\(minutes)")
                                .font(.system(size: 80, weight: .bold))
                                .foregroundStyle(AppTheme.gradient1)
                            Text("MIN")
                                .font(.title2)
                                .foregroundColor(AppTheme.smallTitleText)
                        }
                    }
                } else {
                    Text("\(Int(dailyTimeCommitmentMinutes))")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundStyle(AppTheme.gradient1)
                    Text("MINUTES")
                        .font(.title2)
                        .foregroundColor(AppTheme.smallTitleText)
                }
            }

            // Slider
            VStack(spacing: 8) {
                Slider(value: $dailyTimeCommitmentMinutes, in: 10...480, step: 5)
                    .tint(AppTheme.selectableTint)

                HStack {
                    Text("10 MIN")
                        .font(.caption)
                        .foregroundColor(AppTheme.smallTextColor1)
                    Spacer()
                    Text("8 HRS")
                        .font(.caption)
                        .foregroundColor(AppTheme.smallTextColor1)
                }
            }
            .padding(.horizontal, 24)

            // Optional: Show estimated words per day calculation
            Text("~\(estimatedWordsPerDay) WORDS PER DAY")
                .font(.headline)
                .foregroundColor(AppTheme.smallTitleText)
        }
        .padding(.horizontal, 24)

        Spacer()
    }
}
.tag(2)  // 🆕 NEW PAGE at tag 2

// Helper computed property:
private var estimatedWordsPerDay: Int {
    // Assume ~2 minutes per word (definition + practice)
    return max(1, Int(dailyTimeCommitmentMinutes) / 2)
}
```

**E. Update page indices**:
```swift
private var usernamePageIndex: Int {
    return 3  // 🆕 CHANGE: was dynamic, now always 3
}

private var declarationPageIndex: Int {
    return 4  // 🆕 CHANGE: was dynamic, now always 4
}

private var searchPageIndex: Int {
    return 5  // 🆕 CHANGE: was dynamic, now always 5
}

private var totalPages: Int {
    return 6  // 🆕 CHANGE: was dynamic (5-8), now always 6
}

private var showDurationPage: Bool {
    return true  // 🆕 CHANGE: always show time commitment page
}
```

**F. Update submitOnboarding()**:
```swift
private func submitOnboarding() {
    isSubmitting = true

    let trimmedName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
    let userId = userManager.getUserID()

    DictionaryService.shared.updateUserPreferences(
        userID: userId,
        learningLanguage: "en",  // 🆕 HARDCODED to English
        nativeLanguage: selectedNativeLanguage,
        userName: trimmedName,
        userMotto: "",
        testPrep: selectedTestType?.rawValue ?? "DEMO",  // 🆕 CHANGE: default to DEMO
        studyDurationDays: Int(selectedStudyDuration),  // Keep for backward compatibility
        dailyTimeCommitmentMinutes: Int(dailyTimeCommitmentMinutes)  // 🆕 NEW PARAMETER
    ) { result in
        // ... rest of existing code
    }
}
```

**G. Remove Schedule Preview Page**:
```swift
// DELETE schedulePreviewPage entirely
// Or keep it but show it after declaration page
```

#### 2. `SettingsView.swift` (Minor changes)

**A. Hide/Disable Learning Language Picker**:

**Option 1: Remove entirely** (recommended)
```swift
@ViewBuilder
private var languagePreferencesSection: some View {
    Section(header:
        HStack {
            Text("LANGUAGE PREFERENCES")
            .foregroundStyle(AppTheme.gradient1)
                .fontWeight(.semibold)
        }
    ) {
        VStack(alignment: .leading, spacing: 12) {
            // DELETE Learning Language Picker (lines 199-215)

            // KEEP Native Language Picker (lines 217-233)
            HStack {
                Spacer()
                Picker("NATIVE LANGUAGE", selection: nativeLanguageBinding) {
                    ForEach(LanguageConstants.availableLanguages, id: \.0) { code, name in
                        HStack {
                            Text(name.uppercased())
                            Text("(\(code.uppercased()))")
                                .font(.caption2)
                                .foregroundColor(AppTheme.smallTitleText)
                        }
                        .tag(code)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .tint(AppTheme.selectableTint)
                .foregroundColor(AppTheme.smallTitleText)
            }

            // 🆕 ADD: Time Commitment Slider
            VStack(alignment: .leading, spacing: 8) {
                Text("DAILY TIME COMMITMENT")
                    .font(.caption)
                    .foregroundColor(AppTheme.smallTextColor1)

                HStack(spacing: 8) {
                    if userManager.dailyTimeCommitmentMinutes >= 60 {
                        let hours = userManager.dailyTimeCommitmentMinutes / 60
                        let minutes = userManager.dailyTimeCommitmentMinutes % 60
                        Text("\(hours) HR \(minutes > 0 ? "\(minutes) MIN" : "")")
                    } else {
                        Text("\(userManager.dailyTimeCommitmentMinutes) MIN")
                    }
                }
                .font(.body)
                .foregroundColor(AppTheme.selectableTint)

                Slider(value: Binding(
                    get: { Double(userManager.dailyTimeCommitmentMinutes) },
                    set: { userManager.dailyTimeCommitmentMinutes = Int($0) }
                ), in: 10...480, step: 5)
                .tint(AppTheme.selectableTint)

                HStack {
                    Text("10 MIN")
                        .font(.caption2)
                        .foregroundColor(AppTheme.smallTextColor1)
                    Spacer()
                    Text("8 HRS")
                        .font(.caption2)
                        .foregroundColor(AppTheme.smallTextColor1)
                }
            }
        }
    }.listRowBackground(Color.clear)
}
```

**Option 2: Disable (show but grayed out)**
```swift
// Wrap the Learning Language Picker:
HStack {
    Spacer()
    Picker("LEARNING LANGUAGE", selection: .constant("en")) {
        Text("ENGLISH (EN)")
            .tag("en")
    }
    .pickerStyle(MenuPickerStyle())
    .tint(AppTheme.selectableTint.opacity(0.5))
    .foregroundColor(AppTheme.smallTextColor1)
    .disabled(true)  // 🆕 DISABLED
}

Text("LEARNING LANGUAGE IS CURRENTLY LOCKED TO ENGLISH")
    .font(.caption2)
    .foregroundColor(AppTheme.smallTextColor1)
```

**Recommendation**: Option 1 (complete removal) is cleaner.

#### 3. `UserManager.swift` (Add new property)

**Location**: `ios/dogetionary/dogetionary/Core/Managers/UserManager.swift`

**Add new @AppStorage property**:
```swift
@AppStorage("dailyTimeCommitmentMinutes") var dailyTimeCommitmentMinutes: Int = 30  // 🆕 NEW
```

**Update sync methods**:
```swift
func syncPreferencesFromServer() {
    // ... existing code ...

    // 🆕 ADD:
    if let timeCommitment = prefs["daily_time_commitment_minutes"] as? Int {
        self.dailyTimeCommitmentMinutes = timeCommitment
    }
}
```

---

## Backend Changes Required

### Files to Modify: 2 files

#### 1. `src/handlers/users.py`

**A. Update `handle_user_preferences()` POST handler**:

**Add new parameter handling**:
```python
def handle_user_preferences(user_id):
    # ... existing code ...

    elif request.method == 'POST':
        data = request.get_json()
        learning_lang = data.get('learning_language')
        native_lang = data.get('native_language')
        user_name = data.get('user_name', '')
        user_motto = data.get('user_motto', '')
        test_prep = data.get('test_prep')
        study_duration_days = data.get('study_duration_days')
        timezone = data.get('timezone')
        target_end_date = data.get('target_end_date')
        daily_time_commitment_minutes = data.get('daily_time_commitment_minutes')  # 🆕 NEW

        # Validation
        if daily_time_commitment_minutes is not None:
            if not isinstance(daily_time_commitment_minutes, int):
                return jsonify({"error": "daily_time_commitment_minutes must be an integer"}), 400
            if daily_time_commitment_minutes < 10 or daily_time_commitment_minutes > 480:
                return jsonify({"error": "daily_time_commitment_minutes must be between 10 and 480"}), 400

        # ... existing validation code ...

        # Build UPDATE query
        update_fields = []
        update_values = []

        # ... existing fields ...

        # 🆕 ADD:
        if daily_time_commitment_minutes is not None:
            update_fields.append("daily_time_commitment_minutes = %s")
            update_values.append(daily_time_commitment_minutes)

        # ... rest of existing code ...
```

**B. Update `get_user_preferences()` response**:
```python
def get_user_preferences(user_id: str) -> dict:
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT learning_language, native_language, user_name, user_motto,
                   toefl_enabled, ielts_enabled, demo_enabled,
                   toefl_target_days, ielts_target_days, demo_target_days,
                   daily_time_commitment_minutes  -- 🆕 ADD
            FROM user_preferences
            WHERE user_id = %s
        """, (user_id,))

        result = cur.fetchone()
        # ... existing code ...

        return {
            'learning_language': result['learning_language'],
            'native_language': result['native_language'],
            'user_name': result['user_name'] or '',
            'user_motto': result['user_motto'] or '',
            'test_prep': test_prep,
            'study_duration_days': target_days,
            'daily_time_commitment_minutes': result.get('daily_time_commitment_minutes', 30)  # 🆕 ADD
        }
```

#### 2. `src/services/user_service.py` (if exists)

**Update UserPreferences model** (if using a model/schema):
```python
class UserPreferences:
    def __init__(self, ...):
        # ... existing fields ...
        self.daily_time_commitment_minutes = 30  # 🆕 NEW
```

---

## iOS Service Changes Required

### Files to Modify: 2 files

#### 1. `UserPreferencesService.swift`

**Update `updateUserPreferences()` method signature**:
```swift
func updateUserPreferences(
    userID: String,
    learningLanguage: String,
    nativeLanguage: String,
    userName: String,
    userMotto: String,
    testPrep: String? = nil,
    studyDurationDays: Int? = nil,
    dailyTimeCommitmentMinutes: Int? = nil,  // 🆕 NEW PARAMETER
    timezone: String? = nil,
    completion: @escaping (Result<UserPreferences, Error>) -> Void
) {
    // ... existing code ...

    var params: [String: Any] = [
        "learning_language": learningLanguage,
        "native_language": nativeLanguage,
        "user_name": userName,
        "user_motto": userMotto
    ]

    // ... existing parameter handling ...

    // 🆕 ADD:
    if let timeCommitment = dailyTimeCommitmentMinutes {
        params["daily_time_commitment_minutes"] = timeCommitment
    }

    // ... rest of existing code ...
}
```

#### 2. `DictionaryModels.swift`

**Update `UserPreferences` struct**:
```swift
struct UserPreferences: Codable {
    let learningLanguage: String
    let nativeLanguage: String
    let userName: String
    let userMotto: String
    let testPrep: String?
    let studyDurationDays: Int?
    let dailyTimeCommitmentMinutes: Int?  // 🆕 NEW FIELD

    enum CodingKeys: String, CodingKey {
        case learningLanguage = "learning_language"
        case nativeLanguage = "native_language"
        case userName = "user_name"
        case userMotto = "user_motto"
        case testPrep = "test_prep"
        case studyDurationDays = "study_duration_days"
        case dailyTimeCommitmentMinutes = "daily_time_commitment_minutes"  // 🆕 NEW
    }
}
```

---

## Migration Strategy

### Phase 1: Database Migration
```sql
-- Migration file: migrations/009_add_daily_time_commitment.sql

BEGIN;

-- Add new column with default value
ALTER TABLE user_preferences
ADD COLUMN daily_time_commitment_minutes INTEGER DEFAULT 30;

-- Add comment
COMMENT ON COLUMN user_preferences.daily_time_commitment_minutes IS
'Daily study time commitment in minutes (10-480). Used for scheduling and personalization.';

-- Optional: Add check constraint
ALTER TABLE user_preferences
ADD CONSTRAINT check_time_commitment_range
CHECK (daily_time_commitment_minutes >= 10 AND daily_time_commitment_minutes <= 480);

COMMIT;
```

### Phase 2: Backend Updates
1. Update `users.py` to handle new parameter
2. Update validation logic
3. Update API response to include new field
4. Test with Postman/curl

### Phase 3: iOS Updates
1. Update `OnboardingView.swift`:
   - Remove learning language page
   - Add time commitment page
   - Update page indices
   - Update submit logic
2. Update `SettingsView.swift`:
   - Remove learning language picker
   - Add time commitment slider
3. Update `UserManager.swift`:
   - Add new @AppStorage property
4. Update service layer:
   - `UserPreferencesService.swift`
   - `DictionaryModels.swift`
5. Test on simulator and device

### Phase 4: Testing
1. Test onboarding flow (fresh install)
2. Test settings update
3. Test backend API directly
4. Verify database values
5. Test with existing users (migration)

---

## Edge Cases & Considerations

### 1. Existing Users
**Problem**: Existing users have `daily_time_commitment_minutes = NULL` or default 30.
**Solution**: Database migration sets default to 30. Backend returns 30 if NULL.

### 2. Learning Language Still in Database
**Problem**: Users still have different learning languages in DB from before.
**Solution**:
- Don't force-update existing users' learning_language to "en"
- Just hardcode onboarding to "en" for NEW users
- Settings can still show current learning_language (but disabled)
- Future: Keep flexibility to support other languages

### 3. Time Commitment vs Study Duration
**Problem**: We have both `study_duration_days` and `daily_time_commitment_minutes`.
**Solution**:
- **Keep both** - they serve different purposes:
  - `study_duration_days`: How many days until target completion
  - `daily_time_commitment_minutes`: How much time per day
- Use both together for smart scheduling:
  - Example: 30 days × 30 mins/day = 900 minutes total study time
  - Calculate: words_per_day = total_words / (30 days × (30 mins/day ÷ 2 mins/word))

### 4. Schedule Preview Page
**Question**: Should we keep the schedule preview page?
**Recommendation**:
- **Keep it** - but show it AFTER username page
- Update it to show time-based schedule instead of just word counts
- Example: "Mon 9AM-9:30AM: 15 words, Tue 9AM-9:30AM: 15 words"

### 5. Analytics
**Remember to track**:
- Onboarding completion with new flow
- Average time commitment selected
- Correlation between time commitment and retention

---

## API Contract Changes

### POST /v3/user_preferences/:user_id

**Before**:
```json
{
  "learning_language": "en",
  "native_language": "zh",
  "user_name": "Vocab Ninja",
  "user_motto": "Words are power",
  "test_prep": "DEMO",
  "study_duration_days": 30
}
```

**After**:
```json
{
  "learning_language": "en",
  "native_language": "zh",
  "user_name": "Vocab Ninja",
  "user_motto": "Words are power",
  "test_prep": "DEMO",
  "study_duration_days": 30,
  "daily_time_commitment_minutes": 30  // 🆕 NEW FIELD (optional)
}
```

**Backward Compatibility**: ✅ YES
- New field is optional
- Existing API calls without `daily_time_commitment_minutes` still work
- Default value applied if missing

---

## Implementation Checklist

### Database
- [ ] Create migration file `009_add_daily_time_commitment.sql`
- [ ] Test migration on local database
- [ ] Add validation constraint (10-480 range)
- [ ] Update schema documentation

### Backend
- [ ] Update `users.py` POST handler to accept new parameter
- [ ] Add validation (10-480 range, integer type)
- [ ] Update GET response to include new field
- [ ] Update API documentation
- [ ] Test with curl/Postman
- [ ] Write integration tests

### iOS - Models & Services
- [ ] Update `UserPreferences` struct in `DictionaryModels.swift`
- [ ] Update `UserPreferencesService.swift` method signature
- [ ] Update `UserManager.swift` with new @AppStorage property
- [ ] Add sync logic for new field

### iOS - Onboarding
- [ ] Remove Page 0 (learning language)
- [ ] Update Page 0 (native language) with globe animation
- [ ] Update Page 1 (test prep) title and default
- [ ] Create Page 2 (time commitment slider)
- [ ] Update page indices calculation
- [ ] Remove learning language from submit logic
- [ ] Update totalPages count
- [ ] Test all page transitions
- [ ] Fix typo: "REPITITION" → "REPETITION"

### iOS - Settings
- [ ] Remove learning language picker
- [ ] Add time commitment slider to settings
- [ ] Test settings sync with backend
- [ ] Verify existing users can update time commitment

### Testing
- [ ] Test fresh onboarding (new user)
- [ ] Test settings update (existing user)
- [ ] Test backend API directly
- [ ] Verify database values
- [ ] Test edge cases (min/max values)
- [ ] Test backward compatibility (old iOS → new backend)

---

## Future Enhancements (Post-Implementation)

### Smart Scheduling Based on Time Commitment
- Use `daily_time_commitment_minutes` to calculate optimal word batches
- Example: 30 mins/day ÷ 2 mins/word = 15 words/day
- Adjust batch sizes dynamically

### Adaptive Learning
- Track actual time spent vs committed time
- Suggest adjustments: "You committed 30 mins but average 45 mins. Update?"
- Gamification: "Streak: 7 days of meeting your time commitment!"

### Notification Personalization
- "You have 30 minutes committed today. 12 words are waiting!"
- "Quick session? You can finish 5 words in 10 minutes."

### Analytics Dashboard
- Show user: "You committed 30 mins/day, spent 28 mins average"
- "At your current pace, you'll master vocabulary in 35 days (vs 30 target)"

---

## Summary

### Changes Required:
1. **Database**: Add `daily_time_commitment_minutes` column (INTEGER, 10-480)
2. **Backend**: Update user preferences endpoint to handle new field
3. **iOS Onboarding**:
   - Remove learning language page
   - Hardcode learning language to "en"
   - Add time commitment slider page (10 mins - 8 hours)
   - Update test prep default to DEMO
   - Update wording
4. **iOS Settings**:
   - Remove/disable learning language picker
   - Add time commitment slider

### Risk Level: **MEDIUM**
- Database schema change (low risk with default value)
- iOS UI changes (medium complexity)
- Backward compatible API changes (low risk)

### Estimated Effort:
- **Database**: 30 minutes (migration + testing)
- **Backend**: 1-2 hours (API updates + testing)
- **iOS**: 3-4 hours (UI changes + testing)
- **Total**: ~5-7 hours

### Benefits:
- ✅ Simpler onboarding (one less page to confuse users)
- ✅ More actionable data (time commitment > abstract "days")
- ✅ Better personalization opportunities
- ✅ Default to DEMO program (easier first experience)

---

## Next Steps

1. **Get approval** on proposed changes
2. **Create database migration** file
3. **Update backend** (users.py + validation)
4. **Update iOS** (onboarding + settings)
5. **Test thoroughly** (especially existing users)
6. **Deploy** (backend first, then iOS)
7. **Monitor** analytics for onboarding completion rates

All changes maintain backward compatibility and provide graceful defaults for existing users. ✅
