-- Migration: Add schema_version to definitions table
-- Date: 2025-10-01
-- Purpose: Track definition schema version for automatic migration

-- Add schema_version column with default value 1 for existing rows
ALTER TABLE definitions ADD COLUMN IF NOT EXISTS schema_version INTEGER DEFAULT 1;

-- Create index for efficient querying
CREATE INDEX IF NOT EXISTS idx_definitions_schema_version ON definitions(schema_version);

-- Update existing rows to have schema_version = 1
UPDATE definitions SET schema_version = 1 WHERE schema_version IS NULL;

-- Make schema_version NOT NULL after setting default
ALTER TABLE definitions ALTER COLUMN schema_version SET NOT NULL;
