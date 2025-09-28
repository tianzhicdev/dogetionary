from flask import Blueprint
from handlers.analytics import track_user_action, get_analytics_data

analytics_bp = Blueprint('analytics', __name__)

analytics_bp.route('/track', methods=['POST'])(track_user_action)
analytics_bp.route('/data', methods=['GET'])(get_analytics_data)