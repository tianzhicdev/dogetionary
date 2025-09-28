import queue
import time
import logging
from handlers.words import audio_generation_queue

logger = logging.getLogger(__name__)

def audio_generation_worker():
    """Background worker for audio generation"""
    logger.info("Audio generation worker started")

    while True:
        try:
            # Check if queue has items
            if not audio_generation_queue.empty():
                task = audio_generation_queue.get()
                # Process task here (implementation would be in handlers.words)
                logger.info(f"Processing audio task: {task}")
                audio_generation_queue.task_done()
            else:
                time.sleep(1)
        except Exception as e:
            logger.error(f"Audio worker error: {e}")
            time.sleep(5)