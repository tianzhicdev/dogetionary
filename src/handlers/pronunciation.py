"""
Pronunciation practice handlers
"""

from flask import request, jsonify
import base64
import json
import logging
from utils.database import get_db_connection
import uuid

logger = logging.getLogger(__name__)

# Lazy initialization of pronunciation service to avoid import errors
pronunciation_service = None

def get_pronunciation_service():
    global pronunciation_service
    if pronunciation_service is None:
        from services.pronunciation_service import PronunciationService
        pronunciation_service = PronunciationService()
    return pronunciation_service

def practice_pronunciation():
    """
    POST /pronunciation/practice
    Process user pronunciation practice attempt
    """
    try:
        data = request.get_json()

        # Validate required fields
        required_fields = ['user_id', 'original_text', 'audio_data']
        for field in required_fields:
            if field not in data or not data[field]:
                return jsonify({'error': f'Missing required field: {field}'}), 400

        user_id = data['user_id']
        original_text = data['original_text'].strip()
        audio_data_base64 = data['audio_data']
        metadata = data.get('metadata', {})

        # Validate user_id
        try:
            uuid.UUID(user_id)
        except ValueError:
            return jsonify({'error': 'Invalid user_id format'}), 400

        # Decode audio data from base64
        try:
            audio_data = base64.b64decode(audio_data_base64)
        except Exception as e:
            logger.error(f"Failed to decode audio data: {str(e)}", exc_info=True)
            return jsonify({'error': 'Invalid audio data encoding'}), 400

        # Get user's learning language from database
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT learning_language
            FROM user_preferences
            WHERE user_id = %s
        """, (user_id,))

        row = cur.fetchone()
        learning_language = row['learning_language'] if row else 'en'

        cur.close()
        conn.close()

        # Process pronunciation with OpenAI
        result = get_pronunciation_service().evaluate_pronunciation(
            original_text=original_text,
            audio_data=audio_data,
            user_id=user_id,
            metadata=metadata,
            language=learning_language
        )

        if result['success']:
            return jsonify({
                'success': True,
                'result': result['result'],
                'similarity_score': result['similarity_score'],
                'recognized_text': result['recognized_text'],
                'feedback': result['feedback']
            })
        else:
            return jsonify({
                'success': False,
                'error': result.get('error', 'Failed to process pronunciation')
            }), 500

    except Exception as e:
        logger.error(f"Error in practice_pronunciation: {str(e)}", exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500