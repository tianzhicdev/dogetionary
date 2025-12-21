# OpenAI Model Configuration
# Text completion models

# Legacy model configs (deprecated - use FALLBACK_CHAINS instead)
COMPLETION_MODEL_WORD_SEARCH = "llama-3.3-70b-versatile"  # Groq: Ultra-fast word definition lookup (200-500ms)
COMPLETION_MODEL_NAME = "gpt-4o-mini"  # OpenAI: High-quality for questions, profiles, feedback
COMPLETION_MODEL_NAME_ADVANCED = "gpt-4o"  # OpenAI: Advanced tasks like scene generation

# Fallback mappings: Groq model -> OpenAI model (when Groq is over capacity)
# Note: This is legacy fallback, new code should use FALLBACK_CHAINS
GROQ_TO_OPENAI_FALLBACK = {
    "meta-llama/llama-4-scout-17b-16e-instruct": "gpt-4o-mini",
    "llama-4-scout": "gpt-4o-mini",
    "llama-3.3-70b-versatile": "gpt-4o",
    "llama-3.1-70b-versatile": "gpt-4o",
    "mixtral-8x7b-32768": "gpt-4o-mini",
}

# Multi-level fallback chains per use case
# Chain tries models in order: DeepSeek V3 -> Qwen 2.5 7B -> Mistral Small -> GPT-4o
FALLBACK_CHAINS = {
    "definition": [
        "google/gemini-2.0-flash-lite-001",   # Fastest TTFT, excellent multilingual ($0.10/$0.40/M)
        "deepseek/deepseek-chat-v3.1",        # Great Chinese, cheap ($0.14-0.28/M with caching)
        "qwen/qwen-2.5-7b-instruct",          # Best Chinese+JSON quality ($0.15/$0.17/M)
        "openai/gpt-4o-mini"                  # Most reliable fallback ($0.15/$0.60/M)
    ],
    "question": [
        "google/gemini-2.0-flash-lite-001",
        "deepseek/deepseek-chat-v3.1",
        "qwen/qwen-2.5-7b-instruct",
        "openai/gpt-4o-mini"
    ],
    "user_profile": [
        "google/gemini-2.0-flash-lite-001",
        "deepseek/deepseek-chat-v3.1",
        "qwen/qwen-2.5-7b-instruct",
        "openai/gpt-4o-mini"
    ],
    "pronunciation": [
        "google/gemini-2.0-flash-lite-001",
        "deepseek/deepseek-chat-v3.1",
        "openai/gpt-4o-mini"
    ],
    "scene_description": [
        "google/gemini-2.0-flash-lite-001",
        "deepseek/deepseek-chat-v3.1",
        "openai/gpt-4o-mini"
    ],
    "general": [
        "google/gemini-2.0-flash-lite-001",
        "deepseek/deepseek-chat-v3.1",
        "qwen/qwen-2.5-7b-instruct",
        "openai/gpt-4o-mini"
    ],
    "video_analysis": [
        "google/gemini-2.0-flash-lite-001",   # Fast structured output for video analysis
        "deepseek/deepseek-chat-v3.1",        # Good JSON quality
        "qwen/qwen-2.5-7b-instruct",          # Backup for structured output
        "openai/gpt-4o-mini"                  # Final fallback
    ]
}

# Image generation models
IMAGE_MODEL_NAME = "dall-e-3"  # High-quality image generation
IMAGE_MODEL_SIZE = "1024x1024"  # Default image size
IMAGE_MODEL_QUALITY = "standard"  # Image quality: "standard" or "hd"

# Audio/TTS models
TTS_MODEL_NAME = "tts-1"  # Fast text-to-speech model
TTS_VOICE = "alloy"  # Default voice: alloy, echo, fable, onyx, nova, shimmer
WHISPER_MODEL_NAME = "whisper-1"  # Speech-to-text transcription model

# SM-2 SuperMemo spaced repetition algorithm (deprecated - now using Fibonacci)
INITIAL_INTERVALS = [1, 6]  # First review: 1 day, Second review: 6 days

DECAY_RATE_WEEK_1 = 0.45      # 45% per day
DECAY_RATE_WEEK_2 = 0.18      # 22% per day
DECAY_RATE_WEEK_3_4 = 0.09    # 11% per day
DECAY_RATE_WEEK_5_8 = 0.035   # 5.5% per day
DECAY_RATE_WEEK_9_PLUS = 0.015 # 2.5% per day

RETENTION_THRESHOLD = 0.40  # 40% retention threshold

# Supported languages
SUPPORTED_LANGUAGES = {
    'af', 'ar', 'hy', 'az', 'be', 'bs', 'bg', 'ca', 'zh', 'hr', 'cs', 'da',
    'nl', 'en', 'et', 'fi', 'fr', 'gl', 'de', 'el', 'he', 'hi', 'hu', 'is',
    'id', 'it', 'ja', 'kn', 'kk', 'ko', 'lv', 'lt', 'mk', 'ms', 'mr', 'mi',
    'ne', 'no', 'fa', 'pl', 'pt', 'ro', 'ru', 'sr', 'sk', 'sl', 'es', 'sw',
    'sv', 'tl', 'ta', 'th', 'tr', 'uk', 'ur', 'vi', 'cy'
}