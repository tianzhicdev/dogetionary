# Quick Reference: Production Vocabulary Import

## What You Need to Do

To clear existing `bundle_vocabularies` (or `test_vocabularies` on prod) and upload `vocabulary_merged.csv`:

### On Production Server:

```bash
# 1. Copy files to server
scp resources/words/vocabulary_merged.csv user@server:/path/to/dogetionary/resources/words/
scp scripts/import_vocabulary_to_prod.py user@server:/path/to/dogetionary/scripts/

# 2. SSH and run import
ssh user@server
cd /path/to/dogetionary
export DATABASE_URL="postgresql://user:pass@localhost:5432/dogetionary"
python3 scripts/import_vocabulary_to_prod.py
```

When prompted, type `yes` to confirm.

## Does the Script Still Work?

✅ **YES** - The script `import_vocabulary_to_prod.py` is **production-safe** and works with:

| Environment | Table Name | Demo Column | Business/Everyday Columns |
|-------------|------------|-------------|---------------------------|
| **Production** (commit 4d446430) | `test_vocabularies` | `is_tianz` | ❌ Missing (script skips) |
| **Current Dev** (HEAD) | `bundle_vocabularies` | `is_demo` | ✅ Exists |

The script **auto-detects** the schema and adapts accordingly.

## What the Script Does

1. ✅ Connects to database
2. ✅ Detects schema (table/column names)
3. ✅ **CLEARS** all existing vocabulary
4. ✅ Imports 4,042 words from `vocabulary_merged.csv`
5. ✅ Shows statistics

## Expected Result

After import:
- Total words: **4,042**
- TOEFL beginner: **796**
- TOEFL intermediate: **1,995**
- TOEFL advanced: **4,889**
- IELTS beginner: **800**
- IELTS intermediate: **2,000**
- IELTS advanced: **4,323**

## Testing Before Production

```bash
# Test locally first (dry run)
python3 scripts/test_import_vocab.py
```

## Rollback

```bash
# Create backup before import
pg_dump dogetionary > backup_$(date +%Y%m%d).sql

# Restore if needed
psql dogetionary < backup_YYYYMMDD.sql
```

---

**See DEPLOYMENT_VOCABULARY_IMPORT.md for detailed instructions**
