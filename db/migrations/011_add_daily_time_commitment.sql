-- Migration 011: Add daily time commitment to user preferences
-- Adds column to track how much time users commit to studying daily

BEGIN;

-- Add new column with default value (30 minutes)
ALTER TABLE user_preferences
ADD COLUMN daily_time_commitment_minutes INTEGER DEFAULT 30;

-- Add comment explaining the field
COMMENT ON COLUMN user_preferences.daily_time_commitment_minutes IS
'Daily study time commitment in minutes (range: 10-480). Used for scheduling, personalization, and calculating realistic study plans. Default: 30 minutes.';

-- Add check constraint to ensure valid range (10 minutes to 8 hours)
ALTER TABLE user_preferences
ADD CONSTRAINT check_time_commitment_range
CHECK (daily_time_commitment_minutes >= 10 AND daily_time_commitment_minutes <= 480);

COMMIT;
