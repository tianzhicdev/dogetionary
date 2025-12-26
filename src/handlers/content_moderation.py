"""
Content moderation handlers for user-reported issues
"""

from flask import jsonify, request
import logging
from utils.database import db_cursor

logger = logging.getLogger(__name__)

# Valid report types (flexible text-based, not enum)
VALID_REPORT_TYPES = ['Inappropriate', 'Incorrect', 'Copyright', 'Other']


def report_content():
    """
    POST /v3/content/report

    Submit user report for inappropriate/incorrect question content.

    Request Body:
    {
        "user_id": "uuid",
        "word": "ubiquitous",
        "learning_language": "en",
        "native_language": "zh",
        "question_type": "mc_definition",
        "video_id": 123,  // Optional, only for video_mc questions
        "report_type": "Inappropriate"  // or "Incorrect", "Copyright", "Other"
    }

    Returns:
    {
        "success": true,
        "message": "Thank you for your report. We'll review it soon."
    }

    Errors:
    - 400: Missing required fields or invalid report_type
    - 500: Database error
    """
    try:
        data = request.get_json()

        # Validate required fields
        required_fields = ['user_id', 'word', 'learning_language', 'native_language', 'question_type', 'report_type']
        missing_fields = [field for field in required_fields if field not in data]

        if missing_fields:
            logger.warning(f"Content report missing fields: {missing_fields}")
            return jsonify({
                "success": False,
                "error": f"Missing required fields: {', '.join(missing_fields)}"
            }), 400

        # Validate report_type
        report_type = data['report_type']
        if report_type not in VALID_REPORT_TYPES:
            logger.warning(f"Invalid report type: {report_type}")
            return jsonify({
                "success": False,
                "error": f"Invalid report_type. Must be one of: {', '.join(VALID_REPORT_TYPES)}"
            }), 400

        # Extract fields
        user_id = data['user_id']
        word = data['word']
        learning_lang = data['learning_language']
        native_lang = data['native_language']
        question_type = data['question_type']
        video_id = data.get('video_id')  # Optional
        comment = data.get('comment')  # Optional (for future enhancement)

        # Insert report (or update timestamp if duplicate)
        with db_cursor() as cur:
            cur.execute("""
                INSERT INTO reported_content
                (user_id, word, learning_language, native_language, question_type, video_id, report_type, comment)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (user_id, word, learning_language, native_language, question_type, report_type)
                DO UPDATE SET
                    reported_at = CURRENT_TIMESTAMP,
                    comment = COALESCE(EXCLUDED.comment, reported_content.comment)
                RETURNING id, (xmax = 0) AS inserted
            """, (
                user_id,
                word,
                learning_lang,
                native_lang,
                question_type,
                video_id,
                report_type,
                comment
            ))

            result = cur.fetchone()
            report_id = result['id']
            is_new = result['inserted']

        action = "submitted" if is_new else "updated"
        logger.info(
            f"Content report {action}: id={report_id}, user={user_id}, "
            f"word={word}, type={report_type}, question_type={question_type}"
        )

        return jsonify({
            "success": True,
            "message": "Thank you for your report. We'll review it soon.",
            "report_id": report_id
        }), 200

    except Exception as e:
        logger.error(f"Error submitting content report: {str(e)}", exc_info=True)
        return jsonify({
            "success": False,
            "error": "Failed to submit report. Please try again."
        }), 500
