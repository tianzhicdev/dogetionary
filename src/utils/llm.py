"""
LLM Completion Utility

Centralized utility for making LLM completion API calls.
Supports multiple providers: OpenAI (gpt-5-nano, gpt-4o-mini) and Groq (llama-4-scout).
"""

import json
import logging
import os
import time
import re
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
from config.config import GROQ_TO_OPENAI_FALLBACK, FALLBACK_CHAINS

logger = logging.getLogger(__name__)


# Removed clean_json_response() - JSON must be valid or fail to trigger fallback


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

    # OpenRouter models
    "google/gemini-2.0-flash-lite-001": "openrouter",
    "deepseek/deepseek-chat-v3.1": "openrouter",
    "qwen/qwen-2.5-7b-instruct": "openrouter",
    "mistralai/mistral-small": "openrouter",
    "openai/gpt-4o": "openrouter",

    # OpenAI models (default)
    "gpt-5-nano": "openai",
    "gpt-4o": "openai",
    "gpt-4o-mini": "openai",
    "gpt-4-turbo": "openai",
    "gpt-3.5-turbo": "openai",
}

# Models that support strict JSON Schema validation
# Reference: https://platform.openai.com/docs/guides/structured-outputs
MODELS_WITH_JSON_SCHEMA_SUPPORT = {
    # OpenAI models
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-5-nano",

    # Google models (via OpenRouter)
    "google/gemini-2.0-flash-lite-001",
    "google/gemini-2.0-flash-exp",
    "google/gemini-2.0-flash-thinking-exp-01-21",
}


def normalize_model_name(model_name: str) -> str:
    """
    Normalize model name for Prometheus labels.
    Converts slashes and hyphens to underscores and uses short names.

    Examples:
        "deepseek/deepseek-chat-v3.1" -> "deepseek_v3"
        "qwen/qwen-2.5-7b-instruct" -> "qwen25_7b"
        "gpt-4o-mini" -> "gpt4o_mini"
    """
    # Map full model names to short, normalized versions
    model_map = {
        "google/gemini-2.0-flash-lite-001": "gemini_2_0_flash_lite",
        "deepseek/deepseek-chat-v3.1": "deepseek_v3",
        "qwen/qwen-2.5-7b-instruct": "qwen25_7b",
        "mistralai/mistral-small": "mistral_small",
        "openai/gpt-4o": "gpt4o",
        "llama-3.3-70b-versatile": "llama33_70b",
        "llama-3.1-70b-versatile": "llama31_70b",
        "mixtral-8x7b-32768": "mixtral_8x7b",
        "gpt-4o": "gpt4o",
        "gpt-4o-mini": "gpt4o_mini",
        "gpt-4-turbo": "gpt4_turbo",
        "gpt-3.5-turbo": "gpt35_turbo",
    }

    # Return mapped name or fallback to replacing special chars
    return model_map.get(model_name, model_name.replace("/", "_").replace("-", "_").replace(".", "_"))

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


def get_fallback_chain(use_case: str) -> List[str]:
    """
    Get fallback chain for a specific use case.
    Returns list of model names to try in order.
    Falls back to 'general' chain if use_case not found.
    """
    return FALLBACK_CHAINS.get(use_case, FALLBACK_CHAINS.get('general', []))


def supports_json_schema(model_name: str) -> bool:
    """
    Check if a model supports strict JSON Schema validation.

    Args:
        model_name: Name of the model to check

    Returns:
        True if model supports JSON Schema, False otherwise
    """
    return model_name in MODELS_WITH_JSON_SCHEMA_SUPPORT


def get_response_format(
    model_name: str,
    schema_name: Optional[str] = None,
    fallback_to_json_object: bool = True
) -> Optional[Dict[str, Any]]:
    """
    Get appropriate response_format parameter based on model capabilities.

    Args:
        model_name: Name of the model to use
        schema_name: Name of the schema from config.json_schemas (e.g., 'pronunciation', 'mc_definition')
        fallback_to_json_object: If True, use json_object for models without schema support

    Returns:
        Response format dict, or None if no JSON formatting requested

    Example:
        >>> # For a model with schema support
        >>> get_response_format("gpt-4o", "pronunciation")
        {"type": "json_schema", "json_schema": {...}}

        >>> # For a model without schema support
        >>> get_response_format("deepseek/deepseek-chat-v3.1", "pronunciation")
        {"type": "json_object"}  # Falls back to loose JSON mode
    """
    if schema_name is None:
        return None

    # Import here to avoid circular dependency
    from config.json_schemas import get_schema

    if supports_json_schema(model_name):
        # Use strict JSON Schema
        schema = get_schema(schema_name)
        return {
            "type": "json_schema",
            "json_schema": schema
        }
    elif fallback_to_json_object:
        # Fall back to loose JSON mode
        logger.debug(f"Model {model_name} does not support JSON Schema, using json_object mode")
        return {"type": "json_object"}
    else:
        # No JSON formatting
        return None


# Removed validate_json_response() - JSON must be valid or fail to trigger fallback


def llm_completion_with_fallback(
    messages: List[Dict[str, str]],
    use_case: str,
    schema_name: str,
    temperature: float = 1.0,
    max_tokens: Optional[int] = None,
    max_completion_tokens: Optional[int] = None
) -> Optional[str]:
    """
    Make an LLM completion API call with multi-level fallback chain.
    Tries models in order defined by FALLBACK_CHAINS for the given use_case.

    Args:
        messages: List of message dicts with 'role' and 'content' keys
        use_case: Use case identifier (definition, question, pronunciation, etc.)
        schema_name: Name of JSON schema from config.json_schemas (REQUIRED)
                     Automatically selects json_schema or json_object based on model support
        temperature: Sampling temperature (default: 1.0)
        max_tokens: Maximum tokens in response (deprecated, use max_completion_tokens)
        max_completion_tokens: Maximum tokens in completion

    Returns:
        Response content as string, or None if all models in chain fail

    Example:
        >>> messages = [{"role": "user", "content": "Define 'hello'"}]
        >>> response = llm_completion_with_fallback(
        ...     messages, use_case="definition", schema_name="definition"
        ... )
        # Tries: gemini -> deepseek-v3 -> qwen -> gpt-4o-mini until one succeeds
        # Uses json_schema for supported models, json_object for others
    """
    chain = get_fallback_chain(use_case)

    if not chain:
        logger.error(f"No fallback chain configured for use_case={use_case}")
        return None

    logger.info(f"Starting fallback chain for use_case={use_case}, schema={schema_name}, models={chain}")

    for i, model_name in enumerate(chain):
        try:
            logger.info(f"Attempting model {i+1}/{len(chain)}: {model_name} for use_case={use_case}")

            # Auto-select response format based on model capabilities
            model_response_format = get_response_format(model_name, schema_name)

            result = llm_completion(
                messages=messages,
                model_name=model_name,
                use_case=use_case,
                response_format=model_response_format,
                temperature=temperature,
                max_tokens=max_tokens,
                max_completion_tokens=max_completion_tokens,
                _is_fallback_attempt=True  # Prevent nested fallback loops
            )

            if result:
                if i > 0:
                    logger.warning(f"Fallback to model {model_name} succeeded (fallback level {i}) for use_case={use_case}")
                else:
                    logger.info(f"Primary model {model_name} succeeded for use_case={use_case}")
                return result
            else:
                logger.warning(f"Model {model_name} returned None, trying next in chain (attempt {i+1}/{len(chain)})")

        except Exception as e:
            # Catch ANY exception and try next model
            # Log everything for debugging
            error_type = type(e).__name__
            error_msg = str(e)

            logger.warning(
                f"Model {model_name} failed with {error_type}: {error_msg}. "
                f"Trying next model in chain (attempt {i+1}/{len(chain)})",
                exc_info=True  # Include full stack trace
            )
            continue

    # All models failed
    logger.error(f"All models in fallback chain failed for use_case={use_case}, chain={chain}")
    return None


def llm_completion(
    messages: List[Dict[str, str]],
    model_name: str,
    use_case: str = "general",
    response_format: Optional[Dict[str, Any]] = None,
    temperature: float = 1.0,
    max_tokens: Optional[int] = None,
    max_completion_tokens: Optional[int] = None,
    _is_fallback_attempt: bool = False
) -> Optional[str]:
    """
    Make an LLM completion API call with standardized error handling.
    Supports multiple providers: OpenAI, Groq, and OpenRouter (auto-detected based on model name).

    Args:
        messages: List of message dicts with 'role' and 'content' keys
        model_name: Model to use - provider is auto-detected from MODEL_PROVIDER_MAP
            - OpenAI: 'gpt-5-nano', 'gpt-4o-mini', etc.
            - Groq: 'llama-4-scout', 'mixtral-8x7b-32768', etc.
            - OpenRouter: 'deepseek/deepseek-chat-v3.1', 'qwen/qwen-2.5-7b-instruct', etc.
        use_case: Use case identifier for metrics tracking (e.g., 'definition', 'question', 'pronunciation')
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

        # Normalize model name for metrics
        normalized_model = normalize_model_name(model_name)

        # Select provider and initialize client
        if provider == "groq":
            if not GROQ_AVAILABLE:
                logger.error("Groq SDK not available. Install with: pip install groq", exc_info=True)
                # Track error
                llm_calls_total.labels(provider='groq', model=normalized_model, use_case=use_case, status='error').inc()
                llm_errors_total.labels(provider='groq', model=normalized_model, use_case=use_case, error_type='sdk_unavailable').inc()
                return None
            client = Groq(api_key=os.getenv("GROQ_API_KEY"))
            logger.debug(f"Auto-detected Groq provider for model={model_name}")
        elif provider == "openrouter":
            # OpenRouter is OpenAI API-compatible, just different base URL
            client = openai.OpenAI(
                api_key=os.getenv("OPEN_ROUTER_KEY"),
                base_url="https://openrouter.ai/api/v1"
            )
            logger.debug(f"Auto-detected OpenRouter provider for model={model_name}")
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

        # Log which model was actually used and response details
        logger.info(f"LLM response received: provider={provider}, model={model_name}, use_case={use_case}, content_length={len(content) if content else 0}, duration={duration:.2f}s")

        # Log content preview for debugging (especially for JSON responses)
        if response_format is not None:
            logger.info(f"LLM content preview (first 500 chars): {content[:500] if content else 'EMPTY'}...")

        if not content:
            logger.error(f"{provider.upper()} returned empty content. Model: {model_name}, Response: {response}", exc_info=True)
            # Track as error - empty response
            llm_calls_total.labels(provider=provider, model=normalized_model, use_case=use_case, status='error').inc()
            llm_errors_total.labels(provider=provider, model=normalized_model, use_case=use_case, error_type='empty_response').inc()
            llm_request_duration_seconds.labels(provider=provider, model=normalized_model, use_case=use_case).observe(duration)
            return None

        # If JSON mode requested, validate JSON before returning
        # STRICT: Any invalid JSON fails immediately to trigger fallback
        if response_format and response_format.get("type") in ["json_object", "json_schema"]:
            try:
                # Validate that it's actually valid JSON (no cleanup, must be perfect)
                parsed = json.loads(content)

                # Additional type check: must be dict, not list or other types
                if not isinstance(parsed, dict):
                    logger.error(
                        f"JSON type validation failed for {model_name}: Expected dict, got {type(parsed).__name__}. "
                        f"Full content:\n{content}"
                    )
                    llm_calls_total.labels(provider=provider, model=normalized_model, use_case=use_case, status='error').inc()
                    llm_errors_total.labels(provider=provider, model=normalized_model, use_case=use_case, error_type='json_wrong_type').inc()
                    llm_request_duration_seconds.labels(provider=provider, model=normalized_model, use_case=use_case).observe(duration)
                    return None  # Fail to trigger fallback

                logger.debug(f"JSON validation passed for {model_name}")
            except json.JSONDecodeError as e:
                # JSON parsing failed - log raw output and fail to trigger fallback
                logger.error(
                    f"JSON parsing failed for {model_name}: {e.msg} at line {e.lineno} col {e.colno} (char {e.pos}). "
                    f"Raw LLM output:\n{content}"
                )
                # Track JSON validation error in metrics
                llm_calls_total.labels(provider=provider, model=normalized_model, use_case=use_case, status='error').inc()
                llm_errors_total.labels(provider=provider, model=normalized_model, use_case=use_case, error_type='json_parse_failed').inc()
                llm_request_duration_seconds.labels(provider=provider, model=normalized_model, use_case=use_case).observe(duration)
                return None  # Fail to trigger fallback

        # Track successful call metrics
        llm_calls_total.labels(provider=provider, model=normalized_model, use_case=use_case, status='success').inc()
        llm_request_duration_seconds.labels(provider=provider, model=normalized_model, use_case=use_case).observe(duration)

        # Track token usage if available
        if hasattr(response, 'usage') and response.usage:
            prompt_tokens = getattr(response.usage, 'prompt_tokens', 0)
            completion_tokens = getattr(response.usage, 'completion_tokens', 0)

            if prompt_tokens > 0:
                llm_tokens_total.labels(provider=provider, model=normalized_model, use_case=use_case, type='prompt').inc(prompt_tokens)
            if completion_tokens > 0:
                llm_tokens_total.labels(provider=provider, model=normalized_model, use_case=use_case, type='completion').inc(completion_tokens)

            # Estimate and track cost
            cost = estimate_cost(provider, model_name, response.usage)
            if cost > 0:
                llm_cost_usd_total.labels(provider=provider, model=normalized_model, use_case=use_case).inc(cost)
                logger.debug(f"LLM call cost: ${cost:.6f} (provider={provider}, model={normalized_model}, use_case={use_case}, prompt={prompt_tokens}, completion={completion_tokens})")

        return content.strip()

    except openai.APIError as e:
        duration = time.time() - start_time
        error_type = type(e).__name__
        logger.error(f"OpenAI API error: {e}", exc_info=True)

        # Track error metrics
        if provider:
            normalized_model = normalize_model_name(model_name)
            llm_calls_total.labels(provider=provider, model=normalized_model, use_case=use_case, status='error').inc()
            llm_request_duration_seconds.labels(provider=provider, model=normalized_model, use_case=use_case).observe(duration)
            llm_errors_total.labels(provider=provider, model=normalized_model, use_case=use_case, error_type=error_type).inc()

        return None
    except Exception as e:
        duration = time.time() - start_time
        error_type = type(e).__name__
        logger.error(f"Unexpected error in llm_completion (provider={provider}): {e}", exc_info=True)

        # Track error metrics
        if provider:
            normalized_model = normalize_model_name(model_name)
            llm_calls_total.labels(provider=provider, model=normalized_model, use_case=use_case, status='error').inc()
            llm_request_duration_seconds.labels(provider=provider, model=normalized_model, use_case=use_case).observe(duration)
            llm_errors_total.labels(provider=provider, model=normalized_model, use_case=use_case, error_type=error_type).inc()

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
                    use_case=use_case,
                    response_format=response_format,
                    temperature=temperature,
                    max_tokens=max_tokens,
                    max_completion_tokens=max_completion_tokens,
                    _is_fallback_attempt=True
                )
            else:
                logger.warning(f"Groq over capacity but no fallback configured for {model_name}")

        return None
