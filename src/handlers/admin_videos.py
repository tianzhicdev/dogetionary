"""
Admin Video Handler - Upload videos and create word-to-video mappings

Provides endpoint for batch uploading videos with word mappings from the find_videos pipeline.
"""

import logging
import base64
from flask import request, jsonify
from utils.database import db_fetch_one, db_fetch_all, db_execute, get_db_connection
import psycopg2.extras

logger = logging.getLogger(__name__)


# Mapping of bundle names to database column names
BUNDLE_COLUMN_MAP = {
    "toefl_beginner": "is_toefl_beginner",
    "toefl_intermediate": "is_toefl_intermediate",
    "toefl_advanced": "is_toefl_advanced",
    "ielts_beginner": "is_ielts_beginner",
    "ielts_intermediate": "is_ielts_intermediate",
    "ielts_advanced": "is_ielts_advanced",
    "demo": "is_demo",
    "business_english": "business_english",
    "everyday_english": "everyday_english",
}


def get_bundle_words_needing_videos(bundle_name):
    """
    Get words from a bundle that don't have any videos yet.

    URL: GET /v3/admin/bundles/{bundle_name}/words-needing-videos

    Args:
        bundle_name: Bundle identifier (e.g., 'toefl_beginner', 'ielts_advanced')

    Returns:
        JSON response with list of words needing videos:
        {
            "bundle": "toefl_beginner",
            "words": ["abandon", "ability", ...],
            "total_count": 150
        }
    """
    try:
        # Validate bundle name
        if bundle_name not in BUNDLE_COLUMN_MAP:
            valid_bundles = ", ".join(BUNDLE_COLUMN_MAP.keys())
            return jsonify({
                "error": f"Invalid bundle name '{bundle_name}'. Valid bundles: {valid_bundles}"
            }), 400

        column_name = BUNDLE_COLUMN_MAP[bundle_name]

        # Query words from bundle that don't have videos
        # Use parameterized query with format for column name (safe since we validated it)
        query = f"""
            SELECT bv.word
            FROM bundle_vocabularies bv
            WHERE bv.{column_name} = TRUE
              AND NOT EXISTS (
                  SELECT 1
                  FROM word_to_video wtv
                  WHERE wtv.word = bv.word
                    AND wtv.learning_language = bv.language
              )
            ORDER BY bv.word
        """

        rows = db_fetch_all(query)

        # Extract words from rows
        words = [row['word'] for row in rows]

        logger.info(f"Found {len(words)} words needing videos for bundle '{bundle_name}'")

        return jsonify({
            "bundle": bundle_name,
            "words": words,
            "total_count": len(words)
        }), 200

    except Exception as e:
        logger.error(f"Error in get_bundle_words_needing_videos: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


def batch_upload_videos():
    """
    Batch upload videos with word-to-video mappings.

    Expected JSON payload:
    {
        "source_id": "find_videos_20251211_143022",  // Optional: pipeline run identifier
        "videos": [
            {
                "slug": "clip-slug",
                "name": "clip-name",
                "format": "mp4",
                "video_data_base64": "base64-encoded-video",
                "transcript": "...",
                "metadata": {
                    "clip_id": 123,
                    "duration_seconds": 14,
                    ...
                },
                "word_mappings": [
                    {
                        "word": "abdominal",
                        "learning_language": "en",
                        "relevance_score": 0.95
                    }
                ]
            }
        ]
    }

    Returns:
    {
        "success": true,
        "results": [
            {
                "slug": "clip-slug",
                "video_id": 123,
                "status": "created" | "existed",
                "mappings_created": 2,
                "mappings_skipped": 0
            }
        ],
        "total_videos": 1,
        "total_mappings": 2
    }
    """
    try:
        data = request.get_json()

        if not data or 'videos' not in data:
            return jsonify({"error": "Missing 'videos' in request body"}), 400

        videos = data['videos']
        source_id = data.get('source_id')  # Optional pipeline run identifier

        if not isinstance(videos, list) or len(videos) == 0:
            return jsonify({"error": "'videos' must be a non-empty list"}), 400

        results = []
        total_mappings = 0

        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        try:
            for video_data in videos:
                result = _upload_single_video(cursor, video_data, source_id)
                results.append(result)
                total_mappings += result['mappings_created']

            # Commit transaction
            conn.commit()

            logger.info(f"Batch upload completed: {len(results)} videos, {total_mappings} mappings")

            return jsonify({
                "success": True,
                "results": results,
                "total_videos": len(results),
                "total_mappings": total_mappings
            }), 200

        except Exception as e:
            conn.rollback()
            raise

        finally:
            cursor.close()
            conn.close()

    except Exception as e:
        logger.error(f"Error in batch_upload_videos: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500


def _upload_single_video(cursor, video_data: dict, source_id: str = None) -> dict:
    """
    Upload a single video with its word mappings.

    Args:
        cursor: Database cursor
        video_data: Video data dictionary
        source_id: Optional pipeline run identifier

    Returns:
        Result dictionary with upload stats
    """
    slug = video_data.get('slug')
    name = video_data.get('name', slug)
    format_type = video_data.get('format', 'mp4')
    video_base64 = video_data.get('video_data_base64')
    size_bytes = video_data.get('size_bytes')
    transcript = video_data.get('transcript', '')
    audio_transcript = video_data.get('audio_transcript')
    audio_transcript_verified = video_data.get('audio_transcript_verified', False)
    whisper_metadata = video_data.get('whisper_metadata')
    metadata = video_data.get('metadata', {})
    word_mappings = video_data.get('word_mappings', [])

    # Validate required fields
    if not slug or not video_base64:
        raise ValueError(f"Missing required fields: slug or video_data_base64")

    # Decode video data
    try:
        video_bytes = base64.b64decode(video_base64)
    except Exception as e:
        raise ValueError(f"Invalid base64 video data: {e}")

    # Use INSERT ... ON CONFLICT to handle idempotency and race conditions
    cursor.execute("""
        INSERT INTO videos (name, format, video_data, size_bytes, transcript, audio_transcript,
                           audio_transcript_verified, whisper_metadata, metadata, source_id)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (name, format) DO UPDATE
        SET video_data = EXCLUDED.video_data,
            size_bytes = EXCLUDED.size_bytes,
            transcript = EXCLUDED.transcript,
            audio_transcript = EXCLUDED.audio_transcript,
            audio_transcript_verified = EXCLUDED.audio_transcript_verified,
            whisper_metadata = EXCLUDED.whisper_metadata,
            metadata = EXCLUDED.metadata,
            source_id = EXCLUDED.source_id,
            updated_at = NOW()
        RETURNING id, (xmax = 0) AS inserted
    """, (name, format_type, video_bytes, size_bytes or len(video_bytes), transcript, audio_transcript,
          audio_transcript_verified, psycopg2.extras.Json(whisper_metadata) if whisper_metadata else None,
          psycopg2.extras.Json(metadata), source_id))

    result = cursor.fetchone()
    video_id = result['id']
    status = "created" if result['inserted'] else "updated"
    size_mb = (size_bytes or len(video_bytes)) / (1024 * 1024)
    logger.info(f"{status.capitalize()} video: {name}.{format_type} (id={video_id}, size={size_mb:.2f}MB, "
               f"audio_verified={audio_transcript_verified}, source_id={source_id})")

    # Insert word mappings
    mappings_created = 0
    mappings_skipped = 0

    for mapping in word_mappings:
        word = mapping.get('word')
        learning_language = mapping.get('learning_language', 'en')
        relevance_score = mapping.get('relevance_score')
        transcript_source = mapping.get('transcript_source', 'metadata')
        timestamp = mapping.get('timestamp')

        if not word:
            logger.warning(f"Skipping mapping with missing word for video_id={video_id}")
            continue

        # Insert mapping (idempotent with ON CONFLICT)
        # Include verified_at timestamp if audio-verified
        from datetime import datetime
        verified_at = datetime.now() if transcript_source == 'audio' else None

        cursor.execute("""
            INSERT INTO word_to_video (word, learning_language, video_id, relevance_score, source_id,
                                      transcript_source, verified_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (word, learning_language, video_id) DO UPDATE
            SET relevance_score = EXCLUDED.relevance_score,
                source_id = EXCLUDED.source_id,
                transcript_source = EXCLUDED.transcript_source,
                verified_at = EXCLUDED.verified_at
            RETURNING (xmax = 0) AS inserted
        """, (word.lower(), learning_language, video_id, relevance_score, source_id,
              transcript_source, verified_at))

        result = cursor.fetchone()
        if result['inserted']:
            mappings_created += 1
            logger.debug(f"Created mapping: word={word}, video_id={video_id}, score={relevance_score}, "
                        f"source={transcript_source}")
        else:
            mappings_skipped += 1
            logger.debug(f"Updated mapping: word={word}, video_id={video_id}, score={relevance_score}, "
                        f"source={transcript_source}")

    return {
        "slug": slug,
        "video_id": video_id,
        "status": status,
        "mappings_created": mappings_created,
        "mappings_skipped": mappings_skipped
    }
