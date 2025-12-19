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


def submit_pronunciation_review():
    """
    POST /review/pronounce
    Submit a pronunciation-based review attempt.

    Combines pronunciation evaluation with review submission.
    Evaluates user's pronunciation and saves result to both pronunciation_practice and reviews tables.

    Request Body:
        - user_id: User UUID
        - word: The target word being reviewed
        - original_text: The sentence to pronounce
        - audio_data: Base64 encoded audio data
        - learning_language: Language code (e.g., 'en')
        - native_language: User's native language code
        - evaluation_threshold: Minimum score to pass (default 0.7)
    """
    try:
        data = request.get_json()

        # Validate required fields
        required_fields = ['user_id', 'word', 'original_text', 'audio_data', 'learning_language', 'native_language']
        for field in required_fields:
            if field not in data or not data[field]:
                return jsonify({'error': f'Missing required field: {field}'}), 400

        user_id = data['user_id']
        word = data['word'].strip()
        original_text = data['original_text'].strip()
        audio_data_base64 = data['audio_data']
        learning_language = data['learning_language']
        native_language = data['native_language']
        evaluation_threshold = data.get('evaluation_threshold', 0.7)

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

        # Evaluate pronunciation
        metadata = {
            'word': word,
            'question_type': 'pronounce_sentence',
            'threshold': evaluation_threshold
        }

        result = get_pronunciation_service().evaluate_pronunciation(
            original_text=original_text,
            audio_data=audio_data,
            user_id=user_id,
            metadata=metadata,
            language=learning_language
        )

        if not result['success']:
            return jsonify({
                'success': False,
                'error': result.get('error', 'Failed to evaluate pronunciation')
            }), 500

        # Extract evaluation results
        similarity_score = result['similarity_score']
        recognized_text = result['recognized_text']
        feedback = result['feedback']

        # Determine if user passed based on threshold
        passed = similarity_score >= evaluation_threshold

        # Save review to database
        conn = get_db_connection()
        cur = conn.cursor()

        try:
            # Get or create saved_word entry
            cur.execute("""
                INSERT INTO saved_words (user_id, word, learning_language, native_language)
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (user_id, word, learning_language, native_language)
                DO UPDATE SET created_at = saved_words.created_at
                RETURNING id
            """, (user_id, word, learning_language, native_language))

            word_info = cur.fetchone()
            word_id = word_info['id']

            # Calculate next review date based on Fibonacci spaced repetition
            # Get user's review history for this word
            cur.execute("""
                SELECT response
                FROM reviews
                WHERE user_id = %s AND word_id = %s
                ORDER BY reviewed_at DESC
            """, (user_id, word_id))

            review_history = [r['response'] for r in cur.fetchall()]

            # Calculate consecutive correct answers
            consecutive_correct = 0
            for response in review_history:
                if response:
                    consecutive_correct += 1
                else:
                    break

            # Fibonacci intervals in days: 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89
            fib_intervals = [1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89]

            if passed:
                # User passed - advance to next Fibonacci interval
                next_interval_index = min(consecutive_correct, len(fib_intervals) - 1)
                interval_days = fib_intervals[next_interval_index]
            else:
                # User failed - reset to 1 day
                interval_days = 1

            # Save review record
            cur.execute("""
                INSERT INTO reviews (
                    user_id,
                    word_id,
                    response,
                    question_type,
                    reviewed_at,
                    next_review_date
                )
                VALUES (
                    %s, %s, %s, %s,
                    CURRENT_TIMESTAMP,
                    CURRENT_TIMESTAMP + INTERVAL '%s days'
                )
                RETURNING id
            """, (user_id, word_id, passed, 'pronounce_sentence', interval_days))

            review_id = cur.fetchone()['id']

            conn.commit()
            logger.info(f"Saved pronunciation review for word '{word}' (user: {user_id}, passed: {passed}, score: {similarity_score:.2f})")

        except Exception as db_error:
            conn.rollback()
            logger.error(f"Database error in pronunciation review: {db_error}", exc_info=True)
            raise

        finally:
            cur.close()
            conn.close()

        # Return evaluation results
        return jsonify({
            'success': True,
            'passed': passed,
            'similarity_score': similarity_score,
            'recognized_text': recognized_text,
            'feedback': feedback,
            'evaluation_threshold': evaluation_threshold,
            'review_id': review_id,
            'next_interval_days': interval_days
        }), 200

    except Exception as e:
        logger.error(f"Error in submit_pronunciation_review: {str(e)}", exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500