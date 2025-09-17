-- Migration: Add validation action types to user_actions table
-- This migration adds support for word validation analytics

-- Drop the existing constraint
ALTER TABLE user_actions DROP CONSTRAINT valid_action;

-- Add the new constraint with validation actions included
ALTER TABLE user_actions
ADD CONSTRAINT valid_action CHECK (
    action IN (
        'dictionary_search',
        'dictionary_search_audio',
        'dictionary_save',
        'dictionary_auto_save',
        'dictionary_example_audio',
        'dictionary_illustration',
        'validation_invalid',
        'validation_accept_suggestion',
        'validation_use_original',
        'validation_cancel',
        'review_start',
        'review_answer_correct',
        'review_answer_incorrect',
        'review_audio',
        'review_next',
        'review_complete',
        'nav_tab_dictionary',
        'nav_tab_saved',
        'nav_tab_review',
        'nav_tab_leaderboard',
        'nav_tab_settings',
        'profile_name_update',
        'profile_motto_update',
        'profile_language_learning',
        'profile_language_native',
        'settings_notification_enable',
        'settings_notification_disable',
        'settings_notification_time',
        'settings_timezone_update',
        'saved_view_details',
        'feedback_submit',
        'app_launch',
        'app_background',
        'app_foreground'
    )
);