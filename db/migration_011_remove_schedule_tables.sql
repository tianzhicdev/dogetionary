-- Migration 011: Remove schedule feature tables
-- Part of radical simplification - schedule calculations now happen on-the-fly
-- Date: 2025-12-19

-- Drop daily_schedule_entries first (has foreign key to study_schedules)
DROP TABLE IF EXISTS daily_schedule_entries CASCADE;

-- Drop study_schedules table
DROP TABLE IF EXISTS study_schedules CASCADE;

-- Note: We keep target_end_date in user_preferences table
-- It may still be useful for test prep duration tracking

-- Verify tables are dropped
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'study_schedules') THEN
        RAISE EXCEPTION 'Failed to drop study_schedules table';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'daily_schedule_entries') THEN
        RAISE EXCEPTION 'Failed to drop daily_schedule_entries table';
    END IF;

    RAISE NOTICE 'Migration 011 completed successfully - schedule tables dropped';
END $$;
