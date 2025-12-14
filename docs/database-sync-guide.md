# Database Sync Guide - Remote to Local

## Overview

This guide explains how to synchronize your local development database with the production database running on the remote server. The process involves pulling a compressed snapshot from the remote server and restoring it locally.

## Table of Contents

1. [Quick Start](#quick-start)
2. [How It Works](#how-it-works)
3. [Architecture](#architecture)
4. [Detailed Process](#detailed-process)
5. [Usage Examples](#usage-examples)
6. [Troubleshooting](#troubleshooting)
7. [Technical Details](#technical-details)

---

## Quick Start

### Prerequisites

- SSH access to remote server (`root@69.167.170.85`)
- Docker and docker-compose installed locally
- `/Volumes/databank` directory exists and is writable
- At least 5GB free disk space

### Basic Usage

**Full sync (recommended for most cases):**

```bash
cd /Users/biubiu/projects/dogetionary
./scripts/sync_db_from_remote.sh
```

This will:
1. Create a safety backup of your current local database
2. Pull the latest snapshot from production
3. Replace your local database with production data
4. Verify the restoration
5. Restart all services

**Time estimate:** 5-10 minutes for a 2GB database

---

## How It Works

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    REMOTE SERVER                             │
│  (69.167.170.85)                                            │
│                                                              │
│  1. SSH connection established                              │
│     ssh root@69.167.170.85                                  │
│                                                              │
│  2. Switch to application user                              │
│     su - tianzhic                                           │
│                                                              │
│  3. Execute pg_dump inside Docker container                 │
│     docker exec dogetionary_postgres_1 \                    │
│       pg_dump -U dogeuser dogetionary                       │
│                                                              │
│  4. Stream output through SSH pipe                          │
│     (encrypted transfer)                                    │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ (gzip compressed stream)
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    LOCAL MACHINE                             │
│                                                              │
│  5. Receive and compress data                               │
│     | gzip -9 > snapshot.sql.gz                             │
│                                                              │
│  6. Save to /Volumes/databank/                              │
│     dogetionary_remote_snapshot_YYYYMMDD_HHMMSS.sql.gz     │
│                                                              │
│  7. Verify file integrity                                   │
│     gunzip -t snapshot.sql.gz                               │
│                                                              │
│  8. Stop dependent services                                 │
│     docker-compose stop app nginx                           │
│                                                              │
│  9. Terminate database connections                          │
│     SELECT pg_terminate_backend(...)                        │
│                                                              │
│  10. Drop existing database                                 │
│      dropdb dogetionary                                     │
│                                                              │
│  11. Create fresh database                                  │
│      createdb dogetionary                                   │
│                                                              │
│  12. Restore from snapshot                                  │
│      gunzip -c snapshot.sql.gz | psql                       │
│                                                              │
│  13. Verify restoration                                     │
│      Check table counts and critical data                   │
│                                                              │
│  14. Restart all services                                   │
│      docker-compose up -d                                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Architecture

### Remote Server Configuration

**Location:** `69.167.170.85`

**Access Path:**
```
SSH User: root
├─ Application User: tianzhic (via su -)
   ├─ Project Directory: ~/dogetionary
      ├─ Docker Container: dogetionary_postgres_1
         └─ Database: dogetionary (user: dogeuser)
```

**Database Details:**
- PostgreSQL Version: 15
- Database Name: `dogetionary`
- Database User: `dogeuser`
- Database Password: `dogepass`
- Container: Uses underscores `dogetionary_postgres_1`

### Local Environment Configuration

**Location:** `/Users/biubiu/projects/dogetionary`

**Setup:**
```
Project Directory: /Users/biubiu/projects/dogetionary
├─ Docker Container: dogetionary-postgres-1  (uses dashes)
├─ Database: dogetionary
├─ Backup Storage: /Volumes/databank/
└─ Log Storage: /Volumes/databank/
```

**Key Difference:** Local containers use dashes (`-`) while remote uses underscores (`_`)

---

## Detailed Process

### Phase 1: Pre-Flight Checks

The script validates your environment before starting:

1. **Directory Validation**
   - Checks `/Volumes/databank` exists and is writable
   - Verifies local project structure

2. **Tool Availability**
   - Confirms `docker-compose` is installed
   - Checks Docker is running

3. **SSH Connection**
   - Tests connection to remote server
   - Warns if password auth is required (key-based preferred)

4. **Container Status**
   - Ensures local PostgreSQL container is running
   - Starts it if necessary

### Phase 2: Safety Backup (Optional)

**What happens:**
```bash
docker exec dogetionary-postgres-1 \
  pg_dump -U dogeuser dogetionary | \
  gzip -9 > /Volumes/databank/dogetionary_local_backup_TIMESTAMP.sql.gz
```

**Why it's important:**
- Protects against failed restores
- Allows rollback if snapshot is corrupted
- Preserves local development data

**Skip with:** `--skip-local-backup` flag (not recommended)

### Phase 3: Remote Snapshot Pull

**Command executed on remote:**
```bash
ssh root@69.167.170.85 \
  "su - tianzhic -c 'cd ~/dogetionary && \
   docker exec dogetionary_postgres_1 \
     pg_dump -U dogeuser dogetionary'" | \
  gzip -9 > /Volumes/databank/dogetionary_remote_snapshot_TIMESTAMP.sql.gz
```

**Process details:**

1. **SSH Tunnel Established**
   - Encrypted connection to remote server
   - Uses your SSH key or password

2. **User Switch**
   - `su - tianzhic` switches to application user
   - Necessary for Docker access permissions

3. **pg_dump Execution**
   - Dumps entire database schema and data
   - Runs inside Docker container
   - Streams to stdout

4. **Compression**
   - `gzip -9` maximum compression
   - Reduces transfer time and storage
   - Typical compression: 70-90%

5. **File Creation**
   - Saved with timestamp for tracking
   - Example: `dogetionary_remote_snapshot_20251213_193943.sql.gz`

**Performance:**
- 2GB database → ~15-20 minutes to pull
- Network dependent (SSH bandwidth)
- Compression happens on-the-fly

### Phase 4: Integrity Verification

**What happens:**
```bash
gunzip -t /Volumes/databank/dogetionary_remote_snapshot_*.sql.gz
```

**Checks:**
- File is valid gzip format
- No corruption during transfer
- Complete file received

**If verification fails:** Script exits immediately, no restore attempted

### Phase 5: Restoration

**Step-by-step:**

1. **Stop Dependent Services**
   ```bash
   docker-compose stop app nginx
   ```
   - Prevents connections during restore
   - Postgres container keeps running

2. **Terminate Active Connections**
   ```sql
   SELECT pg_terminate_backend(pid)
   FROM pg_stat_activity
   WHERE datname = 'dogetionary'
     AND pid <> pg_backend_pid();
   ```
   - Kills any remaining connections
   - Allows clean database drop

3. **Drop Existing Database**
   ```bash
   docker exec dogetionary-postgres-1 \
     dropdb -U dogeuser --if-exists dogetionary
   ```
   - Removes all tables, data, schemas
   - Complete clean slate

4. **Create Fresh Database**
   ```bash
   docker exec dogetionary-postgres-1 \
     createdb -U dogeuser dogetionary
   ```
   - New empty database
   - Ready for data import

5. **Restore Data**
   ```bash
   gunzip -c /Volumes/databank/snapshot.sql.gz | \
     docker exec -i dogetionary-postgres-1 \
       psql -U dogeuser -d dogetionary --set ON_ERROR_STOP=on
   ```
   - Decompresses on-the-fly
   - Pipes into psql
   - `ON_ERROR_STOP=on` ensures no partial restores

**Restore Output:**
```
CREATE TABLE        # Schema creation
ALTER TABLE         # Constraints
CREATE SEQUENCE     # Auto-increment sequences
CREATE INDEX        # Performance indexes
COPY 15009         # Data insertion (row counts)
COPY 8242
...
CREATE TRIGGER      # Database triggers
```

**Time estimate:** ~60-90 seconds for 2GB database

### Phase 6: Verification

**Automated Checks:**

1. **Table Count**
   ```sql
   SELECT COUNT(*)
   FROM information_schema.tables
   WHERE table_schema = 'public'
   ```
   Expected: 18 tables

2. **Critical Tables**
   - `user_preferences` - User settings
   - `saved_words` - User vocabulary
   - `reviews` - Spaced repetition history
   - `definitions` - Word definitions
   - `audio` - TTS audio cache

3. **Row Counts**
   - Displays count for each critical table
   - Helps verify data completeness

**Example Output:**
```
Tables in database: 18
  - user_preferences: 2 rows
  - saved_words: 34 rows
  - reviews: 24 rows
  - definitions: 8242 rows
  - audio: 326 rows
```

### Phase 7: Service Restart

**What happens:**
```bash
docker-compose up -d
```

**Services restarted:**
- `postgres` - Database (already running, healthy check)
- `app` - Flask backend
- `nginx` - Reverse proxy
- `prometheus` - Metrics (if configured)
- `grafana` - Dashboards (if configured)
- `loki` - Logging (if configured)

**Health Check:**
```bash
curl http://localhost:5000/health
```

---

## Usage Examples

### Example 1: Regular Development Sync

**Scenario:** You want to pull latest production data for development

```bash
cd /Users/biubiu/projects/dogetionary
./scripts/sync_db_from_remote.sh
```

**Expected flow:**
1. Prompt: "This will DESTROY the current local database..."
2. Type: `yes` + Enter
3. Wait 5-10 minutes
4. Database synced, services restarted
5. Continue development with production data

### Example 2: Snapshot Only (No Restore)

**Scenario:** You want to backup production without affecting local database

```bash
./scripts/sync_db_from_remote.sh --snapshot-only
```

**Result:**
- Snapshot saved to `/Volumes/databank/`
- Local database unchanged
- Can restore later with `--restore-from`

### Example 3: Restore from Previous Snapshot

**Scenario:** You have an older snapshot and want to restore it

```bash
# List available snapshots
ls -lh /Volumes/databank/dogetionary_remote_snapshot_*.sql.gz

# Restore specific snapshot
./scripts/sync_db_from_remote.sh --restore-from \
  /Volumes/databank/dogetionary_remote_snapshot_20251213_193943.sql.gz
```

### Example 4: Dry Run (Test Without Executing)

**Scenario:** You want to see what would happen without making changes

```bash
./scripts/sync_db_from_remote.sh --dry-run
```

**Output:**
```
[DRY RUN] Would create: /Volumes/databank/dogetionary_local_backup_...
[DRY RUN] Would pull snapshot to: /Volumes/databank/...
[DRY RUN] Would stop: app, nginx
[DRY RUN] Would restore database from snapshot
...
```

### Example 5: Quick Sync (Skip Local Backup)

**Scenario:** You don't care about current local data

```bash
./scripts/sync_db_from_remote.sh --skip-local-backup
```

**Warning:** No safety net if restore fails!

---

## Troubleshooting

### Issue 1: SSH Connection Fails

**Error:**
```
Cannot connect to remote server
```

**Solutions:**

1. **Check SSH key:**
   ```bash
   ssh-add -l  # List loaded keys
   ssh root@69.167.170.85 echo "test"  # Manual test
   ```

2. **Try with password:**
   - Script will prompt for password if key fails
   - Consider setting up key-based auth:
     ```bash
     ssh-copy-id root@69.167.170.85
     ```

3. **Network issues:**
   - Verify you can reach the server
   - Check VPN connection if required

### Issue 2: Container Not Running

**Error:**
```
Local PostgreSQL container 'dogetionary-postgres-1' is not running
```

**Solution:**
- Script auto-starts it, but if it fails:
  ```bash
  cd /Users/biubiu/projects/dogetionary
  docker-compose up -d postgres
  docker-compose ps  # Verify it's running
  ```

### Issue 3: Disk Space Full

**Error:**
```
No space left on device
```

**Solutions:**

1. **Check available space:**
   ```bash
   df -h /Volumes/databank
   ```

2. **Clean old snapshots:**
   ```bash
   ls -lh /Volumes/databank/dogetionary_*.sql.gz
   rm /Volumes/databank/dogetionary_remote_snapshot_OLD_DATE.sql.gz
   ```

3. **Estimate required space:**
   - Snapshot size: ~2-3GB (compressed)
   - Local backup: ~2-3GB (compressed)
   - Total: ~5-6GB minimum

### Issue 4: Restore Fails Mid-Process

**Error:**
```
ERROR: Database restore failed
```

**Recovery:**

1. **Check the log:**
   ```bash
   tail -100 /Volumes/databank/db_sync_TIMESTAMP.log
   ```

2. **Restore from safety backup:**
   ```bash
   # Find your backup
   ls -lh /Volumes/databank/dogetionary_local_backup_*.sql.gz

   # Restore it
   gunzip -c /Volumes/databank/dogetionary_local_backup_TIMESTAMP.sql.gz | \
     docker exec -i dogetionary-postgres-1 \
       psql -U dogeuser -d dogetionary

   # Restart services
   cd /Users/biubiu/projects/dogetionary
   docker-compose up -d
   ```

### Issue 5: Version Mismatch

**Error:**
```
pg_restore: [archiver] unsupported version
```

**Check versions:**
```bash
# Local
docker exec dogetionary-postgres-1 psql -U dogeuser -V

# Remote
ssh root@69.167.170.85 \
  "su - tianzhic -c 'docker exec dogetionary_postgres_1 psql -U dogeuser -V'"
```

**Solution:**
- Both should be PostgreSQL 15
- If different, update containers to match

### Issue 6: Application Won't Start

**Error:**
```
Application health check failed
```

**Solutions:**

1. **Check logs:**
   ```bash
   docker-compose logs app
   ```

2. **Verify database:**
   ```bash
   docker exec dogetionary-postgres-1 \
     psql -U dogeuser -d dogetionary -c "\dt"
   ```

3. **Restart services:**
   ```bash
   docker-compose restart app
   ```

4. **Check database connection:**
   ```bash
   docker exec dogetionary-postgres-1 \
     psql -U dogeuser -d dogetionary -c "SELECT 1"
   ```

---

## Technical Details

### File Naming Convention

**Snapshots:**
```
dogetionary_remote_snapshot_YYYYMMDD_HHMMSS.sql.gz
                           └─ 20251213_193943.sql.gz
                              Year─┘ │││││ │││││└─ Second
                                Month┘││││ │││└─ Minute
                                  Day──┘││ ││└─ Hour
                                        └─┴─┴─ Time separator
```

**Local Backups:**
```
dogetionary_local_backup_YYYYMMDD_HHMMSS.sql.gz
```

**Logs:**
```
db_sync_YYYYMMDD_HHMMSS.log
```

### Compression Details

**gzip -9 settings:**
- Algorithm: DEFLATE (maximum compression)
- Compression ratio: ~80% for text/SQL data
- Trade-off: Slower compression, better ratio
- CPU usage: Moderate

**Example:**
- Uncompressed: 10GB
- Compressed: ~2GB (-80%)

### Database Dump Format

The script uses SQL format (plain text), not custom format:

**Advantages:**
- Human-readable
- Easy to inspect
- Compatible across versions
- Can be edited if needed

**Contents:**
```sql
-- PostgreSQL database dump

-- Dumped from database version 15.x
-- Dumped by pg_dump version 15.x

SET statement_timeout = 0;
SET lock_timeout = 0;
...

-- Schema creation
CREATE TABLE user_preferences (...);
CREATE TABLE saved_words (...);
...

-- Data insertion
COPY user_preferences (...) FROM stdin;
data1
data2
\.

-- Indexes and constraints
CREATE INDEX idx_saved_words_user_id ON saved_words(...);
...

-- Triggers
CREATE TRIGGER ...;
```

### Security Considerations

**Password Storage:**
- Database password in script: `dogepass`
- Acceptable for local development
- **DO NOT** use for production scripts

**SSH Access:**
- Uses root user (required for su)
- Switches to tianzhic for Docker access
- Key-based auth recommended

**File Permissions:**
```bash
# Script permissions
chmod 755 sync_db_from_remote.sh

# Snapshot permissions (contains sensitive data)
chmod 600 /Volumes/databank/*.sql.gz
```

### Performance Optimization

**Network Transfer:**
- SSH compression: Enabled by default
- gzip -9: Maximum compression
- Single pipe: No intermediate files on remote

**Database Operations:**
- `--if-exists`: Prevents errors if DB doesn't exist
- `ON_ERROR_STOP=on`: Fails fast on errors
- Connection termination: Clean shutdown

**Disk I/O:**
- Streaming decompression: No temp files
- Direct pipe to psql: Minimal disk writes

### Logging

**Log Format:**
```
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message
[2025-12-13 19:39:43] [INFO] Log file: /Volumes/databank/db_sync_20251213_193943.log
[2025-12-13 19:39:45] [SUCCESS] Pre-flight checks passed
[2025-12-13 19:58:10] [SUCCESS] Remote snapshot pulled successfully
```

**Log Levels:**
- `INFO` - Informational messages
- `SUCCESS` - Operation completed successfully
- `WARNING` - Non-fatal issues
- `ERROR` - Fatal errors

**Log Location:**
- `/Volumes/databank/db_sync_TIMESTAMP.log`
- Persists after script completion
- Useful for debugging

### Script Variables Reference

**Remote Configuration:**
```bash
REMOTE_HOST="69.167.170.85"
REMOTE_USER="root"
REMOTE_APP_USER="tianzhic"
REMOTE_PROJECT_PATH="/home/tianzhic/dogetionary"
REMOTE_CONTAINER="dogetionary_postgres_1"  # Uses underscores
```

**Local Configuration:**
```bash
LOCAL_PROJECT_PATH="/Users/biubiu/projects/dogetionary"
LOCAL_CONTAINER="dogetionary-postgres-1"  # Uses dashes
BACKUP_DIR="/Volumes/databank"
LOG_DIR="/Volumes/databank"
```

**Database Configuration:**
```bash
DB_NAME="dogetionary"
DB_USER="dogeuser"
DB_PASS="dogepass"
```

---

## Best Practices

### When to Sync

**Good times:**
- Start of development session
- After major production data changes
- Before testing with realistic data
- Weekly routine sync

**Avoid syncing:**
- During active development (will lose local changes)
- When local database has test data you need
- Without understanding current local state

### Data Safety

**Always:**
1. Review what data you'll lose locally
2. Keep local safety backup (don't skip it)
3. Verify restore completed successfully
4. Test application after sync

**Never:**
1. Run this script on production server
2. Skip confirmation prompts carelessly
3. Delete snapshots immediately (keep for rollback)

### Storage Management

**Retention Policy:**
- Keep last 3-5 snapshots
- Delete snapshots older than 30 days
- Monitor `/Volumes/databank` usage

**Cleanup Example:**
```bash
# Keep only last 5 snapshots
cd /Volumes/databank
ls -t dogetionary_remote_snapshot_*.sql.gz | tail -n +6 | xargs rm

# Delete snapshots older than 30 days
find /Volumes/databank -name "dogetionary_*.sql.gz" -mtime +30 -delete
```

### Workflow Integration

**Development Workflow:**
1. Pull latest code: `git pull`
2. Sync database: `./scripts/sync_db_from_remote.sh`
3. Run migrations (if any): `./scripts/run_migrations.sh`
4. Start development

**Testing Workflow:**
1. Sync database (fresh production data)
2. Run integration tests
3. Verify against production-like data

---

## FAQ

**Q: How often should I sync?**
A: Depends on your workflow. Daily for active development, weekly for maintenance work.

**Q: Can I sync while the app is running?**
A: Yes, the script stops dependent services automatically.

**Q: What if I  accidentally run this on production?**
A: The script has safeguards, but **NEVER** run it on production. It's designed for local development only.

**Q: How much disk space do I need?**
A: At least 5GB for snapshots + backups. More if you keep multiple snapshots.

**Q: Can I cancel mid-operation?**
A: Yes (Ctrl+C), but database may be in inconsistent state. Restore from safety backup if needed.

**Q: Why is my snapshot 2GB but database is 10GB?**
A: gzip compression (~80%). The actual database is 10GB uncompressed.

**Q: Can I use this for automated backups?**
A: Yes, use `--snapshot-only` in a cron job. Don't auto-restore without supervision.

**Q: How do I verify the sync worked?**
A: Script shows row counts. You can also:
```bash
docker exec dogetionary-postgres-1 \
  psql -U dogeuser -d dogetionary -c "SELECT COUNT(*) FROM saved_words"
```

**Q: What's the difference between snapshot and backup?**
A: Snapshot = remote production data, Backup = local safety copy

**Q: Can I edit the snapshot before restoring?**
A: Yes, it's plain SQL. Decompress, edit, recompress. Not recommended unless you know what you're doing.

---

## Related Documentation

- [Database Schema Documentation](../db/init.sql)
- [Integration Tests](../scripts/integration_test.py)
- [Docker Compose Setup](../docker-compose.yml)
- [Script Source Code](../scripts/sync_db_from_remote.sh)
- [Detailed Script Documentation](../scripts/README_DB_SYNC.md)

---

## Change Log

**2025-12-13:**
- Initial version created
- Tested with 2.2GB production database
- Verified exact match between remote and local
- Added connection termination fix
- Updated container naming (dashes vs underscores)

---

## Support

**Issues:**
- Check log file: `/Volumes/databank/db_sync_TIMESTAMP.log`
- Review error messages
- See Troubleshooting section above

**Common Gotchas:**
1. Container name mismatch (dashes vs underscores)
2. Insufficient disk space
3. SSH key not loaded
4. Existing database connections
5. Version mismatches

**Getting Help:**
- Review this guide thoroughly
- Check script output and logs
- Verify prerequisites are met
- Test with `--dry-run` first

---

**Last Updated:** December 13, 2025
**Script Version:** 1.0
**Tested On:** macOS, PostgreSQL 15, Docker Compose v2+
