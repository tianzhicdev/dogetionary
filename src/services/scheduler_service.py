"""
Scheduler Service Module - Handles periodic tasks

NOTE: Server-side notifications have been removed.
Notifications are now handled entirely by iOS local notifications.
This service is kept as a skeleton for future scheduled tasks if needed.
"""

import threading
import time
import logging
from datetime import datetime

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
        self.logger.info("Scheduler service started (no active tasks)")

    def stop(self):
        """Stop the scheduler service"""
        self.running = False
        if self.thread:
            self.thread.join(timeout=5)
        self.logger.info("Scheduler service stopped")

    def _run_scheduler(self):
        """Main scheduler loop - currently no tasks scheduled"""
        while self.running:
            try:
                # No scheduled tasks currently
                # Sleep for 60 seconds before next iteration
                time.sleep(60)

            except Exception as e:
                self.logger.error(f"Error in scheduler loop: {str(e)}", exc_info=True)
                time.sleep(60)  # Wait before retrying

# Global scheduler instance
scheduler = SchedulerService()