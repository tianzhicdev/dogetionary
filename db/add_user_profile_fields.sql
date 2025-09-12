-- Migration to add user profile fields to user_preferences table
-- Adds user_name and user_motto columns for leaderboard functionality

ALTER TABLE user_preferences 
ADD COLUMN user_name VARCHAR(255),
ADD COLUMN user_motto TEXT;

-- Update the demo user with sample profile data
UPDATE user_preferences 
SET user_name = 'Demo User', user_motto = 'Learning every day!' 
WHERE user_id = '5E0DAFB6-756C-463E-8061-F88DEAC2E20B';