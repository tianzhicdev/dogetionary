# Vocabulary Import to Production

## Prerequisites

**IMPORTANT:** Check which commit is deployed in production.

Current production commit: `4d446430cd4bcd6ae964f0a65653007da8f70783`

## Deployment Steps

### Step 1: Determine if Migration 009 is needed

Production at `4d446430` has **NOT** run migration 009 yet, which:
- Renames `test_vocabularies` → `bundle_vocabularies`
- Renames `is_tianz` → `is_demo`
- Adds `business_english` and `everyday_english` columns

**Decision:**
- **Option A:** Run migration 009 first, THEN import vocabulary
- **Option B:** Import vocabulary to current schema (test_vocabularies), then migrate later

### Step 2A: If Running Migration 009 First (Recommended)

```bash
# 1. Backup database
pg_dump -h <prod-host> -U <user> dogetionary > backup_pre_vocab_import_$(date +%Y%m%d).sql

# 2. Run migration 009
psql -h <prod-host> -U <user> -d dogetionary -f db/migration_009_bundle_vocabulary.sql

# 3. Verify migration
psql -h <prod-host> -U <user> -d dogetionary -c "\d bundle_vocabularies"

# 4. Upload vocabulary CSV to server
scp resources/words/vocabulary_merged.csv <server>:/path/to/dogetionary/resources/words/

# 5. Upload import script to server
scp scripts/import_vocabulary_to_prod.py <server>:/path/to/dogetionary/scripts/

# 6. SSH into server and run import
ssh <server>
cd /path/to/dogetionary
export DATABASE_URL="postgresql://<user>:<pass>@localhost:5432/dogetionary"
python3 scripts/import_vocabulary_to_prod.py
# Type 'yes' when prompted
```

### Step 2B: If Importing to Current Schema (No Migration)

```bash
# 1. Backup database
pg_dump -h <prod-host> -U <user> dogetionary > backup_pre_vocab_import_$(date +%Y%m%d).sql

# 2. Upload files to server
scp resources/words/vocabulary_merged.csv <server>:/path/to/dogetionary/resources/words/
scp scripts/import_vocabulary_to_prod.py <server>:/path/to/dogetionary/scripts/

# 3. SSH into server and run import
ssh <server>
cd /path/to/dogetionary
export DATABASE_URL="postgresql://<user>:<pass>@localhost:5432/dogetionary"
python3 scripts/import_vocabulary_to_prod.py
# Type 'yes' when prompted
```

The script will automatically:
- Detect `test_vocabularies` table
- Use `is_tianz` instead of `is_demo`
- Skip `business_english` and `everyday_english` columns if they don't exist

### Step 3: Verify Import

```bash
# Check total count
psql -h <prod-host> -U <user> -d dogetionary -c "
  SELECT
    COUNT(*) as total_words,
    COUNT(CASE WHEN is_toefl_beginner THEN 1 END) as toefl_beginner,
    COUNT(CASE WHEN is_toefl_intermediate THEN 1 END) as toefl_intermediate,
    COUNT(CASE WHEN is_toefl_advanced THEN 1 END) as toefl_advanced,
    COUNT(CASE WHEN is_ielts_beginner THEN 1 END) as ielts_beginner,
    COUNT(CASE WHEN is_ielts_intermediate THEN 1 END) as ielts_intermediate,
    COUNT(CASE WHEN is_ielts_advanced THEN 1 END) as ielts_advanced
  FROM test_vocabularies  -- or bundle_vocabularies if migrated
  WHERE language = 'en';
"
```

Expected output:
- Total words: ~4,042
- TOEFL beginner: ~796
- TOEFL intermediate: ~1,995
- TOEFL advanced: ~4,889
- IELTS beginner: ~800
- IELTS intermediate: ~2,000
- IELTS advanced: ~4,323

## Script Features

✅ **Production Safe:**
- Auto-detects table name (`test_vocabularies` vs `bundle_vocabularies`)
- Auto-detects column names (`is_tianz` vs `is_demo`)
- Handles missing columns gracefully (`business_english`, `everyday_english`)
- Requires explicit confirmation before clearing data
- Comprehensive logging and error handling

✅ **What the script does:**
1. Connects to database
2. Detects schema (table and column names)
3. Clears existing vocabulary data
4. Imports 4,042 words from `vocabulary_merged.csv`
5. Shows import statistics
6. Verifies cumulative counts

## Testing the Script

Before running on production, test locally:

```bash
# Dry run test (doesn't modify data)
python3 scripts/test_import_vocab.py
```

## Rollback Plan

If something goes wrong:

```bash
# Restore from backup
psql -h <prod-host> -U <user> -d dogetionary < backup_pre_vocab_import_YYYYMMDD.sql
```

## Files Needed on Production Server

1. `resources/words/vocabulary_merged.csv` - The vocabulary data (4,042 words)
2. `scripts/import_vocabulary_to_prod.py` - The import script

## Environment Variables

The script uses:
- `DATABASE_URL` - PostgreSQL connection string
  - Default: `postgresql://dogeuser:dogepass@localhost:5432/dogetionary`
  - Override for production: `export DATABASE_URL="postgresql://..."`
