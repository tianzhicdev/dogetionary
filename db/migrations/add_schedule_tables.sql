-- Migration: Add schedule tables and timezone support
-- Run this after backing up database
-- Description: Adds study_schedules and daily_schedule_entries tables for test preparation scheduling

BEGIN;

-- Step 1.1: Add timezone to user_preferences
ALTER TABLE user_preferences
ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'UTC';

CREATE INDEX IF NOT EXISTS idx_user_preferences_timezone
ON user_preferences(timezone);

-- Step 1.2: Create study_schedules table
CREATE TABLE IF NOT EXISTS study_schedules (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES user_preferences(user_id) ON DELETE CASCADE,
    test_type VARCHAR(20) NOT NULL CHECK (test_type IN ('TOEFL', 'IELTS', 'BOTH')),
    target_end_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_study_schedules_user ON study_schedules(user_id);
CREATE INDEX IF NOT EXISTS idx_study_schedules_end_date ON study_schedules(target_end_date);

-- Step 1.3: Create daily_schedule_entries table
CREATE TABLE IF NOT EXISTS daily_schedule_entries (
    id SERIAL PRIMARY KEY,
    schedule_id INTEGER NOT NULL REFERENCES study_schedules(id) ON DELETE CASCADE,
    scheduled_date DATE NOT NULL,
    new_words JSONB DEFAULT '[]'::jsonb,
    test_practice_words JSONB DEFAULT '[]'::jsonb,
    non_test_practice_words JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(schedule_id, scheduled_date)
);

CREATE INDEX IF NOT EXISTS idx_daily_entries_schedule ON daily_schedule_entries(schedule_id, scheduled_date);
CREATE INDEX IF NOT EXISTS idx_daily_entries_date ON daily_schedule_entries(scheduled_date DESC);

-- Step 1.4: Create streak_days table (tracks daily completion streaks per schedule)
CREATE TABLE IF NOT EXISTS streak_days (
    id SERIAL PRIMARY KEY,
    schedule_id INTEGER NOT NULL REFERENCES study_schedules(id) ON DELETE CASCADE,
    streak_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(schedule_id, streak_date)
);

CREATE INDEX IF NOT EXISTS idx_streak_days_schedule_date ON streak_days(schedule_id, streak_date DESC);

COMMIT;
