# Notifications Architecture

## Overview

Dogetionary uses **iOS local notifications only**. Server-side push notifications have been removed as they were non-functional and unnecessary.

## How Notifications Work

### User Experience
1. Users open Settings in the iOS app
2. They set their preferred notification time using a time picker
3. The app schedules daily notifications at that time
4. Notifications fire locally on the device at the chosen time

### Technical Implementation

**iOS Side** (Working):
- **Location**: `ios/dogetionary/dogetionary/Core/Managers/NotificationManager.swift`
- **Storage**: User's preferred time stored in `UserDefaults` with key `DogetionaryReminderTime`
- **Scheduling**: Uses `UNCalendarNotificationTrigger` to schedule repeating daily notifications
- **Content**: Dynamically fetches overdue word count from API and updates notification body
- **Permissions**: Requests notification permissions on first use

**Server Side** (Removed):
- ~~notification_service.py~~ - DELETED (had broken SQL queries, hardcoded times)
- `scheduler_service.py` - Simplified to empty skeleton (for future scheduled tasks if needed)
- Database still has `daily_reminder_time` column for potential future use, but it's not actively used

## Code Flow

```
User sets time in Settings
    ↓
Stored in UserDefaults (reminderTime)
    ↓
NotificationManager.scheduleDailyNotification(at: reminderTime)
    ↓
iOS schedules local notification via UNUserNotificationCenter
    ↓
Notification fires daily at user's chosen time
    ↓
App fetches overdue count and displays in notification
```

## Why Local Notifications Only?

1. **Reliability**: iOS local notifications are more reliable than server-push
2. **Privacy**: No need to send device tokens to server
3. **Simplicity**: Less code to maintain, no server infrastructure needed
4. **Cost**: No push notification service fees
5. **Offline**: Works even when user has no internet connection at notification time

## Database Schema

The `user_preferences` table still contains notification-related columns that may be useful for analytics:

```sql
push_notifications_enabled BOOLEAN DEFAULT TRUE
daily_reminder_time TIME DEFAULT '09:00:00'
timezone VARCHAR(50) DEFAULT 'UTC'
```

These columns are not actively used by the notification system but are kept for:
- Future analytics on user notification preferences
- Potential future server-side features
- Migration data if we ever add push notifications

## Files Removed

- `src/services/notification_service.py` - Deleted entirely (broken SQL, hardcoded times)

## Files Modified

- `src/services/scheduler_service.py` - Removed notification code, kept as skeleton
  - `_run_notification_check()` method removed
  - `run_notification_check_now()` method removed
  - Import of `notification_service` removed

## Testing

To verify notifications work:

1. Open iOS app
2. Go to Settings
3. Set notification time to 1 minute from now
4. Close app
5. Wait for notification to appear

## Future Considerations

If push notifications are needed in the future:
1. Use Apple Push Notification Service (APNS) directly
2. Store device tokens in database
3. Implement proper notification service with retry logic
4. Respect user's `daily_reminder_time` preference from database
5. Handle timezone conversions properly

---

**Last Updated**: December 14, 2025
**Status**: ✅ Working (iOS local notifications only)
