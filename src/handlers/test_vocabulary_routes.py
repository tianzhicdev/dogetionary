"""
Register test vocabulary routes in the Flask app
Add this to your app_refactored.py or main app file
"""

def register_test_vocabulary_routes(app):
    """
    Register all test vocabulary related routes
    """
    from handlers.test_vocabulary import (
        update_test_settings,
        get_test_settings,
        add_daily_test_words,
        get_test_vocabulary_stats
    )

    # Test preparation settings
    app.route('/api/test-prep/settings', methods=['PUT'])(update_test_settings)
    app.route('/api/test-prep/settings', methods=['GET'])(get_test_settings)

    # Daily words management
    app.route('/api/test-prep/add-words', methods=['POST'])(add_daily_test_words)

    # Statistics
    app.route('/api/test-prep/stats', methods=['GET'])(get_test_vocabulary_stats)

    return app

# Add this to your app_refactored.py after other route registrations:
# register_test_vocabulary_routes(app)