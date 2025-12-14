"""
Notification Service Module - Handles daily review reminders and notifications
"""

import logging
import pytz
from datetime import datetime, time, timedelta
from typing import List, Dict, Optional
from utils.database import get_db_connection

logger = logging.getLogger(__name__)

class NotificationService:
    """Service for managing user notifications and daily reminders"""

    def __init__(self):
        self.logger = logger

    def get_users_for_notification(self, target_time: time = time(11, 59)) -> List[Dict]:
        """
        Get users who should receive notifications at the specified time in their local timezone
        """
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            # Get all users with notification enabled
            cur.execute("""
                SELECT
                    up.user_id,
                    up.timezone,
                    up.notification_time,
                    up.last_notification_sent,
                    up.user_name
                FROM user_preferences up
                WHERE up.notification_enabled = true
                AND up.notification_time = %s
            """, (target_time,))

            users = []
            for row in cur.fetchall():
                user_data = {
                    'user_id': row['user_id'],
                    'timezone': row['timezone'],
                    'notification_time': row['notification_time'],
                    'last_notification_sent': row['last_notification_sent'],
                    'user_name': row['user_name'] or 'User'
                }
                users.append(user_data)

            cur.close()
            conn.close()

            return users

        except Exception as e:
            self.logger.error(f"Error getting users for notification: {str(e)}", exc_info=True)
            return []

    def get_overdue_words_count(self, user_id: str) -> int:
        """Get count of overdue words for a user"""
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            # Use the existing logic to get due words count
            # This is a simplified version - you might want to import from your existing service
            cur.execute("""
                WITH word_reviews AS (
                    SELECT
                        sw.id,
                        sw.word,
                        sw.created_at,
                        COALESCE(
                            ARRAY_AGG(
                                CASE WHEN r.response THEN r.reviewed_at END
                                ORDER BY r.reviewed_at
                            ) FILTER (WHERE r.response),
                            ARRAY[]::timestamp[]
                        ) as success_dates,
                        COALESCE(
                            MAX(CASE WHEN NOT r.response THEN r.reviewed_at END),
                            sw.created_at
                        ) as last_failure_date
                    FROM saved_words sw
                    LEFT JOIN reviews r ON sw.id = r.word_id
                    WHERE sw.user_id = %s
                    GROUP BY sw.id, sw.word, sw.created_at
                )
                SELECT COUNT(*) as due_count
                FROM word_reviews wr
                WHERE (
                    -- Case 1: Never reviewed successfully (only creation date)
                    (array_length(wr.success_dates, 1) IS NULL AND wr.created_at <= NOW() - INTERVAL '1 day')
                    OR
                    -- Case 2: Has successful reviews - calculate next review date using Fibonacci
                    (array_length(wr.success_dates, 1) > 0 AND
                     wr.success_dates[array_length(wr.success_dates, 1)] +
                     CASE array_length(wr.success_dates, 1)
                         WHEN 1 THEN INTERVAL '5 days'
                         WHEN 2 THEN INTERVAL '8 days'
                         WHEN 3 THEN INTERVAL '13 days'
                         WHEN 4 THEN INTERVAL '21 days'
                         WHEN 5 THEN INTERVAL '34 days'
                         WHEN 6 THEN INTERVAL '55 days'
                         ELSE INTERVAL '89 days'
                     END <= NOW())
                )
            """, (user_id,))

            result = cur.fetchone()
            count = result['due_count'] if result else 0

            cur.close()
            conn.close()

            return count

        except Exception as e:
            self.logger.error(f"Error getting overdue words count for user {user_id}: {str(e)}", exc_info=True)
            return 0

    def should_send_notification(self, user_data: Dict, current_utc: datetime) -> bool:
        """
        Check if we should send notification to user based on their timezone and last notification
        """
        try:
            user_timezone = pytz.timezone(user_data['timezone'])
            user_local_time = current_utc.replace(tzinfo=pytz.UTC).astimezone(user_timezone)

            # Check if it's the right time (11:59 AM in user's timezone)
            target_time = time(11, 59)
            current_time = user_local_time.time()

            # Allow a 5-minute window around 11:59 AM
            start_time = time(11, 54)  # 11:54 AM
            end_time = time(12, 4)     # 12:04 PM

            if not (start_time <= current_time <= end_time):
                return False

            # Check if we already sent notification today
            last_sent = user_data.get('last_notification_sent')
            if last_sent:
                last_sent_local = last_sent.replace(tzinfo=pytz.UTC).astimezone(user_timezone)
                today_local = user_local_time.date()

                if last_sent_local.date() == today_local:
                    return False  # Already sent today

            return True

        except Exception as e:
            self.logger.error(f"Error checking notification timing for user: {str(e)}", exc_info=True)
            return False

    def send_notification(self, user_id: str, user_name: str, overdue_count: int) -> bool:
        """
        Send notification to user about overdue words
        For now, this logs the notification. In production, you'd integrate with
        push notification services, email, SMS, etc.
        """
        try:
            if overdue_count == 0:
                return False  # No need to send notification

            # Create notification message
            message = f"Now is the best timing to review {overdue_count} word{'s' if overdue_count != 1 else ''} you saved"

            # Log the notification (in production, send via push notification service)
            self.logger.info(f"📱 NOTIFICATION for {user_name} ({user_id}): {message}")

            # Record notification in database
            conn = get_db_connection()
            cur = conn.cursor()

            # Insert notification log
            cur.execute("""
                INSERT INTO notification_logs (user_id, notification_type, message, words_count)
                VALUES (%s, %s, %s, %s)
            """, (user_id, 'daily_review', message, overdue_count))

            # Update last notification sent timestamp
            cur.execute("""
                UPDATE user_preferences
                SET last_notification_sent = CURRENT_TIMESTAMP
                WHERE user_id = %s
            """, (user_id,))

            conn.commit()
            cur.close()
            conn.close()

            return True

        except Exception as e:
            self.logger.error(f"Error sending notification to user {user_id}: {str(e)}", exc_info=True)
            return False

    def process_daily_notifications(self) -> Dict[str, int]:
        """
        Main function to process all daily notifications
        Returns statistics about notifications sent
        """
        try:
            current_utc = datetime.utcnow()

            # Get users who should receive notifications
            users = self.get_users_for_notification()

            stats = {
                'users_checked': len(users),
                'notifications_sent': 0,
                'users_with_overdue': 0,
                'total_overdue_words': 0
            }

            for user_data in users:
                user_id = user_data['user_id']
                user_name = user_data['user_name']

                # Check if it's time to send notification for this user
                if not self.should_send_notification(user_data, current_utc):
                    continue

                # Get overdue words count
                overdue_count = self.get_overdue_words_count(user_id)

                if overdue_count > 0:
                    stats['users_with_overdue'] += 1
                    stats['total_overdue_words'] += overdue_count

                    # Send notification
                    if self.send_notification(user_id, user_name, overdue_count):
                        stats['notifications_sent'] += 1

            self.logger.info(f"Daily notification run completed: {stats}")
            return stats

        except Exception as e:
            self.logger.error(f"Error processing daily notifications: {str(e)}", exc_info=True)
            return {'error': str(e)}

# Global instance
notification_service = NotificationService()