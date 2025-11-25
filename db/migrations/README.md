# Database Migrations

## Current Status

**All migrations have been merged into `/db/init.sql`**

The main `init.sql` file now contains the complete, up-to-date schema including all historical migrations. This file is used by Docker to initialize a fresh database.

## Migration Files in This Directory

The migration files in this directory are kept for **historical reference only**. They show the evolution of the schema over time:

- `002_add_api_usage_logs.sql` - ✅ Merged into init.sql
- `003_add_schema_version.sql` - ✅ Merged into init.sql
- `004_add_enhanced_review_questions.sql` - ✅ Merged into init.sql
- `005_add_is_known_column.sql` - ✅ Merged into init.sql
- `add_schedule_tables.sql` - ✅ Merged into init.sql
- `modify_streak_days_for_schedules.sql` - ✅ Merged into init.sql

## For Fresh Database Setup

**Use `/db/init.sql` only** - it contains everything needed.

```bash
# Take down existing database
docker-compose down
docker volume rm dogetionary_postgres_data

# Start fresh database with all migrations
docker-compose up -d

# Populate test vocabularies
python scripts/import_test_vocabularies.py
```

## For Adding New Migrations

When adding new schema changes:

1. **Update `/db/init.sql` directly** with your changes
2. Optionally create a migration file here for documentation
3. Update this README

## Database Schema Version

Current schema version: **v5** (as indicated in init.sql line 1)

Includes:
- Core tables (user_preferences, audio, definitions, saved_words, reviews)
- Review questions cache
- Schedule tables (study_schedules, daily_schedule_entries, streak_days)
- Test vocabularies table
- API usage logs
- All indexes and constraints
