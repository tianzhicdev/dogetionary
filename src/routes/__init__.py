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

    # Register v3 API
    try:
        import sys
        import os
        # Add parent directory to path to import app_v3
        sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
        from app_v3 import v3_api
        app.register_blueprint(v3_api)  # V3 API with /v3 prefix
        app.logger.info("✅ V3 API registered successfully")
    except Exception as e:
        app.logger.error(f"❌ Failed to register V3 API: {e}")
        import traceback
        app.logger.error(traceback.format_exc())