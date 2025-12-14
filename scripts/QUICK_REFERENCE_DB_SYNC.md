# Database Sync - Quick Reference Card

## TL;DR

**Pull production data to local:**
```bash
cd /Users/biubiu/projects/dogetionary
./scripts/sync_db_from_remote.sh
```

**Time:** ~5-10 minutes | **Size:** ~2.2GB compressed

---

## Common Commands

### Full Sync (Pull + Restore)
```bash
./scripts/sync_db_from_remote.sh
```
✅ Creates local backup
✅ Pulls remote snapshot
✅ Restores to local
✅ Verifies data
✅ Restarts services

### Snapshot Only (No Restore)
```bash
./scripts/sync_db_from_remote.sh --snapshot-only
```
📦 Downloads snapshot
🚫 Doesn't modify local database

### Restore from Existing Snapshot
```bash
./scripts/sync_db_from_remote.sh --restore-from \
  /Volumes/databank/dogetionary_remote_snapshot_20251213_193943.sql.gz
```
♻️ Uses previously downloaded snapshot
⚡ Faster than pulling again

### Dry Run (Test Mode)
```bash
./scripts/sync_db_from_remote.sh --dry-run
```
👀 Shows what would happen
🚫 Doesn't execute any changes

### Skip Local Backup (Fast Mode)
```bash
./scripts/sync_db_from_remote.sh --skip-local-backup
```
⚠️ No safety net - use with caution

---

## File Locations

### Snapshots
```
/Volumes/databank/dogetionary_remote_snapshot_YYYYMMDD_HHMMSS.sql.gz
```

### Backups
```
/Volumes/databank/dogetionary_local_backup_YYYYMMDD_HHMMSS.sql.gz
```

### Logs
```
/Volumes/databank/db_sync_YYYYMMDD_HHMMSS.log
```

---

## What Gets Synced

| Table | Description | Typical Rows |
|-------|-------------|--------------|
| user_preferences | User settings | ~2 |
| saved_words | User vocabulary | ~34 |
| reviews | Review history | ~24 |
| definitions | Word definitions | ~8,242 |
| audio | TTS cache | ~326 |
| **Total Tables** | | **18** |

---

## Workflow

```
┌──────────────┐    SSH     ┌──────────────┐
│   Remote     │───────────>│    Local     │
│  Production  │   pg_dump  │ Development  │
│              │   +gzip    │              │
│ 69.167.     │            │ localhost    │
│ 170.85      │            │              │
└──────────────┘            └──────────────┘
      │                            │
      └─> tianzhic/dogetionary    └─> dogetionary/
          dogetionary_postgres_1       dogetionary-postgres-1
```

---

## Quick Troubleshooting

### SSH Fails
```bash
ssh root@69.167.170.85 echo "test"
```

### Disk Space
```bash
df -h /Volumes/databank
```

### Container Status
```bash
docker-compose ps
```

### View Logs
```bash
tail -f /Volumes/databank/db_sync_YYYYMMDD_HHMMSS.log
```

### Verify Sync
```bash
docker exec dogetionary-postgres-1 \
  psql -U dogeuser -d dogetionary -c "SELECT COUNT(*) FROM saved_words"
```

---

## Recovery

### Restore from Local Backup
```bash
gunzip -c /Volumes/databank/dogetionary_local_backup_*.sql.gz | \
  docker exec -i dogetionary-postgres-1 \
    psql -U dogeuser -d dogetionary

docker-compose up -d
```

---

## Configuration

### Remote Server
- Host: `69.167.170.85`
- User: `root` → `su - tianzhic`
- Path: `~/dogetionary`
- Container: `dogetionary_postgres_1` ⚠️ (underscores)

### Local Environment
- Path: `/Users/biubiu/projects/dogetionary`
- Container: `dogetionary-postgres-1` ⚠️ (dashes)
- Database: `dogetionary` / User: `dogeuser`

---

## Help

**Detailed docs:** [Database Sync Guide](../docs/database-sync-guide.md)

**Script help:**
```bash
./scripts/sync_db_from_remote.sh --help
```

**Check health:**
```bash
curl http://localhost:5000/health
```

---

## Safety Checklist

- [ ] Understand what local data will be lost
- [ ] Have recent code backup (git commit)
- [ ] Have sufficient disk space (~5GB)
- [ ] Not running critical local tests
- [ ] Ready to wait 5-10 minutes

---

**Version:** 1.0 | **Last Updated:** 2025-12-13
