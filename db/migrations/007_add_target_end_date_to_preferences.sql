-- Migration: Add target_end_date to user_preferences
-- This allows schedules to be calculated on-the-fly from user preferences
-- instead of being stored in study_schedules and daily_schedule_entries tables

ALTER TABLE user_preferences
ADD COLUMN target_end_date DATE;

-- Copy existing target_end_date from study_schedules to user_preferences
UPDATE user_preferences up
SET target_end_date = ss.target_end_date
FROM study_schedules ss
WHERE up.user_id = ss.user_id;

-- Add comment explaining the column
COMMENT ON COLUMN user_preferences.target_end_date IS 'Target date for completing test preparation. Used to calculate daily schedules on-the-fly.';
