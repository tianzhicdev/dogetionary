"""
Centralized Bundle Configuration
Maps bundle types to database columns and user preferences.
"""

# Bundle type to database column mapping
BUNDLE_TYPE_MAP = {
    'TOEFL_BEGINNER': ('toefl_enabled', 'toefl_target_days', 'is_toefl_beginner'),
    'TOEFL_INTERMEDIATE': ('toefl_enabled', 'toefl_target_days', 'is_toefl_intermediate'),
    'TOEFL_ADVANCED': ('toefl_enabled', 'toefl_target_days', 'is_toefl_advanced'),
    'IELTS_BEGINNER': ('ielts_enabled', 'ielts_target_days', 'is_ielts_beginner'),
    'IELTS_INTERMEDIATE': ('ielts_enabled', 'ielts_target_days', 'is_ielts_intermediate'),
    'IELTS_ADVANCED': ('ielts_enabled', 'ielts_target_days', 'is_ielts_advanced'),
    'DEMO': ('demo_enabled', 'demo_target_days', 'is_demo'),
    'BUSINESS_ENGLISH': ('business_english_enabled', 'business_english_target_days', 'business_english'),
    'EVERYDAY_ENGLISH': ('everyday_english_enabled', 'everyday_english_target_days', 'everyday_english'),
}

# All bundle enable columns
ALL_BUNDLE_ENABLE_COLUMNS = [
    'toefl_enabled', 'ielts_enabled', 'demo_enabled',
    'business_english_enabled', 'everyday_english_enabled'
]

# All bundle vocabulary columns
ALL_BUNDLE_VOCAB_COLUMNS = [
    'is_toefl_beginner', 'is_toefl_intermediate', 'is_toefl_advanced',
    'is_ielts_beginner', 'is_ielts_intermediate', 'is_ielts_advanced',
    'is_demo', 'business_english', 'everyday_english'
]

# Source name mapping (for API compatibility)
SOURCE_TO_COLUMN_MAP = {
    'demo_bundle': 'is_demo',
    'demo': 'is_demo',
    'business_english': 'business_english',
    'everyday_english': 'everyday_english',
    'toefl': 'is_toefl_beginner',  # Default to beginner
    'toefl_beginner': 'is_toefl_beginner',
    'toefl_intermediate': 'is_toefl_intermediate',
    'toefl_advanced': 'is_toefl_advanced',
    'ielts': 'is_ielts_beginner',  # Default to beginner
    'ielts_beginner': 'is_ielts_beginner',
    'ielts_intermediate': 'is_ielts_intermediate',
    'ielts_advanced': 'is_ielts_advanced',
}
