from flask import Blueprint

def register_blueprints(app):
    """Register all application blueprints"""

    # Import blueprints
    from .words import words_bp
    from .reviews import reviews_bp
    from .users import users_bp
    from .admin import admin_bp
    from .analytics import analytics_bp
    from .test_prep import test_prep_bp

    # Register blueprints
    app.register_blueprint(words_bp)
    app.register_blueprint(reviews_bp, url_prefix='/reviews')
    app.register_blueprint(users_bp, url_prefix='/users')
    app.register_blueprint(admin_bp)
    app.register_blueprint(analytics_bp, url_prefix='/analytics')
    app.register_blueprint(test_prep_bp, url_prefix='/api/test-prep')