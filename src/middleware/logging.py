import logging
import sys
import json
import time
import os
import uuid
from flask import request, g, current_app, has_request_context
from logging.handlers import RotatingFileHandler
from pythonjsonlogger import jsonlogger


class LokiJsonFormatter(jsonlogger.JsonFormatter):
    """Custom JSON formatter with Loki-friendly labels"""

    def add_fields(self, log_record, record, message_dict):
        super(LokiJsonFormatter, self).add_fields(log_record, record, message_dict)

        # Add Loki labels
        log_record['app'] = 'dogetionary'
        log_record['service'] = 'backend'
        log_record['level'] = record.levelname
        log_record['logger'] = record.name
        log_record['file'] = record.pathname
        log_record['line'] = record.lineno

        # Add request context if available (only when inside a request context)
        if has_request_context():
            if hasattr(g, 'request_id'):
                log_record['request_id'] = g.request_id
            if hasattr(g, 'user_id'):
                log_record['user_id'] = g.user_id
            if request and request.endpoint:
                log_record['endpoint'] = request.endpoint
                log_record['method'] = request.method
                log_record['path'] = request.path


def setup_logging(app):
    """Configure application logging"""
    # Create JSON formatter for all handlers
    json_formatter = LokiJsonFormatter(
        '%(asctime)s %(name)s %(levelname)s %(pathname)s %(lineno)d %(message)s'
    )

    # Configure ROOT logger to use JSON formatting
    # This ensures ALL child loggers (handlers.*, services.*, etc.) also get JSON formatting
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)

    # Remove any existing handlers from root logger (from basicConfig)
    root_logger.handlers.clear()

    # Add JSON console handler to root logger
    root_console_handler = logging.StreamHandler(sys.stdout)
    root_console_handler.setFormatter(json_formatter)
    root_console_handler.setLevel(logging.INFO)
    root_logger.addHandler(root_console_handler)

    # Configure app.logger specifically
    app.logger.setLevel(logging.INFO)
    app.logger.propagate = False  # Don't propagate to root to avoid duplicate logs

    # Console handler for app.logger
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(json_formatter)
    app.logger.addHandler(console_handler)

    # File handler
    try:
        # Create logs directory if it doesn't exist
        logs_dir = '/app/logs'
        os.makedirs(logs_dir, exist_ok=True)

        # Test write permissions
        test_file = f'{logs_dir}/test.log'
        with open(test_file, 'w') as f:
            f.write('test\n')
        os.remove(test_file)

        # Add rotating file handler for ALL logs (INFO+) to ROOT logger
        # This captures logs from ALL child loggers (handlers.*, services.*, etc.)
        root_file_handler = RotatingFileHandler(
            f'{logs_dir}/app.log',
            maxBytes=100*1024*1024,  # 100MB per file
            backupCount=50  # 50 backups × 100MB = 5GB total
        )
        root_file_handler.setLevel(logging.INFO)
        root_file_handler.setFormatter(json_formatter)
        root_logger.addHandler(root_file_handler)

        # Add separate rotating file handler for ERRORS ONLY to ROOT logger
        # This captures ERROR logs from ALL child loggers
        root_error_handler = RotatingFileHandler(
            f'{logs_dir}/error.log',
            maxBytes=50*1024*1024,  # 50MB per file
            backupCount=20  # 20 backups × 50MB = 1GB total
        )
        root_error_handler.setLevel(logging.ERROR)  # Only ERROR and CRITICAL
        root_error_handler.setFormatter(json_formatter)
        root_logger.addHandler(root_error_handler)

        # Also add file handlers to app.logger (for app-specific logs)
        app_file_handler = RotatingFileHandler(
            f'{logs_dir}/app.log',
            maxBytes=100*1024*1024,
            backupCount=50
        )
        app_file_handler.setLevel(logging.INFO)
        app_file_handler.setFormatter(json_formatter)
        app.logger.addHandler(app_file_handler)

        app_error_handler = RotatingFileHandler(
            f'{logs_dir}/error.log',
            maxBytes=50*1024*1024,
            backupCount=20
        )
        app_error_handler.setLevel(logging.ERROR)
        app_error_handler.setFormatter(json_formatter)
        app.logger.addHandler(app_error_handler)

        # Force a log entry to test file handler
        app.logger.info("=== DOGETIONARY LOGGING INITIALIZED (Console + File + Error File) ===")
    except Exception as e:
        app.logger.info(f"=== DOGETIONARY LOGGING INITIALIZED (Console only - File error: {e}) ===")

    app.logger.info("=== DOGETIONARY REFACTORED LOGGING INITIALIZED ===")

def log_request_info():
    """Log all incoming requests with full details"""
    g.start_time = time.time()

    # Use client-provided request ID if available (for request tracing),
    # otherwise generate a new one on the server
    g.request_id = request.headers.get('X-Request-ID', str(uuid.uuid4()))

    # Log request details
    request_data = {
        'request_id': g.request_id,
        'method': request.method,
        'url': request.url,
        'remote_addr': request.remote_addr,
        'user_agent': request.headers.get('User-Agent', ''),
        'content_type': request.headers.get('Content-Type', ''),
        'content_length': request.headers.get('Content-Length', ''),
        'headers': dict(request.headers),
        'args': dict(request.args),
    }

    # Only log request body for non-GET requests and if it's not too large
    if request.method != 'GET' and request.content_length and request.content_length < 10000:
        try:
            if request.is_json:
                request_data['json_body'] = request.get_json()
            elif request.form:
                request_data['form_data'] = dict(request.form)
            else:
                request_data['raw_body'] = request.get_data(as_text=True)[:1000]  # Limit to 1000 chars
        except Exception as e:
            request_data['body_error'] = str(e)

    current_app.logger.info(f"REQUEST: {json.dumps(request_data, default=str, indent=2)}")

def log_response_info(response):
    """Log all outgoing responses with full details"""
    duration = time.time() - getattr(g, 'start_time', time.time())

    response_data = {
        'request_id': getattr(g, 'request_id', 'unknown'),
        'status_code': response.status_code,
        'status': response.status,
        'content_type': response.content_type,
        'content_length': response.content_length,
        'headers': dict(response.headers),
        'duration_ms': round(duration * 1000, 2)
    }

    # Log response body if it's not too large and is text-based
    if response.content_length and response.content_length < 10000:
        try:
            if response.content_type and 'json' in response.content_type:
                response_data['json_body'] = response.get_json()
            elif response.content_type and response.content_type.startswith('text/'):
                response_data['text_body'] = response.get_data(as_text=True)[:1000]  # Limit to 1000 chars
        except Exception as e:
            response_data['body_error'] = str(e)

    current_app.logger.info(f"RESPONSE: {json.dumps(response_data, default=str, indent=2)}")

    return response


def log_error(logger, message, **context):
    """
    Consistently log errors with full context and stack trace.

    Args:
        logger: The logger instance to use
        message: Human-readable error message
        **context: Additional context fields (user_id, word, endpoint, etc.)

    Usage:
        from middleware.logging import log_error
        log_error(logger, "Failed to save word", user_id=user_id, word=word, language=language)
    """
    # Merge context with request context if available
    extra = dict(context)

    # Add request context automatically
    if hasattr(g, 'request_id'):
        extra['request_id'] = g.request_id
    if hasattr(g, 'user_id'):
        extra['user_id'] = g.user_id

    # Add current exception type if we're in an exception handler
    import sys
    exc_info = sys.exc_info()
    if exc_info[0] is not None:
        extra['error_type'] = exc_info[0].__name__
        extra['error_message'] = str(exc_info[1])

    # Log with full stack trace
    logger.error(message, extra=extra, exc_info=True)