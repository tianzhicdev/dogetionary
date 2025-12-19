"""
Analytics API handlers
"""

from flask import request, jsonify
from services.analytics_service import analytics_service
import logging

logger = logging.getLogger(__name__)

def track_user_action():
    """
    POST /analytics/track
    Track a user action
    """
    try:
        data = request.get_json()

        if not data:
            return jsonify({'error': 'No data provided'}), 400

        required_fields = ['user_id', 'action']
        for field in required_fields:
            if field not in data:
                return jsonify({'error': f'Missing required field: {field}'}), 400

        user_id = data['user_id']
        action = data['action']
        metadata = data.get('metadata', {})
        session_id = data.get('session_id')
        platform = data.get('platform', 'ios')
        app_version = data.get('app_version')

        success = analytics_service.track_action(
            user_id=user_id,
            action=action,
            metadata=metadata,
            session_id=session_id,
            platform=platform,
            app_version=app_version
        )

        if success:
            return jsonify({'success': True, 'message': 'Action tracked'})
        else:
            return jsonify({'error': 'Failed to track action'}), 500

    except Exception as e:
        logger.error(f"Error in track_user_action: {str(e)}", exc_info=True)
        return jsonify({'error': 'Internal server error'}), 500
