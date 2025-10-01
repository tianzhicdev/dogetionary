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