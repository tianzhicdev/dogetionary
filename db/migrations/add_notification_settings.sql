-- Migration: Add notification and timezone settings to user_preferences
-- This migration adds timezone and notification preferences for daily review reminders

-- Add timezone and notification columns to user_preferences table
ALTER TABLE user_preferences
ADD COLUMN timezone VARCHAR(50) DEFAULT 'UTC',
ADD COLUMN notification_enabled BOOLEAN DEFAULT true,
ADD COLUMN notification_time TIME DEFAULT '11:59:00',
ADD COLUMN last_notification_sent TIMESTAMP DEFAULT NULL;

-- Add index for timezone-based queries
CREATE INDEX idx_user_preferences_timezone ON user_preferences(timezone);
CREATE INDEX idx_user_preferences_notification ON user_preferences(notification_enabled, notification_time);

-- Add notification logs table to track sent notifications
CREATE TABLE notification_logs (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    message TEXT NOT NULL,
    words_count INTEGER,
    sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) DEFAULT 'sent',
    FOREIGN KEY (user_id) REFERENCES user_preferences(user_id)
);

-- Add indexes for notification logs
CREATE INDEX idx_notification_logs_user_id ON notification_logs(user_id);
CREATE INDEX idx_notification_logs_sent_at ON notification_logs(sent_at);
CREATE INDEX idx_notification_logs_type ON notification_logs(notification_type);

-- Update existing users to have default timezone settings
UPDATE user_preferences
SET timezone = 'UTC',
    notification_enabled = true,
    notification_time = '11:59:00'
WHERE timezone IS NULL;