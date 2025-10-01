from flask import Blueprint
from handlers.users import handle_user_preferences, get_supported_languages
from handlers.reads import get_leaderboard
from handlers.pronunciation import (
    practice_pronunciation, get_pronunciation_history, get_pronunciation_stats
)
from handlers.actions import submit_feedback

users_bp = Blueprint('users', __name__)

# User preferences
users_bp.route('/<user_id>/preferences', methods=['GET', 'POST'])(handle_user_preferences)

# Languages
users_bp.route('/languages', methods=['GET'])(get_supported_languages)

# Leaderboard
users_bp.route('/leaderboard', methods=['GET'])(get_leaderboard)

# Pronunciation
users_bp.route('/pronunciation/practice', methods=['POST'])(practice_pronunciation)
users_bp.route('/pronunciation/history', methods=['GET'])(get_pronunciation_history)
users_bp.route('/pronunciation/stats', methods=['GET'])(get_pronunciation_stats)

# Feedback
users_bp.route('/feedback', methods=['POST'])(submit_feedback)