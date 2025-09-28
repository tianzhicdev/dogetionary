import logging
import sys
import json
import time
import os
from flask import request, g, current_app
from logging.handlers import RotatingFileHandler

def setup_logging(app):
    """Configure application logging"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    app.logger.setLevel(logging.INFO)

    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
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

        # Add rotating file handler
        file_handler = RotatingFileHandler(
            f'{logs_dir}/app.log',
            maxBytes=10*1024*1024,  # 10MB
            backupCount=5
        )
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
        app.logger.addHandler(file_handler)

        # Force a log entry to test file handler
        app.logger.info("File handler test - this should appear in app.log")

        app.logger.info("=== DOGETIONARY REFACTORED LOGGING INITIALIZED (Console + File) ===")
    except Exception as e:
        app.logger.info(f"=== DOGETIONARY REFACTORED LOGGING INITIALIZED (Console only - File error: {e}) ===")

    app.logger.info("=== DOGETIONARY REFACTORED LOGGING INITIALIZED ===")

def log_request_info():
    """Log all incoming requests with full details"""
    g.start_time = time.time()

    # Log request details
    request_data = {
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