# Database Snapshot & Restore Script

## Overview

The `sync_db_from_remote.sh` script automates the process of pulling a PostgreSQL database snapshot from the remote production server and restoring it to your local development environment.

**Location**: `scripts/sync_db_from_remote.sh`

## Features

✅ **Automated workflow**: Complete end-to-end snapshot and restore process
✅ **Safety first**: Creates local backup before any destructive operations
✅ **Comprehensive logging**: All operations logged to `/Volumes/databank/db_sync_TIMESTAMP.log`
✅ **Error handling**: Exits on first error, prevents partial operations
✅ **Pre-flight checks**: Validates prerequisites before starting
✅ **Verification**: Checks database integrity after restore
✅ **Flexible modes**: Snapshot-only, restore-from-file, dry-run options

## Prerequisites

1. **SSH Access**: Must have SSH access to `root@69.167.170.85`
   - Key-based authentication recommended
   - Will prompt for password if key-based auth fails

2. **Storage**: `/Volumes/databank` directory must exist and be writable

3. **Docker**: Docker and docker-compose must be installed and running locally

4. **Local Setup**: Local dogetionary project at `/Users/biubiu/projects/dogetionary`

## Quick Start

### Basic Usage (Full Sync)

Pull snapshot from remote and restore to local database:

```bash
cd /Users/biubiu/projects/dogetionary
./scripts/sync_db_from_remote.sh
```

**This will:**
1. Create a local safety backup
2. Pull snapshot from remote production server
3. Stop local app/nginx services
4. Drop and recreate local database
5. Restore data from snapshot
6. Verify restoration
7. Restart all services
8. Check application health

### Snapshot Only (No Restore)

Pull snapshot without restoring:

```bash
./scripts/sync_db_from_remote.sh --snapshot-only
```

**Use case**: Create a backup without modifying local database

### Restore from Existing Snapshot

Restore from a previously downloaded snapshot:

```bash
./scripts/sync_db_from_remote.sh --restore-from /Volumes/databank/dogetionary_remote_snapshot_20251213_120000.sql.gz
```

**Use case**: Re-restore from same snapshot, or restore from older backup

### Dry Run

See what would happen without actually doing it:

```bash
./scripts/sync_db_from_remote.sh --dry-run
```

**Use case**: Test script, verify configuration, or understand workflow

## Command Line Options

| Option | Description |
|--------|-------------|
| `--skip-local-backup` | Skip creating local safety backup (not recommended) |
| `--snapshot-only` | Only pull snapshot, don't restore to local database |
| `--restore-from FILE` | Restore from existing snapshot file instead of pulling new one |
| `--dry-run` | Show what would be done without executing commands |
| `-h`, `--help` | Show help message |

## Remote Server Configuration

The script connects to the remote server with these settings:

- **Host**: `69.167.170.85`
- **SSH User**: `root`
- **Application User**: `tianzhic` (accessed via `su -`)
- **Project Path**: `/home/tianzhic/dogetionary`
- **Container Name**: `dogetionary_postgres_1`

## File Locations

### Snapshots

All snapshots are saved to `/Volumes/databank/` with timestamp:

```
/Volumes/databank/
├── dogetionary_remote_snapshot_20251213_143022.sql.gz
├── dogetionary_remote_snapshot_20251213_150015.sql.gz
├── dogetionary_local_backup_20251213_143022.sql.gz
└── ...
```

**Naming convention:**
- Remote snapshots: `dogetionary_remote_snapshot_YYYYMMDD_HHMMSS.sql.gz`
- Local backups: `dogetionary_local_backup_YYYYMMDD_HHMMSS.sql.gz`

### Logs

All operations are logged to `/Volumes/databank/` with timestamp:

```
/Volumes/databank/
├── db_sync_20251213_143022.log
├── db_sync_20251213_150015.log
└── ...
```

Each log contains:
- Timestamp for each operation
- All commands executed
- Success/warning/error messages
- Database verification results

## Workflow Details

### Step-by-Step Process

1. **Pre-flight Checks**
   - Verify `/Volumes/databank` exists and is writable
   - Check docker-compose is available
   - Verify local project exists
   - Test SSH connection to remote server
   - Ensure local PostgreSQL container is running

2. **Remote Database Info**
   - Query remote database size
   - Display to user for awareness

3. **Local Safety Backup** (unless `--skip-local-backup`)
   - Create compressed backup of current local database
   - Save to `/Volumes/databank/dogetionary_local_backup_TIMESTAMP.sql.gz`
   - Verify file creation and size

4. **Pull Remote Snapshot**
   - SSH to remote server as `root`
   - Switch to `tianzhic` user
   - Execute `pg_dump` inside remote Docker container
   - Pipe output through SSH, compress with gzip
   - Save to `/Volumes/databank/dogetionary_remote_snapshot_TIMESTAMP.sql.gz`
   - Verify gzip file integrity

5. **Stop Dependent Services**
   - Stop `app` and `nginx` containers
   - Keep `postgres` running (needed for restore)

6. **User Confirmation**
   - Prompt user to confirm destructive operation
   - Show snapshot file and size
   - Allow cancellation

7. **Drop & Recreate Database**
   - Drop existing `dogetionary` database
   - Create fresh empty `dogetionary` database

8. **Restore Data**
   - Decompress snapshot file
   - Pipe into `psql` with `ON_ERROR_STOP=on`
   - Monitor for errors during restore

9. **Verify Restoration**
   - Count tables in database
   - Check for critical tables (user_preferences, saved_words, reviews, definitions)
   - Display row counts for verification

10. **Restart Services**
    - Start all docker-compose services
    - Wait for services to become healthy

11. **Health Check**
    - Test `http://localhost:5000/health` endpoint
    - Verify application is responding

12. **Summary Report**
    - Display completion status
    - Show snapshot location
    - Show log file location
    - Display total duration

## Error Handling

### What Happens on Error

The script uses `set -e` (exit on error), so:
- **Any command failure stops the script immediately**
- **No partial operations** - either completes fully or fails cleanly
- **All errors are logged** to the log file

### Common Issues & Solutions

#### SSH Connection Fails

```
Error: Cannot connect to remote server
```

**Solution**:
- Verify you can SSH manually: `ssh root@69.167.170.85`
- Check if SSH key is loaded: `ssh-add -l`
- Script will work with password auth, but key-based is preferred

#### Remote Container Not Running

```
Error: docker exec failed on remote
```

**Solution**:
- SSH to remote server
- `su - tianzhic`
- `cd ~/dogetionary`
- `docker-compose ps` to check container status
- `docker-compose up -d postgres` to start if needed

#### Local Container Not Running

The script will automatically start the local postgres container if not running.

#### Restore Fails Mid-Process

```
Error: Database restore failed
```

**Recovery**:
1. Check log file for specific SQL errors
2. Restore from safety backup:
   ```bash
   cd /Users/biubiu/projects/dogetionary
   gunzip -c /Volumes/databank/dogetionary_local_backup_TIMESTAMP.sql.gz | \
     docker exec -i dogetionary_postgres_1 psql -U dogeuser -d dogetionary
   ```
3. Restart services: `docker-compose up -d`

#### Disk Space Full

```
Error: No space left on device
```

**Solution**:
- Clean old snapshots from `/Volumes/databank/`
- Snapshots compress ~70-90%, but can still be large
- Keep only recent snapshots, delete old ones

## Safety Features

### Local Backup

**Why**: Before any destructive operation, script creates a compressed backup of your current local database.

**Location**: `/Volumes/databank/dogetionary_local_backup_TIMESTAMP.sql.gz`

**Skip**: Use `--skip-local-backup` flag (not recommended unless you have another backup)

### User Confirmation

Before dropping the database, script prompts:
```
This will DESTROY the current local database and replace it with the snapshot. Continue? (yes/no):
```

Type `yes` to proceed, anything else cancels.

### Integrity Verification

After pulling snapshot, script tests gzip integrity:
```bash
gunzip -t snapshot.sql.gz
```

If corrupted, script exits before attempting restore.

### Error Stop on Restore

During restore, uses `--set ON_ERROR_STOP=on` flag:
- Stops immediately if any SQL error occurs
- Prevents partial/corrupted restoration
- Makes failures obvious and safe

## Performance Notes

### Expected Duration

Depends on database size and network speed:

| DB Size | Snapshot Pull | Restore | Total |
|---------|---------------|---------|-------|
| 100 MB  | ~30 sec      | ~10 sec | ~1 min |
| 500 MB  | ~2 min       | ~30 sec | ~3 min |
| 1 GB    | ~4 min       | ~1 min  | ~6 min |
| 5 GB    | ~20 min      | ~5 min  | ~30 min |

*Note: Times are estimates with gzip compression and good network*

### Compression Ratios

PostgreSQL data compresses well with gzip -9:
- Text-heavy data: 85-95% compression
- Mixed data: 70-85% compression
- Binary data: 40-60% compression

Average: **~80% compression** (5GB → 1GB compressed)

## Advanced Usage

### Automated Scheduled Sync

**Not included** - this script is designed for on-demand use.

For scheduled syncing, consider:
- Add to cron with `--snapshot-only` flag
- Keep snapshots without auto-restore
- Manually restore when needed

Example cron (daily at 2 AM):
```cron
0 2 * * * /Users/biubiu/projects/dogetionary/scripts/sync_db_from_remote.sh --snapshot-only >> /Volumes/databank/cron.log 2>&1
```

### Multiple Remote Environments

To support multiple remotes (staging, production):
1. Copy script with different names
2. Modify `REMOTE_HOST` and `REMOTE_APP_USER` variables
3. Or create wrapper script that sets environment variables

### Selective Table Restore

The script restores the entire database. For selective tables:

1. Pull snapshot: `./scripts/sync_db_from_remote.sh --snapshot-only`
2. Extract specific table manually:
   ```bash
   gunzip -c /Volumes/databank/snapshot.sql.gz | \
     grep -A 10000 "COPY saved_words" | \
     docker exec -i dogetionary_postgres_1 psql -U dogeuser -d dogetionary
   ```

Or use `pg_restore` with selective flags (requires .tar format instead of .sql).

## Troubleshooting

### View Logs

```bash
tail -f /Volumes/databank/db_sync_TIMESTAMP.log
```

### Check Container Status

```bash
cd /Users/biubiu/projects/dogetionary
docker-compose ps
```

### Verify Database

```bash
docker exec -i dogetionary_postgres_1 psql -U dogeuser -d dogetionary -c "\dt"
```

### Test Application

```bash
curl http://localhost:5000/health
```

### Manual Restore

If script fails but you have snapshot:

```bash
cd /Users/biubiu/projects/dogetionary

# Stop services
docker-compose stop app nginx

# Drop database
docker exec -i dogetionary_postgres_1 dropdb -U dogeuser dogetionary

# Create database
docker exec -i dogetionary_postgres_1 createdb -U dogeuser dogetionary

# Restore
gunzip -c /Volumes/databank/snapshot.sql.gz | \
  docker exec -i dogetionary_postgres_1 psql -U dogeuser -d dogetionary

# Restart
docker-compose up -d
```

## Examples

### Example 1: Daily Development Sync

```bash
# Pull fresh production data every morning
cd /Users/biubiu/projects/dogetionary
./scripts/sync_db_from_remote.sh
```

### Example 2: Create Backup Without Restore

```bash
# Pull snapshot for safekeeping, don't modify local
./scripts/sync_db_from_remote.sh --snapshot-only
```

### Example 3: Test Before Restoring

```bash
# First, see what would happen
./scripts/sync_db_from_remote.sh --dry-run

# If looks good, run for real
./scripts/sync_db_from_remote.sh
```

### Example 4: Restore from Old Snapshot

```bash
# List available snapshots
ls -lh /Volumes/databank/dogetionary_remote_snapshot_*.sql.gz

# Restore from specific snapshot
./scripts/sync_db_from_remote.sh --restore-from /Volumes/databank/dogetionary_remote_snapshot_20251210_140000.sql.gz
```

## Script Variables Reference

You can modify these variables at the top of the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `REMOTE_HOST` | `69.167.170.85` | Remote server IP/hostname |
| `REMOTE_USER` | `root` | SSH user for remote connection |
| `REMOTE_APP_USER` | `tianzhic` | Application user on remote (via su) |
| `REMOTE_PROJECT_PATH` | `/home/tianzhic/dogetionary` | Project path on remote |
| `REMOTE_CONTAINER` | `dogetionary_postgres_1` | PostgreSQL container name on remote |
| `LOCAL_PROJECT_PATH` | `/Users/biubiu/projects/dogetionary` | Local project path |
| `LOCAL_CONTAINER` | `dogetionary_postgres_1` | Local PostgreSQL container name |
| `BACKUP_DIR` | `/Volumes/databank` | Where snapshots are saved |
| `LOG_DIR` | `/Volumes/databank` | Where logs are saved |
| `DB_NAME` | `dogetionary` | Database name |
| `DB_USER` | `dogeuser` | Database user |
| `DB_PASS` | `dogepass` | Database password |

## Security Notes

### Credentials in Script

The script contains database password in plain text. This is acceptable for local development, but:

- **Do not commit** to public repositories
- Script is in local project, not shared
- Consider using `.pgpass` file for production use

### SSH Key-Based Auth

**Recommended**: Set up SSH key-based authentication to remote server:

```bash
# Generate key if you don't have one
ssh-keygen -t ed25519

# Copy to remote server
ssh-copy-id root@69.167.170.85
```

Benefits:
- No password prompts
- More secure than password
- Enables automation

### File Permissions

Snapshot files contain your entire database:

```bash
# Check permissions
ls -l /Volumes/databank/*.sql.gz

# Should be readable only by you
chmod 600 /Volumes/databank/*.sql.gz
```

## FAQ

**Q: How often should I sync?**
A: Depends on your workflow. Daily is common for active development. Weekly for less active projects.

**Q: Do I need to stop local services before running?**
A: No, script handles this automatically.

**Q: Can I run this on production?**
A: **NO!** This script is designed for development. It DESTROYS the target database. Never run on production.

**Q: What if I accidentally run this on production?**
A: That's why user confirmation is required. Always read prompts carefully.

**Q: How much disk space do I need?**
A: At minimum: 2x compressed snapshot size (for snapshot + local backup). Recommend: 5x for safety.

**Q: Can I cancel mid-operation?**
A: Yes, Ctrl+C will stop. However, if database drop/restore already started, database may be in inconsistent state. Restore from safety backup if needed.

**Q: Why gzip -9 instead of -6 (default)?**
A: Maximum compression saves significant transfer time and disk space. CPU overhead is minimal for this use case.

**Q: Can I use this with PostgreSQL 14 or 16?**
A: Yes, but ensure both remote and local use same major version. Minor version differences are usually fine.

## Related Files

- Main script: `scripts/sync_db_from_remote.sh`
- Integration tests: `scripts/integration_test.py`
- Database schema: `db/init.sql`
- Docker compose: `docker-compose.yml`

## Getting Help

If you encounter issues:

1. Check the log file: `/Volumes/databank/db_sync_TIMESTAMP.log`
2. Run with `--dry-run` to see what would happen
3. Try each step manually to isolate issue
4. Check Prerequisites section above

---

**Last Updated**: 2025-12-13
**Script Version**: 1.0
**Compatible with**: PostgreSQL 15, Docker Compose v2+
