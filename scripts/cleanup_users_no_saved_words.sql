-- Remove all users who have no saved words
-- This script will delete user preferences for users who don't have any saved words

DELETE FROM user_preferences
WHERE user_id NOT IN (
    SELECT DISTINCT user_id
    FROM saved_words
);