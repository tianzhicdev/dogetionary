# Backward Compatibility Handlers
# These handlers restore endpoints that existed in commit 33c566e but were removed/merged
# They ensure deployed iOS apps continue to work while new versions can use v3 endpoints

from flask import request, jsonify
import json
import logging
from handlers.words import get_word_definition, get_illustration
from handlers.reads import get_review_progress_stats
from handlers.words import get_next_review_word_v2

logger = logging.getLogger(__name__)

def get_word_definition_v2():
    """
    Backward compatibility for /v2/word endpoint
    Redirects to current merged word definition endpoint
    """
    logger.info("V2 word endpoint called - redirecting to merged endpoint")
    return get_word_definition()

def get_review_stats():
    """
    Backward compatibility for /reviews/stats endpoint
    Returns empty stats or redirects to progress_stats
    """
    logger.info("Legacy review stats endpoint called")
    try:
        # For backward compatibility, return the progress stats
        return get_review_progress_stats()
    except Exception as e:
        logger.error(f"Error in compatibility review stats: {str(e)}")
        # Return minimal compatible response
        return jsonify({
            "total_reviews": 0,
            "average_score": 0.0,
            "streak_days": 0
        })

def generate_illustration():
    """
    Backward compatibility for /generate-illustration endpoint
    Redirects to merged illustration endpoint with POST method
    """
    logger.info("Legacy generate illustration endpoint called")
    # The current get_illustration handles both GET and POST
    return get_illustration()

def get_illustration_legacy():
    """
    Backward compatibility for /illustration endpoint
    Redirects to merged illustration endpoint with GET method
    """
    logger.info("Legacy get illustration endpoint called")
    # The current get_illustration handles both GET and POST
    return get_illustration()