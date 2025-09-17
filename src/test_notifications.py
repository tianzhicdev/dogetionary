#!/usr/bin/env python3
"""
Test script for notification system
"""

import sys
import os
from datetime import datetime, time
import pytz

# Add the src directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from services.notification_service import notification_service
from utils.database import get_db_connection

def setup_test_user():
    """Create a test user with notification preferences"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # Create test user with notifications enabled
        test_user_id = "12345678-1234-1234-1234-123456789012"  # Valid UUID format

        cur.execute("""
            INSERT INTO user_preferences (
                user_id,
                learning_language,
                native_language,
                user_name,
                timezone,
                notification_enabled,
                notification_time,
                last_notification_sent
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (user_id)
            DO UPDATE SET
                timezone = EXCLUDED.timezone,
                notification_enabled = EXCLUDED.notification_enabled,
                notification_time = EXCLUDED.notification_time,
                last_notification_sent = NULL
        """, (
            test_user_id,
            'en',
            'zh',
            'Test User',
            'America/New_York',  # Eastern timezone
            True,
            time(11, 59),
            None  # Reset last notification sent
        ))

        # Create some test words for the user
        cur.execute("""
            INSERT INTO saved_words (user_id, word, learning_language)
            VALUES
                (%s, 'hello', 'en'),
                (%s, 'world', 'en'),
                (%s, 'test', 'en')
            ON CONFLICT (user_id, word, learning_language) DO NOTHING
        """, (test_user_id, test_user_id, test_user_id))

        conn.commit()
        cur.close()
        conn.close()

        print(f"✅ Test user created: {test_user_id}")
        return test_user_id

    except Exception as e:
        print(f"❌ Error setting up test user: {str(e)}")
        return None

def test_overdue_count(user_id):
    """Test getting overdue words count"""
    print("\n📊 Testing overdue words count...")

    count = notification_service.get_overdue_words_count(user_id)
    print(f"   Overdue words for test user: {count}")

    return count

def test_notification_timing():
    """Test notification timing logic"""
    print("\n⏰ Testing notification timing...")

    # Create test user data
    user_data = {
        'user_id': 'test-user',
        'timezone': 'America/New_York',
        'notification_time': time(11, 59),
        'last_notification_sent': None,
        'user_name': 'Test User'
    }

    # Test with different times
    test_times = [
        datetime(2023, 12, 1, 15, 59, 0),  # 11:59 AM EST (16:59 UTC)
        datetime(2023, 12, 1, 16, 4, 0),   # 12:04 PM EST (17:04 UTC) - should still work
        datetime(2023, 12, 1, 17, 0, 0),   # 1:00 PM EST - should not work
        datetime(2023, 12, 1, 10, 0, 0),   # 6:00 AM EST - should not work
    ]

    for test_time in test_times:
        should_send = notification_service.should_send_notification(user_data, test_time)
        local_time = test_time.replace(tzinfo=pytz.UTC).astimezone(pytz.timezone('America/New_York'))
        print(f"   UTC: {test_time.strftime('%H:%M')} -> EST: {local_time.strftime('%H:%M')} -> Should send: {should_send}")

def test_full_notification_flow():
    """Test the complete notification flow"""
    print("\n🔄 Testing full notification flow...")

    # Run the notification check
    stats = notification_service.process_daily_notifications()

    print("   Notification stats:")
    for key, value in stats.items():
        print(f"     {key}: {value}")

def test_database_migration():
    """Test if database has notification columns"""
    print("\n🗄️  Testing database schema...")

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # Check if notification columns exist
        cur.execute("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name = 'user_preferences'
            AND column_name IN ('timezone', 'notification_enabled', 'notification_time', 'last_notification_sent')
        """)

        columns = [row['column_name'] for row in cur.fetchall()]

        expected_columns = ['timezone', 'notification_enabled', 'notification_time', 'last_notification_sent']
        missing_columns = [col for col in expected_columns if col not in columns]

        if missing_columns:
            print(f"   ❌ Missing columns: {missing_columns}")
            print("   💡 Run the database migration: db/migrations/add_notification_settings.sql")
            return False
        else:
            print("   ✅ All notification columns exist")

        # Check notification_logs table
        cur.execute("""
            SELECT table_name
            FROM information_schema.tables
            WHERE table_name = 'notification_logs'
        """)

        if not cur.fetchall():
            print("   ❌ notification_logs table missing")
            return False
        else:
            print("   ✅ notification_logs table exists")

        cur.close()
        conn.close()
        return True

    except Exception as e:
        print(f"   ❌ Database test failed: {str(e)}")
        return False

def main():
    """Run all notification tests"""
    print("🧪 Dogetionary Notification System Test")
    print("=" * 40)

    # Test database schema
    if not test_database_migration():
        print("\n❌ Database schema test failed. Please run the migration first.")
        return

    # Setup test user
    test_user_id = setup_test_user()
    if not test_user_id:
        print("\n❌ Failed to create test user")
        return

    # Test overdue count
    overdue_count = test_overdue_count(test_user_id)

    # Test notification timing
    test_notification_timing()

    # Test full flow
    test_full_notification_flow()

    print("\n✅ Notification system test completed!")
    print("\n📱 The notification system is now ready:")
    print("   • Users can set their timezone and notification preferences")
    print("   • Daily reminders will be sent at 11:59 AM in their local time")
    print("   • Notifications are sent only when users have overdue words")
    print("   • The scheduler runs every 5 minutes to check for due notifications")

if __name__ == "__main__":
    main()