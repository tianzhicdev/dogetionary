from flask import Blueprint
from handlers.users import handle_user_preferences, get_supported_languages
from handlers.reads import get_leaderboard, get_leaderboard_v2
from handlers.pronunciation import practice_pronunciation
from handlers.actions import submit_feedback

users_bp = Blueprint('users', __name__)

# User preferences
users_bp.route('/<user_id>/preferences', methods=['GET', 'POST'])(handle_user_preferences)

# Languages
users_bp.route('/languages', methods=['GET'])(get_supported_languages)

# Leaderboard
users_bp.route('/leaderboard', methods=['GET'])(get_leaderboard)
users_bp.route('/leaderboard-score', methods=['GET'])(get_leaderboard_v2)

# Pronunciation
users_bp.route('/pronunciation/practice', methods=['POST'])(practice_pronunciation)

# Feedback
users_bp.route('/feedback', methods=['POST'])(submit_feedback)