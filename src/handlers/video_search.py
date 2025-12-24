"""
Video search workflow handlers.

Endpoints for checking if words have videos, fetching video questions,
and triggering async video search using VideoFinder.
"""

import logging
from flask import request, jsonify
from typing import Dict, List
import threading
import tempfile
import os

from utils.database import get_db_connection, db_fetch_one, db_fetch_all
from services.question_generation_service import generate_video_mc_question

logger = logging.getLogger(__name__)


def check_word_has_videos():
    """Check if a word has videos in word_to_video table"""
    word = request.args.get('word', '').strip().lower()
    lang = request.args.get('lang', 'en')

    if not word:
        return jsonify({"error": "word required"}), 400

    try:
        # Check word_to_video table
        result = db_fetch_one("""
            SELECT COUNT(*) as count
            FROM word_to_video
            WHERE word = %s AND learning_language = %s
        """, (word, lang))

        count = result['count'] if result else 0

        return jsonify({
            "word": word,
            "has_videos": count > 0,
            "video_count": count
        })

    except Exception as e:
        logger.error(f"Error checking videos for {word}: {e}")
        return jsonify({"error": str(e)}), 500


def get_video_questions_for_word():
    """
    Fetch video questions for a specific word.
    Returns up to N video_mc questions for immediate practice.
    """
    word = request.args.get('word', '').strip().lower()
    lang = request.args.get('lang', 'en')
    limit = int(request.args.get('limit', 5))

    if not word:
        return jsonify({"error": "word required"}), 400

    try:
        # Get videos for this word
        videos = db_fetch_all("""
            SELECT
                v.id as video_id,
                v.name as video_name,
                v.audio_transcript,
                wtv.word
            FROM word_to_video wtv
            JOIN videos v ON wtv.video_id = v.id
            WHERE wtv.word = %s
              AND wtv.learning_language = %s
            ORDER BY wtv.relevance_score DESC NULLS LAST
            LIMIT %s
        """, (word, lang, limit))

        if not videos:
            return jsonify({"word": word, "questions": [], "count": 0})

        # Generate questions for each video
        questions = []
        for idx, video in enumerate(videos):
            try:
                # Generate video_mc question
                question_data = generate_video_mc_question(
                    word=video['word'],
                    definition={},  # Not used for video questions
                    learning_lang=lang,
                    native_lang='zh'  # TODO: get from user preferences
                )

                # Return BatchReviewQuestion format (same as /v3/review-batch)
                questions.append({
                    "word": video['word'],
                    "saved_word_id": None,  # Video questions are not from saved words
                    "source": "VIDEO",  # Custom source type for video questions
                    "position": idx,
                    "learning_language": lang,
                    "native_language": "zh",  # TODO: get from user preferences
                    "question": question_data,
                    "definition": None  # No definition needed for video questions
                })
            except Exception as e:
                logger.error(f"Failed to generate question for video {video['video_id']}: {e}")
                continue

        return jsonify({
            "word": word,
            "questions": questions,
            "count": len(questions)
        })

    except Exception as e:
        logger.error(f"Error fetching video questions for {word}: {e}")
        return jsonify({"error": str(e)}), 500


def trigger_video_search():
    """
    Trigger async video search for a word.
    Spawns background job - no blocking.
    """
    data = request.get_json()
    word = data.get('word', '').strip().lower()
    lang = data.get('learning_language', 'en')

    if not word:
        return jsonify({"error": "word required"}), 400

    # Spawn background thread (non-blocking)
    thread = threading.Thread(
        target=run_video_finder_for_word,
        args=(word, lang),
        daemon=True
    )
    thread.start()

    logger.info(f"Triggered background video search for '{word}'")

    return jsonify({
        "status": "triggered",
        "word": word,
        "message": "Video search started in background"
    })


def run_video_finder_for_word(word: str, lang: str):
    """
    Background task to run find_videos.py for a single word.
    Uses VideoFinder class from services/video_finder.py.
    """
    try:
        from services.video_finder import VideoFinder

        # Get API keys from environment
        clipcafe_api_key = os.getenv('CLIPCAFE')
        openai_api_key = os.getenv('OPENAI_API_KEY')

        if not clipcafe_api_key or not openai_api_key:
            logger.error("Missing API keys for video search (CLIPCAFE, OPENAI_API_KEY)")
            return

        # Use temporary storage (no disk persistence needed - upload directly)
        with tempfile.TemporaryDirectory() as temp_dir:
            # Get backend URL from environment or use default
            backend_url = os.getenv('BASE_URL', 'http://localhost:5001')

            finder = VideoFinder(
                storage_dir=temp_dir,
                backend_url=backend_url,
                word_list_path=None,
                clipcafe_api_key=clipcafe_api_key,
                openai_api_key=openai_api_key,
                max_videos_per_word=20,  # Reduced for single word
                education_min_score=0.6,
                context_min_score=0.6,
                download_only=False  # Upload to DB
            )

            # Process single word
            vocab_list = [word]  # Single word for LLM context
            word_stats = finder.process_word(word, vocab_list)

            logger.info(f"Completed video search for '{word}': {word_stats['videos_uploaded']} videos uploaded")

    except Exception as e:
        logger.error(f"Video search failed for '{word}': {e}", exc_info=True)
