"""
Video Handler - Serve video files for practice mode

Provides endpoint to fetch video binary data with CDN-friendly caching headers.
"""

import logging
from flask import Response, jsonify
from utils.database import db_fetch_one

logger = logging.getLogger(__name__)


def get_video(video_id: int):
    """
    Serve video binary data by ID.

    Args:
        video_id: The ID of the video to fetch

    Returns:
        Response with video binary data and CDN-friendly cache headers

    Example:
        GET /v3/videos/12

        Response:
            Content-Type: video/mp4
            Cache-Control: public, max-age=31536000, immutable
            <binary video data>
    """
    try:
        # Fetch video from database
        video = db_fetch_one("""
            SELECT video_data, format
            FROM videos
            WHERE id = %s
        """, (video_id,))

        if not video:
            logger.warning(f"Video not found: id={video_id}")
            return jsonify({"error": "Video not found"}), 404

        # Determine MIME type based on format
        format_type = video['format'].lower()
        mime_type = f"video/{format_type}"

        # Common video MIME types
        mime_mapping = {
            'mp4': 'video/mp4',
            'mov': 'video/quicktime',
            'webm': 'video/webm',
            'avi': 'video/x-msvideo',
            'mkv': 'video/x-matroska'
        }

        mime_type = mime_mapping.get(format_type, f"video/{format_type}")

        logger.info(f"Serving video: id={video_id}, format={format_type}, size={len(video['video_data'])} bytes")

        # Return binary data with CDN-friendly cache headers
        return Response(
            video['video_data'],
            mimetype=mime_type,
            headers={
                # CDN caching: cache for 1 year (videos are immutable)
                'Cache-Control': 'public, max-age=31536000, immutable',
                # Security headers
                'X-Content-Type-Options': 'nosniff',
                # Optional: Add content length
                'Content-Length': str(len(video['video_data']))
            }
        )

    except Exception as e:
        logger.error(f"Error serving video {video_id}: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500
