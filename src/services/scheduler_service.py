"""
Scheduler Service Module - Handles periodic tasks like notifications
"""

import threading
import time
import logging
from datetime import datetime
from services.notification_service import notification_service

logger = logging.getLogger(__name__)

class SchedulerService:
    """Service for running scheduled tasks"""

    def __init__(self):
        self.running = False
        self.thread = None
        self.logger = logger

    def start(self):
        """Start the scheduler service"""
        if self.running:
            return

        self.running = True
        self.thread = threading.Thread(target=self._run_scheduler, daemon=True)
        self.thread.start()
        self.logger.info("Scheduler service started")

    def stop(self):
        """Stop the scheduler service"""
        self.running = False
        if self.thread:
            self.thread.join(timeout=5)
        self.logger.info("Scheduler service stopped")

    def _run_scheduler(self):
        """Main scheduler loop"""
        last_notification_check = 0
        notification_check_interval = 300  # Check every 5 minutes

        while self.running:
            try:
                current_time = time.time()

                # Check for notifications every 5 minutes
                if current_time - last_notification_check >= notification_check_interval:
                    self._run_notification_check()
                    last_notification_check = current_time

                # Sleep for 60 seconds before next iteration
                time.sleep(60)

            except Exception as e:
                self.logger.error(f"Error in scheduler loop: {str(e, exc_info=True)}")
                time.sleep(60)  # Wait before retrying

    def _run_notification_check(self):
        """Run the daily notification check"""
        try:
            self.logger.info("Running scheduled notification check...")
            stats = notification_service.process_daily_notifications()

            if 'error' not in stats and stats['notifications_sent'] > 0:
                self.logger.info(f"📱 Sent {stats['notifications_sent']} notifications to users with {stats['total_overdue_words']} overdue words")

        except Exception as e:
            self.logger.error(f"Error in notification check: {str(e, exc_info=True)}")

    def run_notification_check_now(self):
        """Manually trigger notification check (for testing/admin purposes)"""
        self.logger.info("Manual notification check triggered")
        self._run_notification_check()

# Global scheduler instance
scheduler = SchedulerService()