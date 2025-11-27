from flask import Blueprint
from handlers.actions import get_next_review_word, submit_review
from handlers.words import get_next_review_word_v2
from handlers.reads import (
    get_due_counts, get_review_stats, get_forgetting_curve,
    get_review_progress_stats
)

reviews_bp = Blueprint('reviews', __name__)

# Core review functionality
reviews_bp.route('/next', methods=['GET'])(get_next_review_word)
reviews_bp.route('/v2/next', methods=['GET'])(get_next_review_word_v2)
reviews_bp.route('/submit', methods=['POST'])(submit_review)

# Review statistics
reviews_bp.route('/due_counts', methods=['GET'])(get_due_counts)
reviews_bp.route('/stats', methods=['GET'])(get_review_stats)
reviews_bp.route('/progress_stats', methods=['GET'])(get_review_progress_stats)

# Word-specific stats
reviews_bp.route('/words/<int:word_id>/forgetting-curve', methods=['GET'])(get_forgetting_curve)