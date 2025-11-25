"""
Flask middleware to automatically track all HTTP requests.
"""
from flask import request, g
import time
from middleware.metrics import (
    http_requests_total,
    http_request_duration_seconds,
    http_requests_in_flight
)


def track_request_start():
    """Track request start time and in-flight count."""
    g.start_time = time.time()

    # Get endpoint and method
    endpoint = request.endpoint or 'unknown'
    method = request.method

    # Increment in-flight gauge
    http_requests_in_flight.labels(
        method=method,
        endpoint=endpoint
    ).inc()


def track_request_end(response):
    """Track request completion metrics."""
    duration = time.time() - g.get('start_time', time.time())

    endpoint = request.endpoint or 'unknown'
    method = request.method
    status_code = response.status_code

    # Record metrics
    http_requests_total.labels(
        method=method,
        endpoint=endpoint,
        status_code=status_code
    ).inc()

    http_request_duration_seconds.labels(
        method=method,
        endpoint=endpoint
    ).observe(duration)

    # Decrement in-flight gauge
    http_requests_in_flight.labels(
        method=method,
        endpoint=endpoint
    ).dec()

    return response
