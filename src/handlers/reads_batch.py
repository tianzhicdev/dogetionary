"""
Batch Forgetting Curve Handler

Provides efficient batch endpoint for fetching multiple forgetting curves in one request.
Uses SQL JOIN aggregation to minimize database queries (200 queries → 1 query for 100 words).
"""

from flask import jsonify, request
from handlers.reads import calculate_curve_for_word
import logging

logger = logging.getLogger(__name__)


def get_forgetting_curves_batch():
    """
    Get forgetting curves for multiple words in one request.

    POST /v3/words/batch/forgetting-curves
    Body: {"user_id": "uuid", "word_ids": [1, 2, 3, ...]}

    Returns:
        {
            "curves": [ForgettingCurveResponse, ...],
            "not_found": [word_id, ...]
        }
    """
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        word_ids = data.get('word_ids', [])

        # Validation
        if not user_id:
            return jsonify({"error": "user_id is required"}), 400

        if not isinstance(word_ids, list) or len(word_ids) == 0:
            return jsonify({"error": "word_ids must be non-empty array"}), 400

        # Fetch all words and reviews in ONE optimized query
        from utils.database import db_fetch_all

        results = db_fetch_all("""
            SELECT
                sw.id as word_id,
                sw.word,
                sw.learning_language,
                sw.created_at,
                COALESCE(
                    jsonb_agg(
                        jsonb_build_object(
                            'response', r.response,
                            'reviewed_at', r.reviewed_at
                        ) ORDER BY r.reviewed_at
                    ) FILTER (WHERE r.id IS NOT NULL),
                    '[]'::jsonb
                ) as review_history
            FROM saved_words sw
            LEFT JOIN reviews r ON r.word_id = sw.id AND r.user_id = sw.user_id
            WHERE sw.id = ANY(%s::INTEGER[]) AND sw.user_id = %s::UUID
            GROUP BY sw.id, sw.word, sw.learning_language, sw.created_at
            ORDER BY sw.id
        """, (word_ids, user_id))

        # Convert results to dict for easier processing
        words_data = []
        for row in results:
            # Parse JSONB review_history (psycopg2 returns it as string)
            import json
            review_history_raw = row['review_history']
            if isinstance(review_history_raw, str):
                review_history = json.loads(review_history_raw)
            else:
                review_history = review_history_raw

            # Convert ISO string dates back to datetime objects
            from datetime import datetime
            for review in review_history:
                if isinstance(review['reviewed_at'], str):
                    review['reviewed_at'] = datetime.fromisoformat(review['reviewed_at'].replace('Z', '+00:00'))

            words_data.append({
                'id': row['word_id'],
                'word': row['word'],
                'learning_language': row['learning_language'],
                'created_at': row['created_at'],
                'review_history': review_history
            })

        # Generate curves using extracted core logic
        curves = []
        found_word_ids = set()

        for word_data in words_data:
            found_word_ids.add(word_data['id'])

            # Call the same calculation function as single-word endpoint
            curve_data = calculate_curve_for_word(
                {
                    'id': word_data['id'],
                    'word': word_data['word'],
                    'created_at': word_data['created_at']
                },
                word_data['review_history']
            )
            curves.append(curve_data)

        # Determine which words were not found
        not_found = [wid for wid in word_ids if wid not in found_word_ids]

        logger.info(f"Batch forgetting curves: {len(curves)} curves generated, {len(not_found)} not found")

        return jsonify({
            "curves": curves,
            "not_found": not_found
        }), 200

    except Exception as e:
        logger.error(f"Error in batch forgetting curves: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500
