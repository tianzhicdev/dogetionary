from flask import Blueprint
from handlers.words import (
    get_word_definition, get_word_definition_v2, get_word_details,
    get_saved_words, get_audio, generate_illustration, get_illustration,
    generate_word_definition, is_word_saved
)
from handlers.actions import save_word, delete_saved_word, delete_saved_word_v2
from handlers.static_site import get_all_words, get_words_summary, get_featured_words

words_bp = Blueprint('words', __name__)

# Word definitions
words_bp.route('/word', methods=['GET'])(get_word_definition)
words_bp.route('/v2/word', methods=['GET'])(get_word_definition_v2)
words_bp.route('/words/<int:word_id>/details', methods=['GET'])(get_word_details)

# Word management
words_bp.route('/save', methods=['POST'])(save_word)
words_bp.route('/unsave', methods=['POST'])(delete_saved_word)
words_bp.route('/v2/unsave', methods=['POST'])(delete_saved_word_v2)
words_bp.route('/saved_words', methods=['GET'])(get_saved_words)
words_bp.route('/v3/is-word-saved', methods=['GET'])(is_word_saved)

# Media
words_bp.route('/audio/<path:text>/<language>')(get_audio)
words_bp.route('/generate-illustration', methods=['POST'])(generate_illustration)
words_bp.route('/illustration', methods=['GET'])(get_illustration)

# Static site endpoints
words_bp.route('/words', methods=['GET'])(get_all_words)
words_bp.route('/words/summary', methods=['GET'])(get_words_summary)
words_bp.route('/words/featured', methods=['GET'])(get_featured_words)

# Bulk operations
words_bp.route('/api/words/generate', methods=['POST'])(generate_word_definition)