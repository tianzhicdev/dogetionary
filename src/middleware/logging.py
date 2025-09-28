import logging
import sys
import json
import time
from flask import request, g, current_app

def setup_logging(app):
    """Configure application logging"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    app.logger.setLevel(logging.INFO)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s'))
    app.logger.addHandler(handler)

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