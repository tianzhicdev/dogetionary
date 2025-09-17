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
        logger.error(f"Error in track_user_action: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

def get_analytics_data():
    """
    GET /analytics/data
    Get analytics data for dashboard
    """
    try:
        days = int(request.args.get('days', 7))
        user_id = request.args.get('user_id')

        response = {}

        # Daily action counts
        daily_counts = analytics_service.get_daily_action_counts(days)
        response['daily_counts'] = []

        for row in daily_counts:
            response['daily_counts'].append({
                'date': row['action_date'].isoformat(),
                'action': row['action'],
                'category': row['category'],
                'count': row['count']
            })

        # User actions if user_id provided
        if user_id:
            user_actions = analytics_service.get_user_actions(user_id)
            response['user_actions'] = []

            for row in user_actions:
                response['user_actions'].append({
                    'timestamp': row['created_at'].isoformat(),
                    'action': row['action'],
                    'category': row['category'],
                    'metadata': row['metadata'],
                    'session_id': row['session_id'],
                    'platform': row['platform'],
                    'app_version': row['app_version']
                })

        # Available users
        users = analytics_service.get_all_users()
        response['users'] = []

        for row in users:
            response['users'].append({
                'user_id': row['user_id'],
                'user_name': row['user_name']
            })

        return jsonify(response)

    except Exception as e:
        logger.error(f"Error in get_analytics_data: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500