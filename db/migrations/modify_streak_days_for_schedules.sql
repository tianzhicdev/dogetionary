-- Migration: Modify streak_days to tie to schedules
-- Description: Changes streak_days from user-based to schedule-based

BEGIN;

-- Drop existing streak_days table
DROP TABLE IF EXISTS streak_days CASCADE;

-- Recreate streak_days table tied to schedule
CREATE TABLE streak_days (
    id SERIAL PRIMARY KEY,
    schedule_id INTEGER NOT NULL REFERENCES study_schedules(id) ON DELETE CASCADE,
    streak_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(schedule_id, streak_date)
);

-- Create index for efficient queries
CREATE INDEX idx_streak_days_schedule_date ON streak_days(schedule_id, streak_date DESC);

COMMIT;
