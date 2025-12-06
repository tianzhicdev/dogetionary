"""
LLM Completion Utility

Centralized utility for making LLM completion API calls.
Supports multiple providers: OpenAI (gpt-5-nano, gpt-4o-mini) and Groq (llama-4-scout).
"""

import logging
import os
import time
import openai
from typing import Dict, List, Any, Optional
from middleware.metrics import (
    llm_calls_total,
    llm_request_duration_seconds,
    llm_tokens_total,
    llm_cost_usd_total,
    llm_errors_total,
    estimate_cost
)
from config.config import GROQ_TO_OPENAI_FALLBACK

logger = logging.getLogger(__name__)

# Try to import Groq, but make it optional
try:
    from groq import Groq
    GROQ_AVAILABLE = True
except ImportError:
    GROQ_AVAILABLE = False
    logger.warning("Groq SDK not installed. Install with: pip install groq")

# Model to provider mapping - easily extensible
MODEL_PROVIDER_MAP = {
    # Groq models
    "llama-4-scout": "groq",
    "llama-3.3-70b-versatile": "groq",
    "llama-3.1-70b-versatile": "groq",
    "mixtral-8x7b-32768": "groq",
    "gemma2-9b-it": "groq",
    "meta-llama/llama-4-scout-17b-16e-instruct": "groq",

    # OpenAI models (default)
    "gpt-5-nano": "openai",
    "gpt-4o": "openai",
    "gpt-4o-mini": "openai",
    "gpt-4-turbo": "openai",
    "gpt-3.5-turbo": "openai",
}

def get_provider_for_model(model_name: str) -> str:
    """
    Determine the provider for a given model name.
    Returns 'openai' as default if model is not in the map.
    """
    return MODEL_PROVIDER_MAP.get(model_name, "openai")


def get_fallback_model(groq_model: str) -> Optional[str]:
    """
    Get OpenAI fallback model for a Groq model.
    Returns None if no fallback is configured.
    """
    return GROQ_TO_OPENAI_FALLBACK.get(groq_model)


def llm_completion(
    messages: List[Dict[str, str]],
    model_name: str,
    response_format: Optional[Dict[str, Any]] = None,
    temperature: float = 1.0,
    max_tokens: Optional[int] = None,
    max_completion_tokens: Optional[int] = None,
    _is_fallback_attempt: bool = False
) -> Optional[str]:
    """
    Make an LLM completion API call with standardized error handling.
    Supports multiple providers: OpenAI and Groq (auto-detected based on model name).

    Args:
        messages: List of message dicts with 'role' and 'content' keys
        model_name: Model to use - provider is auto-detected from MODEL_PROVIDER_MAP
            - OpenAI: 'gpt-5-nano', 'gpt-4o-mini', etc.
            - Groq: 'llama-4-scout', 'mixtral-8x7b-32768', etc.
        response_format: Optional response format specification:
            - {"type": "json_object"} for flexible JSON mode
            - {"type": "json_schema", "json_schema": {...}} for strict schema validation
        temperature: Sampling temperature (default: 1.0)
        max_tokens: (Deprecated) Maximum tokens in response - use max_completion_tokens instead
        max_completion_tokens: Maximum tokens in completion (preferred for newer models)

    Returns:
        Response content as string, or None if the call fails

    Example:
        >>> messages = [
        ...     {"role": "system", "content": "You are a helpful assistant."},
        ...     {"role": "user", "content": "Say hello"}
        ... ]
        >>> response = llm_completion(messages, "gpt-5-nano")
        >>> print(response)
        "Hello! How can I help you today?"

        >>> # With JSON schema
        >>> schema = {
        ...     "type": "json_schema",
        ...     "json_schema": {
        ...         "name": "greeting",
        ...         "strict": True,
        ...         "schema": {
        ...             "type": "object",
        ...             "properties": {"message": {"type": "string"}},
        ...             "required": ["message"],
        ...             "additionalProperties": False
        ...         }
        ...     }
        ... }
        >>> response = llm_completion(messages, "gpt-5-nano", response_format=schema)
        >>> print(response)
        '{"message": "Hello! How can I help you today?"}'
    """
    # Start timing for metrics
    start_time = time.time()
    provider = None

    try:
        # Auto-detect provider based on model name
        provider = get_provider_for_model(model_name)

        # Select provider and initialize client
        if provider == "groq":
            if not GROQ_AVAILABLE:
                logger.error("Groq SDK not available. Install with: pip install groq")
                # Track error
                llm_calls_total.labels(provider='groq', model=model_name, status='error').inc()
                llm_errors_total.labels(provider='groq', model=model_name, error_type='sdk_unavailable').inc()
                return None
            client = Groq(api_key=os.getenv("GROQ_API_KEY"))
            logger.debug(f"Auto-detected Groq provider for model={model_name}")
        else:  # default to openai
            client = openai.OpenAI()
            logger.debug(f"Auto-detected OpenAI provider for model={model_name}")

        # Build API call parameters
        params = {
            "model": model_name,
            "messages": messages,
            "temperature": temperature
        }

        # Add optional parameters
        if response_format is not None:
            params["response_format"] = response_format

        # Prefer max_completion_tokens for newer models, fall back to max_tokens for compatibility
        if max_completion_tokens is not None:
            params["max_completion_tokens"] = max_completion_tokens
        elif max_tokens is not None:
            params["max_tokens"] = max_tokens

        # Make the API call
        logger.debug(f"Making LLM completion call with provider={provider}, model={model_name}, response_format={response_format is not None}")
        response = client.chat.completions.create(**params)

        # Calculate duration
        duration = time.time() - start_time

        # Extract content
        content = response.choices[0].message.content

        if not content:
            logger.error(f"{provider.upper()} returned empty content. Model: {model_name}, Response: {response}")
            # Track as error - empty response
            llm_calls_total.labels(provider=provider, model=model_name, status='error').inc()
            llm_errors_total.labels(provider=provider, model=model_name, error_type='empty_response').inc()
            llm_request_duration_seconds.labels(provider=provider, model=model_name).observe(duration)
            return None

        # Track successful call metrics
        llm_calls_total.labels(provider=provider, model=model_name, status='success').inc()
        llm_request_duration_seconds.labels(provider=provider, model=model_name).observe(duration)

        # Track token usage if available
        if hasattr(response, 'usage') and response.usage:
            prompt_tokens = getattr(response.usage, 'prompt_tokens', 0)
            completion_tokens = getattr(response.usage, 'completion_tokens', 0)

            if prompt_tokens > 0:
                llm_tokens_total.labels(provider=provider, model=model_name, type='prompt').inc(prompt_tokens)
            if completion_tokens > 0:
                llm_tokens_total.labels(provider=provider, model=model_name, type='completion').inc(completion_tokens)

            # Estimate and track cost
            cost = estimate_cost(provider, model_name, response.usage)
            if cost > 0:
                llm_cost_usd_total.labels(provider=provider, model=model_name).inc(cost)
                logger.debug(f"LLM call cost: ${cost:.6f} (provider={provider}, model={model_name}, prompt={prompt_tokens}, completion={completion_tokens})")

        return content.strip()

    except openai.APIError as e:
        duration = time.time() - start_time
        error_type = type(e).__name__
        logger.error(f"OpenAI API error: {e}", exc_info=True)

        # Track error metrics
        if provider:
            llm_calls_total.labels(provider=provider, model=model_name, status='error').inc()
            llm_request_duration_seconds.labels(provider=provider, model=model_name).observe(duration)
            llm_errors_total.labels(provider=provider, model=model_name, error_type=error_type).inc()

        return None
    except Exception as e:
        duration = time.time() - start_time
        error_type = type(e).__name__
        logger.error(f"Unexpected error in llm_completion (provider={provider}): {e}", exc_info=True)

        # Track error metrics
        if provider:
            llm_calls_total.labels(provider=provider, model=model_name, status='error').inc()
            llm_request_duration_seconds.labels(provider=provider, model=model_name).observe(duration)
            llm_errors_total.labels(provider=provider, model=model_name, error_type=error_type).inc()

        # Attempt fallback to OpenAI if this is a Groq over-capacity error
        if (provider == "groq" and
            not _is_fallback_attempt):

            fallback_model = get_fallback_model(model_name)
            if fallback_model:
                logger.warning(f"Groq over capacity, falling back from {model_name} to {fallback_model}")

                # Retry with OpenAI fallback model (only once)
                return llm_completion(
                    messages=messages,
                    model_name=fallback_model,
                    response_format=response_format,
                    temperature=temperature,
                    max_tokens=max_tokens,
                    max_completion_tokens=max_completion_tokens,
                    _is_fallback_attempt=True
                )
            else:
                logger.warning(f"Groq over capacity but no fallback configured for {model_name}")

        return None
