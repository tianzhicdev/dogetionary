"""
Notification Controllers - Flask route handlers for notification settings
"""

from flask import request, jsonify
import logging
from datetime import time
from services.notification_service import notification_service
from services.scheduler_service import scheduler
from utils.database import get_db_connection

logger = logging.getLogger(__name__)

def get_notification_settings():
    """Get user's notification settings"""
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT
                timezone,
                notification_enabled,
                notification_time,
                last_notification_sent
            FROM user_preferences
            WHERE user_id = %s
        """, (user_id,))

        result = cur.fetchone()
        cur.close()
        conn.close()

        if not result:
            return jsonify({"error": "User not found"}), 404

        return jsonify({
            "user_id": user_id,
            "timezone": result['timezone'],
            "notification_enabled": result['notification_enabled'],
            "notification_time": result['notification_time'].strftime('%H:%M') if result['notification_time'] else '11:59',
            "last_notification_sent": result['last_notification_sent'].isoformat() if result['last_notification_sent'] else None
        })

    except Exception as e:
        logger.error(f"Error getting notification settings: {str(e)}")
        return jsonify({"error": f"Failed to get notification settings: {str(e)}"}), 500

def update_notification_settings():
    """Update user's notification settings"""
    try:
        data = request.json
        user_id = data.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        timezone = data.get('timezone', 'UTC')
        notification_enabled = data.get('notification_enabled', True)
        notification_time_str = data.get('notification_time', '11:59')

        # Parse notification time
        try:
            hour, minute = map(int, notification_time_str.split(':'))
            notification_time = time(hour, minute)
        except (ValueError, TypeError):
            return jsonify({"error": "Invalid notification_time format. Use HH:MM"}), 400

        # Validate timezone (basic check)
        try:
            import pytz
            pytz.timezone(timezone)
        except pytz.exceptions.UnknownTimeZoneError:
            return jsonify({"error": f"Unknown timezone: {timezone}"}), 400

        conn = get_db_connection()
        cur = conn.cursor()

        # Update user preferences
        cur.execute("""
            UPDATE user_preferences
            SET
                timezone = %s,
                notification_enabled = %s,
                notification_time = %s,
                updated_at = CURRENT_TIMESTAMP
            WHERE user_id = %s
        """, (timezone, notification_enabled, notification_time, user_id))

        if cur.rowcount == 0:
            # User doesn't exist, create preferences
            cur.execute("""
                INSERT INTO user_preferences (user_id, timezone, notification_enabled, notification_time)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (user_id)
                DO UPDATE SET
                    timezone = EXCLUDED.timezone,
                    notification_enabled = EXCLUDED.notification_enabled,
                    notification_time = EXCLUDED.notification_time,
                    updated_at = CURRENT_TIMESTAMP
            """, (user_id, timezone, notification_enabled, notification_time))

        conn.commit()
        cur.close()
        conn.close()

        return jsonify({
            "success": True,
            "message": "Notification settings updated successfully",
            "settings": {
                "user_id": user_id,
                "timezone": timezone,
                "notification_enabled": notification_enabled,
                "notification_time": notification_time_str
            }
        })

    except Exception as e:
        logger.error(f"Error updating notification settings: {str(e)}")
        return jsonify({"error": f"Failed to update notification settings: {str(e)}"}), 500

def get_notification_history():
    """Get user's notification history"""
    try:
        user_id = request.args.get('user_id')
        limit = request.args.get('limit', 20)

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        try:
            limit = int(limit)
            if limit > 100:
                limit = 100
        except (ValueError, TypeError):
            limit = 20

        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT
                notification_type,
                message,
                words_count,
                sent_at,
                status
            FROM notification_logs
            WHERE user_id = %s
            ORDER BY sent_at DESC
            LIMIT %s
        """, (user_id, limit))

        notifications = []
        for row in cur.fetchall():
            notifications.append({
                "type": row['notification_type'],
                "message": row['message'],
                "words_count": row['words_count'],
                "sent_at": row['sent_at'].isoformat(),
                "status": row['status']
            })

        cur.close()
        conn.close()

        return jsonify({
            "user_id": user_id,
            "notifications": notifications,
            "count": len(notifications)
        })

    except Exception as e:
        logger.error(f"Error getting notification history: {str(e)}")
        return jsonify({"error": f"Failed to get notification history: {str(e)}"}), 500

def trigger_notification_check():
    """Admin endpoint to manually trigger notification check"""
    try:
        # This would typically require admin authentication
        scheduler.run_notification_check_now()

        return jsonify({
            "success": True,
            "message": "Notification check triggered successfully"
        })

    except Exception as e:
        logger.error(f"Error triggering notification check: {str(e)}")
        return jsonify({"error": f"Failed to trigger notification check: {str(e)}"}), 500

def get_user_overdue_count():
    """Get current overdue words count for a user"""
    try:
        user_id = request.args.get('user_id')

        if not user_id:
            return jsonify({"error": "user_id parameter is required"}), 400

        overdue_count = notification_service.get_overdue_words_count(user_id)

        return jsonify({
            "user_id": user_id,
            "overdue_count": overdue_count,
            "message": f"You have {overdue_count} word{'s' if overdue_count != 1 else ''} ready for review" if overdue_count > 0 else "No words are overdue for review"
        })

    except Exception as e:
        logger.error(f"Error getting overdue count: {str(e)}")
        return jsonify({"error": f"Failed to get overdue count: {str(e)}"}), 500