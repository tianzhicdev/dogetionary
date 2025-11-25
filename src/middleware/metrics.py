"""
Prometheus metrics for monitoring API and LLM performance.
"""
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from flask import Response
import time
import functools
import logging

logger = logging.getLogger(__name__)

# ============================================================================
# HTTP API METRICS
# ============================================================================

http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status_code']
)

http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint'],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)
)

http_requests_in_flight = Gauge(
    'http_requests_in_flight',
    'Number of HTTP requests currently being processed',
    ['method', 'endpoint']
)

# ============================================================================
# LLM METRICS
# ============================================================================

llm_calls_total = Counter(
    'llm_calls_total',
    'Total LLM API calls',
    ['provider', 'model', 'status']  # status: success|error
)

llm_request_duration_seconds = Histogram(
    'llm_request_duration_seconds',
    'LLM request duration in seconds',
    ['provider', 'model'],
    buckets=(0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0)
)

llm_tokens_total = Counter(
    'llm_tokens_total',
    'Total LLM tokens used',
    ['provider', 'model', 'type']  # type: prompt|completion
)

llm_cost_usd_total = Counter(
    'llm_cost_usd_total',
    'Estimated LLM cost in USD',
    ['provider', 'model']
)

llm_errors_total = Counter(
    'llm_errors_total',
    'Total LLM errors',
    ['provider', 'model', 'error_type']
)

# ============================================================================
# BUSINESS METRICS
# ============================================================================

reviews_total = Counter(
    'reviews_total',
    'Total word reviews',
    ['result']  # result: correct|incorrect
)

words_saved_total = Counter(
    'words_saved_total',
    'Total words saved by users',
    ['language']
)

schedules_created_total = Counter(
    'schedules_created_total',
    'Total study schedules created',
    ['test_type']
)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def track_llm_call(provider, model):
    """Decorator to track LLM call metrics."""
    def decorator(f):
        @functools.wraps(f)
        def wrapper(*args, **kwargs):
            start_time = time.time()

            try:
                result = f(*args, **kwargs)

                # Record success
                duration = time.time() - start_time
                llm_calls_total.labels(
                    provider=provider,
                    model=model,
                    status='success'
                ).inc()
                llm_request_duration_seconds.labels(
                    provider=provider,
                    model=model
                ).observe(duration)

                # Try to extract token usage if available
                if hasattr(result, 'usage'):
                    llm_tokens_total.labels(
                        provider=provider,
                        model=model,
                        type='prompt'
                    ).inc(result.usage.prompt_tokens)
                    llm_tokens_total.labels(
                        provider=provider,
                        model=model,
                        type='completion'
                    ).inc(result.usage.completion_tokens)

                    # Estimate cost (rough estimates)
                    cost = estimate_cost(provider, model, result.usage)
                    llm_cost_usd_total.labels(
                        provider=provider,
                        model=model
                    ).inc(cost)

                return result

            except Exception as e:
                duration = time.time() - start_time
                error_type = type(e).__name__

                llm_calls_total.labels(
                    provider=provider,
                    model=model,
                    status='error'
                ).inc()
                llm_errors_total.labels(
                    provider=provider,
                    model=model,
                    error_type=error_type
                ).inc()
                llm_request_duration_seconds.labels(
                    provider=provider,
                    model=model
                ).observe(duration)

                raise

        return wrapper
    return decorator


def estimate_cost(provider, model, usage):
    """Estimate LLM API cost in USD."""
    # Rough pricing (as of Nov 2025, update as needed)
    PRICING = {
        'openai': {
            'gpt-4o': {'prompt': 0.000005, 'completion': 0.000015},  # $5/$15 per 1M tokens
            'gpt-4o-mini': {'prompt': 0.00000015, 'completion': 0.0000006},  # $0.15/$0.60 per 1M
            'gpt-3.5-turbo': {'prompt': 0.0000005, 'completion': 0.0000015},
        },
        'groq': {
            'llama-3.1-70b-versatile': {'prompt': 0.00000059, 'completion': 0.00000079},
            'llama-3.1-8b-instant': {'prompt': 0.00000005, 'completion': 0.00000008},
        }
    }

    try:
        pricing = PRICING.get(provider, {}).get(model, {})
        if not pricing:
            return 0.0

        prompt_cost = usage.prompt_tokens * pricing.get('prompt', 0)
        completion_cost = usage.completion_tokens * pricing.get('completion', 0)

        return prompt_cost + completion_cost
    except Exception:
        return 0.0


def metrics_endpoint():
    """Expose metrics in Prometheus format."""
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)
