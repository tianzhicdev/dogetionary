"""
Global error handlers for Flask application.
Logs all unhandled exceptions and HTTP errors.
"""
from flask import jsonify, request
import traceback
import logging

logger = logging.getLogger(__name__)


def register_error_handlers(app):
    """Register global error handlers for the Flask app."""

    @app.errorhandler(Exception)
    def handle_exception(e):
        """Handle all unhandled exceptions."""
        # Log full traceback with context
        app.logger.error(
            f"Unhandled exception: {str(e)}\n"
            f"Endpoint: {request.method} {request.path}\n"
            f"User-Agent: {request.headers.get('User-Agent', 'N/A')}\n"
            f"Remote-Addr: {request.remote_addr}\n"
            f"Args: {dict(request.args)}\n"
            f"Traceback:\n{traceback.format_exc()}"
        )

        # Return generic error to client
        return jsonify({
            "error": "Internal server error",
            "message": str(e) if app.debug else "An error occurred"
        }), 500

    @app.errorhandler(404)
    def not_found(e):
        """Handle 404 Not Found errors."""
        app.logger.warning(
            f"404 Not Found: {request.method} {request.path} "
            f"from {request.remote_addr}"
        )
        return jsonify({
            "error": "Not found",
            "message": f"The requested URL {request.path} was not found"
        }), 404

    @app.errorhandler(400)
    def bad_request(e):
        """Handle 400 Bad Request errors."""
        app.logger.warning(
            f"400 Bad Request: {request.method} {request.path} - {str(e)}"
        )
        return jsonify({
            "error": "Bad request",
            "message": str(e)
        }), 400

    @app.errorhandler(401)
    def unauthorized(e):
        """Handle 401 Unauthorized errors."""
        app.logger.warning(
            f"401 Unauthorized: {request.method} {request.path}"
        )
        return jsonify({
            "error": "Unauthorized",
            "message": "Authentication required"
        }), 401

    @app.errorhandler(403)
    def forbidden(e):
        """Handle 403 Forbidden errors."""
        app.logger.warning(
            f"403 Forbidden: {request.method} {request.path}"
        )
        return jsonify({
            "error": "Forbidden",
            "message": "Access denied"
        }), 403

    @app.errorhandler(405)
    def method_not_allowed(e):
        """Handle 405 Method Not Allowed errors."""
        app.logger.warning(
            f"405 Method Not Allowed: {request.method} {request.path}"
        )
        return jsonify({
            "error": "Method not allowed",
            "message": f"Method {request.method} not allowed for this endpoint"
        }), 405

    app.logger.info("✅ Global error handlers registered")
