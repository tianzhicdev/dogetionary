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

        video_data = video['video_data']

        # Convert memoryview to bytes if needed (PostgreSQL BYTEA returns memoryview)
        if isinstance(video_data, memoryview):
            video_data = bytes(video_data)

        video_size = len(video_data)
        logger.info(f"Serving video: id={video_id}, format={format_type}, size={video_size} bytes")

        # Stream video in 256KB chunks for better performance
        # This prevents Gunicorn from using tiny default chunks (8KB)
        def generate_video_chunks():
            chunk_size = 256 * 1024  # 256KB chunks
            offset = 0
            while offset < video_size:
                end = min(offset + chunk_size, video_size)
                yield video_data[offset:end]
                offset = end

        # Return binary data with Cloudflare-optimized cache headers
        return Response(
            generate_video_chunks(),
            mimetype=mime_type,
            headers={
                # Browser caching: cache for 1 year (videos are immutable)
                'Cache-Control': 'public, max-age=31536000, immutable',
                # Cloudflare-specific: cache everything for 1 year
                'CDN-Cache-Control': 'public, max-age=31536000, immutable',
                # Alternative Cloudflare header (redundancy)
                'Cloudflare-CDN-Cache-Control': 'public, max-age=31536000',
                # ETag for cache validation
                'ETag': f'"{video_id}"',
                # Security headers
                'X-Content-Type-Options': 'nosniff',
                # Content length for better caching
                'Content-Length': str(video_size),
                # Accept range requests for video seeking
                'Accept-Ranges': 'bytes'
            }
        )

    except Exception as e:
        logger.error(f"Error serving video {video_id}: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500


def get_video_bytes_only(video_id: int):
    """
    TEST ENDPOINT: Bytes conversion only, NO generator

    This tests if converting memoryview to bytes alone improves performance.
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
        mime_mapping = {
            'mp4': 'video/mp4',
            'mov': 'video/quicktime',
            'webm': 'video/webm',
            'avi': 'video/x-msvideo',
            'mkv': 'video/x-matroska'
        }
        mime_type = mime_mapping.get(format_type, f"video/{format_type}")

        video_data = video['video_data']

        # Convert memoryview to bytes
        if isinstance(video_data, memoryview):
            video_data = bytes(video_data)

        video_size = len(video_data)
        logger.info(f"[BYTES-ONLY TEST] Serving video: id={video_id}, size={video_size} bytes")

        # Return bytes directly WITHOUT generator
        return Response(
            video_data,
            mimetype=mime_type,
            headers={
                'Cache-Control': 'public, max-age=31536000, immutable',
                'X-Content-Type-Options': 'nosniff',
                'Content-Length': str(video_size),
                'Accept-Ranges': 'bytes'
            }
        )

    except Exception as e:
        logger.error(f"Error serving video {video_id}: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500


def get_video_generator_memoryview(video_id: int):
    """
    TEST ENDPOINT: Generator with memoryview (NO bytes conversion)

    This tests if the generator pattern alone improves performance.
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
        mime_mapping = {
            'mp4': 'video/mp4',
            'mov': 'video/quicktime',
            'webm': 'video/webm',
            'avi': 'video/x-msvideo',
            'mkv': 'video/x-matroska'
        }
        mime_type = mime_mapping.get(format_type, f"video/{format_type}")

        video_data = video['video_data']  # Keep as memoryview!

        video_size = len(video_data)
        logger.info(f"[GENERATOR-MEMORYVIEW TEST] Serving video: id={video_id}, size={video_size} bytes")

        # Use generator but DON'T convert to bytes
        def generate_video_chunks():
            chunk_size = 8 * 1024  # 8KB chunks
            offset = 0
            while offset < video_size:
                end = min(offset + chunk_size, video_size)
                yield video_data[offset:end]  # Yield memoryview slices
                offset = end

        return Response(
            generate_video_chunks(),
            mimetype=mime_type,
            headers={
                'Cache-Control': 'public, max-age=31536000, immutable',
                'X-Content-Type-Options': 'nosniff',
                'Content-Length': str(video_size),
                'Accept-Ranges': 'bytes'
            }
        )

    except Exception as e:
        logger.error(f"Error serving video {video_id}: {e}", exc_info=True)
        return jsonify({"error": "Internal server error"}), 500
