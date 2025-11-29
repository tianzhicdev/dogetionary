# Database Schema

## Current Status

**Single Source of Truth: `/db/init.sql`**

The `init.sql` file contains the complete, up-to-date database schema. All migrations have been merged into this single file for simplicity and clarity.

## Schema Version

Current version: **v7**

Includes:
- Core tables (user_preferences, audio, definitions, saved_words, reviews)
- Review questions cache
- Schedule tables (study_schedules, daily_schedule_entries, streak_days)
- Test vocabularies table with granular level support (beginner, intermediate, advanced)
- API usage logs
- All indexes and constraints

**v7 Changes:**
- Streaks tied to `user_id` instead of `schedule_id` for persistence across schedule changes
- Users maintain streak history when switching test types or updating study plans

## Fresh Database Setup

```bash
# Take down existing database
docker-compose down
docker volume rm dogetionary_postgres_data

# Start fresh database with complete schema
docker-compose up -d

# Populate test vocabularies
python scripts/import_test_vocabularies.py
```

## Adding New Schema Changes

When making database changes:

1. **Update `/db/init.sql` directly** with your changes
2. Increment the schema version number in the header comment
3. Update this README with a brief description
4. Test with a fresh database setup

## No Migrations Directory

We do NOT use a migrations directory. All schema changes are made directly to `init.sql`. This keeps the codebase clean and avoids migration complexity for a project of this size.

For production environments with existing data, schema changes would need to be applied manually or via custom scripts.
