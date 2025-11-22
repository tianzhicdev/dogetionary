"""
Analytics service for tracking user actions
"""

from utils.database import get_db_connection
from datetime import datetime
import logging
import json

logger = logging.getLogger(__name__)

class AnalyticsService:
    def __init__(self):
        self.categories = {
            'dictionary_search': 'dictionary',
            'dictionary_search_audio': 'dictionary',
            'dictionary_save': 'dictionary',
            'dictionary_auto_save': 'dictionary',
            'dictionary_example_audio': 'dictionary',
            'dictionary_illustration': 'dictionary',

            'validation_invalid': 'validation',
            'validation_accept_suggestion': 'validation',
            'validation_use_original': 'validation',
            'validation_cancel': 'validation',

            'review_start': 'review',
            'review_answer_correct': 'review',
            'review_answer_incorrect': 'review',
            'review_audio': 'review',
            'review_next': 'review',
            'review_complete': 'review',

            'nav_tab_dictionary': 'navigation',
            'nav_tab_saved': 'navigation',
            'nav_tab_review': 'navigation',
            'nav_tab_leaderboard': 'navigation',
            'nav_tab_settings': 'navigation',

            'profile_name_update': 'profile',
            'profile_motto_update': 'profile',
            'profile_language_learning': 'profile',
            'profile_language_native': 'profile',

            'settings_notification_enable': 'settings',
            'settings_notification_disable': 'settings',
            'settings_notification_time': 'settings',
            'settings_timezone_update': 'settings',

            'saved_view_details': 'saved',
            'saved_mark_known': 'saved',
            'saved_mark_learning': 'saved',
            'saved_delete_word': 'saved',

            'feedback_submit': 'feedback',

            'pronunciation_practice': 'pronunciation',

            'app_launch': 'app_lifecycle',
            'app_background': 'app_lifecycle',
            'app_foreground': 'app_lifecycle'
        }

    def track_action(self, user_id: str, action: str, metadata: dict = None,
                     session_id: str = None, platform: str = 'ios', app_version: str = None):
        """
        Track a user action with metadata

        Args:
            user_id: UUID of the user
            action: Action enum string
            metadata: Additional data about the action
            session_id: Session identifier
            platform: Platform (ios, web, etc.)
            app_version: App version string
        """
        try:
            # Validate action
            if action not in self.categories:
                logger.warning(f"Unknown action: {action}")
                return False

            category = self.categories[action]
            metadata_json = json.dumps(metadata or {})

            conn = get_db_connection()
            cur = conn.cursor()

            cur.execute("""
                INSERT INTO user_actions (
                    user_id, action, category, metadata,
                    session_id, platform, app_version
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (
                user_id, action, category, metadata_json,
                session_id, platform, app_version
            ))

            conn.commit()
            cur.close()
            conn.close()

            logger.info(f"Tracked action: {action} for user {user_id}")
            return True

        except Exception as e:
            logger.error(f"Error tracking action {action}: {str(e)}")
            return False

    def get_daily_action_counts(self, days: int = 7):
        """
        Get action counts by day for the past N days
        """
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            cur.execute("""
                SELECT
                    DATE(created_at) as action_date,
                    action,
                    category,
                    COUNT(*) as count
                FROM user_actions
                WHERE created_at >= CURRENT_DATE - INTERVAL '%s days'
                GROUP BY DATE(created_at), action, category
                ORDER BY action_date DESC, count DESC
            """, (days,))

            results = cur.fetchall()
            cur.close()
            conn.close()

            return results

        except Exception as e:
            logger.error(f"Error getting daily action counts: {str(e)}")
            return []

    def get_action_analytics(self, days: int = 7):
        """
        Get analytics with unique user counts and total action counts for each action
        Returns data suitable for graph visualization
        """
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            cur.execute("""
                SELECT
                    action,
                    category,
                    COUNT(*) as total_count,
                    COUNT(DISTINCT user_id) as unique_users,
                    DATE(created_at) as action_date
                FROM user_actions
                WHERE created_at >= CURRENT_DATE - INTERVAL '%s days'
                GROUP BY action, category, DATE(created_at)
                ORDER BY action_date DESC, total_count DESC
            """, (days,))

            results = cur.fetchall()
            cur.close()
            conn.close()

            return results

        except Exception as e:
            logger.error(f"Error getting action analytics: {str(e)}")
            return []

    def get_action_summary(self, days: int = 7):
        """
        Get summary analytics for each action type across the time period
        """
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            cur.execute("""
                SELECT
                    action,
                    category,
                    COUNT(*) as total_count,
                    COUNT(DISTINCT user_id) as unique_users
                FROM user_actions
                WHERE created_at >= CURRENT_DATE - INTERVAL '%s days'
                GROUP BY action, category
                ORDER BY total_count DESC
            """, (days,))

            results = cur.fetchall()
            cur.close()
            conn.close()

            return results

        except Exception as e:
            logger.error(f"Error getting action summary: {str(e)}")
            return []

    def get_user_actions(self, user_id: str, limit: int = 100):
        """
        Get recent actions for a specific user
        """
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            cur.execute("""
                SELECT
                    created_at,
                    action,
                    category,
                    metadata,
                    session_id,
                    platform,
                    app_version
                FROM user_actions
                WHERE user_id = %s
                ORDER BY created_at DESC
                LIMIT %s
            """, (user_id, limit))

            results = cur.fetchall()
            cur.close()
            conn.close()

            return results

        except Exception as e:
            logger.error(f"Error getting user actions: {str(e)}")
            return []

    def get_all_users(self):
        """
        Get list of all users for the dropdown
        """
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            cur.execute("""
                SELECT DISTINCT
                    up.user_id,
                    up.user_name
                FROM user_preferences up
                WHERE up.user_id IN (
                    SELECT DISTINCT user_id FROM user_actions
                )
                ORDER BY up.user_name
            """)

            results = cur.fetchall()
            cur.close()
            conn.close()

            return results

        except Exception as e:
            logger.error(f"Error getting users: {str(e)}")
            return []

    def get_time_based_analytics(self, days: int = 7):
        """
        Get time-based analytics data for line charts
        Returns data formatted for time series visualization with dates on x-axis
        """
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            cur.execute("""
                WITH date_series AS (
                    SELECT generate_series(
                        CURRENT_DATE - INTERVAL '%s days',
                        CURRENT_DATE,
                        '1 day'::interval
                    )::date as action_date
                ),
                actions AS (
                    SELECT DISTINCT action FROM user_actions
                    WHERE created_at >= CURRENT_DATE - INTERVAL '%s days'
                ),
                daily_data AS (
                    SELECT
                        DATE(created_at) as action_date,
                        action,
                        COUNT(*) as total_count,
                        COUNT(DISTINCT user_id) as unique_users
                    FROM user_actions
                    WHERE created_at >= CURRENT_DATE - INTERVAL '%s days'
                    GROUP BY DATE(created_at), action
                )
                SELECT
                    ds.action_date,
                    a.action,
                    COALESCE(dd.total_count, 0) as total_count,
                    COALESCE(dd.unique_users, 0) as unique_users
                FROM date_series ds
                CROSS JOIN actions a
                LEFT JOIN daily_data dd ON ds.action_date = dd.action_date AND a.action = dd.action
                ORDER BY ds.action_date ASC, a.action
            """, (days, days, days))

            results = cur.fetchall()
            cur.close()
            conn.close()

            return results

        except Exception as e:
            logger.error(f"Error getting time-based analytics: {str(e)}")
            return []

    def get_monthly_daily_metrics(self, days: int = 30):
        """
        Get monthly daily metrics for unique users, searches, and reviews
        Returns data for monthly line chart showing daily unique active users, searches, and reviews
        """
        try:
            conn = get_db_connection()
            cur = conn.cursor()

            cur.execute("""
                WITH date_series AS (
                    SELECT generate_series(
                        CURRENT_DATE - INTERVAL '%s days',
                        CURRENT_DATE,
                        '1 day'::interval
                    )::date as metric_date
                ),
                daily_metrics AS (
                    SELECT
                        DATE(created_at) as metric_date,
                        -- Daily unique active users (any action)
                        COUNT(DISTINCT user_id) as unique_active_users,
                        -- Daily unique users who searched (dictionary actions)
                        COUNT(DISTINCT CASE WHEN action LIKE 'dictionary%%' THEN user_id END) as unique_search_users,
                        -- Daily unique users who reviewed
                        COUNT(DISTINCT CASE WHEN action LIKE 'review%%' THEN user_id END) as unique_review_users
                    FROM user_actions
                    WHERE created_at >= CURRENT_DATE - INTERVAL '%s days'
                    GROUP BY DATE(created_at)
                )
                SELECT
                    ds.metric_date,
                    COALESCE(dm.unique_active_users, 0) as unique_active_users,
                    COALESCE(dm.unique_search_users, 0) as unique_search_users,
                    COALESCE(dm.unique_review_users, 0) as unique_review_users
                FROM date_series ds
                LEFT JOIN daily_metrics dm ON ds.metric_date = dm.metric_date
                ORDER BY ds.metric_date ASC
            """, (days, days))

            results = cur.fetchall()
            cur.close()
            conn.close()

            return results

        except Exception as e:
            logger.error(f"Error getting monthly daily metrics: {str(e)}")
            return []

# Global instance
analytics_service = AnalyticsService()
