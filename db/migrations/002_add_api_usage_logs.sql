-- Migration: Add API Usage Logs table
-- Date: 2025-09-30
-- Purpose: Track endpoint usage for API deprecation and performance monitoring

-- Create API Usage Logs table
CREATE TABLE IF NOT EXISTS api_usage_logs (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP NOT NULL DEFAULT NOW(),
    endpoint VARCHAR(255) NOT NULL,
    method VARCHAR(10) NOT NULL,
    user_id UUID,
    response_status INTEGER,
    duration_ms FLOAT,
    user_agent TEXT,
    api_version VARCHAR(10)  -- 'v1', 'v2', 'v3', or NULL for unversioned
);

-- Create indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_api_usage_endpoint_timestamp ON api_usage_logs(endpoint, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_api_usage_timestamp ON api_usage_logs(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_api_usage_user_id ON api_usage_logs(user_id);
