# Loki Logging Fix - Production Deployment Guide

## Problem Summary

Loki had no logs in production because:
1. ❌ `docker-compose.override.yml` (local-only) was mounting nginx logs
2. ❌ Production didn't have log directories created
3. ❌ Promtail couldn't access nginx logs (trapped in container)
4. ❌ File path mismatches between Promtail config and actual mounts

## What Was Fixed

### Files Modified

1. **docker-compose.yml**
   - Added nginx log volume mount: `./logs/nginx:/var/log/nginx`
   - Updated Promtail volume mounts to use correct paths
   - Now works in BOTH local and production

2. **docker-compose.override.yml**
   - Removed duplicate nginx log mount
   - Added comment explaining the change

3. **promtail/promtail-config.yml**
   - Updated all `__path__` values to match new mounts:
     - `/logs/app.log*` → `/logs/app/app.log*`
     - `/logs/error.log*` → `/logs/app/error.log*`
     - `/var/log/nginx/access.log` → `/logs/nginx/access.log`
     - `/var/log/nginx/error.log` → `/logs/nginx/error.log`

---

## Pre-Deployment: Create Log Directories

**On production server, run these commands BEFORE deploying:**

```bash
# Navigate to project directory
cd /path/to/dogetionary

# Create log directories with correct permissions
mkdir -p logs/app logs/nginx

# Set permissions (important for Promtail to read)
chmod 755 logs/app logs/nginx

# Verify directories exist
ls -la logs/
```

Expected output:
```
drwxr-xr-x  2 user user 4096 Dec 14 10:00 app
drwxr-xr-x  2 user user 4096 Dec 14 10:00 nginx
```

---

## Deployment Steps

### 1. Pull Latest Changes

```bash
git pull
```

### 2. Stop Affected Services

```bash
# Stop services that need reconfiguration
docker-compose stop nginx promtail
```

### 3. Remove Old Promtail Container

```bash
# Remove to force recreation with new volume mounts
docker-compose rm -f promtail
```

### 4. Restart Services in Correct Order

```bash
# Start nginx (will create log files in ./logs/nginx)
docker-compose up -d nginx

# Wait 5 seconds for nginx to start logging
sleep 5

# Start promtail (will read from ./logs/app and ./logs/nginx)
docker-compose up -d promtail

# Restart loki to ensure clean state
docker-compose restart loki
```

### 5. Verify Deployment

```bash
# Check all services are running
docker-compose ps nginx promtail loki

# Check log directories have files
ls -la logs/app/
ls -la logs/nginx/

# Check nginx is writing logs
docker exec dogetionary-nginx-1 ls -la /var/log/nginx/

# Check promtail can see the logs
docker exec dogetionary-promtail ls -la /logs/app/
docker exec dogetionary-promtail ls -la /logs/nginx/

# Check promtail logs for errors
docker logs dogetionary-promtail --tail 50
```

---

## Expected Results

### Log Directory Contents

After deployment, you should see:

```bash
# ls -la logs/app/
-rw-r--r-- 1 user user 1048576 Dec 14 10:05 app.log
-rw-r--r-- 1 user user       0 Dec 14 10:00 error.log

# ls -la logs/nginx/
-rw-r--r-- 1 nginx nginx 524288 Dec 14 10:05 access.log
-rw-r--r-- 1 nginx nginx   2048 Dec 14 10:05 error.log
```

### Promtail Logs (Good)

```
level=info msg="Successfully pushed logs to Loki"
level=info msg="Seeked /logs/app/app.log - &{Offset:0 Whence:0}"
level=info msg="Seeked /logs/nginx/access.log - &{Offset:0 Whence:0}"
```

### Promtail Logs (Bad - Need to Fix)

```
level=error msg="error tailing file" filename="/logs/app/app.log" error="no such file or directory"
```

---

## Verification in Grafana

### 1. Access Grafana

```
https://kwafy.com/grafana
Username: admin
Password: admin123
```

### 2. Check Loki Data Source

1. Go to **Configuration** → **Data Sources** → **Loki**
2. Click **Test** button
3. Should show: ✅ "Data source is working"

### 3. Query Logs

1. Go to **Explore** → Select **Loki**
2. Run these queries:

**Test app logs:**
```logql
{job="dogetionary"}
```

**Test nginx access logs:**
```logql
{job="nginx", log_type="access"}
```

**Test nginx error logs:**
```logql
{job="nginx", log_type="error"}
```

**Test error-only logs:**
```logql
{job="dogetionary", log_type="error"}
```

Each query should return log entries. If you see "No logs found", proceed to troubleshooting.

---

## Troubleshooting

### Issue 1: "No logs found" in Grafana

**Diagnosis:**
```bash
# Check if Promtail is sending to Loki
docker logs dogetionary-promtail --tail 100 | grep -i error

# Check if Loki is receiving data
docker logs dogetionary-loki --tail 100 | grep -i error

# Check Loki API directly
curl http://localhost:3100/loki/api/v1/label
```

**Solution:**
```bash
# Restart Promtail and Loki
docker-compose restart promtail loki

# Wait 30 seconds
sleep 30

# Generate some logs by making API requests
curl https://kwafy.com/api/health

# Check Grafana again
```

---

### Issue 2: Permission Denied Errors

**Symptoms:**
```
level=error msg="error tailing file" error="permission denied"
```

**Solution:**
```bash
# Fix permissions
chmod 644 logs/app/*.log
chmod 644 logs/nginx/*.log
chmod 755 logs/app logs/nginx

# Restart promtail
docker-compose restart promtail
```

---

### Issue 3: Log Files Don't Exist

**Symptoms:**
```
ls: cannot access 'logs/app/app.log': No such file or directory
```

**Solution:**
```bash
# Check if app container has logs
docker exec dogetionary-app-1 ls -la /app/logs/

# If logs exist in container but not on host:
# 1. Stop container
docker-compose stop app

# 2. Verify volume mount in docker-compose.yml
grep -A 3 "app:" docker-compose.yml

# 3. Restart app
docker-compose up -d app

# 4. Make a request to generate logs
curl https://kwafy.com/api/health

# 5. Check again
ls -la logs/app/
```

---

### Issue 4: Nginx Logs Empty

**Symptoms:**
```
-rw-r--r-- 1 nginx nginx 0 Dec 14 10:05 access.log
```

**Solution:**
```bash
# Make some requests to generate logs
curl https://kwafy.com/
curl https://kwafy.com/api/health
curl https://kwafy.com/grafana/

# Check nginx logs now
tail -f logs/nginx/access.log
```

---

### Issue 5: Promtail Not Finding Files

**Symptoms:**
```
level=warn msg="no files to scrape"
```

**Solution:**
```bash
# Verify Promtail mounts
docker inspect dogetionary-promtail | grep -A 10 Mounts

# Should see:
# "Source": "/path/to/dogetionary/logs/app"
# "Destination": "/logs/app"
# "Source": "/path/to/dogetionary/logs/nginx"
# "Destination": "/logs/nginx"

# If mounts are wrong, recreate container
docker-compose up -d --force-recreate promtail
```

---

## Rollback Procedure

If something goes wrong:

```bash
# 1. Stop new services
docker-compose stop nginx promtail loki

# 2. Revert git changes
git checkout HEAD~1

# 3. Restart with old config
docker-compose up -d nginx promtail loki
```

---

## Summary of Changes

### Volume Mounts (Before → After)

**Nginx:**
- Before: Only in `docker-compose.override.yml` (local only)
- After: In `docker-compose.yml` (works everywhere)

**Promtail:**
- Before: `./logs/app:/logs` + `/var/log:/var/log`
- After: `./logs/app:/logs/app` + `./logs/nginx:/logs/nginx`

**Paths in Promtail Config:**
- Before: `/logs/app.log`, `/var/log/nginx/access.log`
- After: `/logs/app/app.log`, `/logs/nginx/access.log`

### Why This Fixes Production

1. ✅ Log directories explicitly created before deployment
2. ✅ Nginx logs accessible to Promtail via `./logs/nginx` mount
3. ✅ Consistent paths between docker-compose.yml and promtail-config.yml
4. ✅ No dependency on `docker-compose.override.yml` (production doesn't use it)
5. ✅ Promtail can read all logs from `/logs/app/` and `/logs/nginx/`

---

## Post-Deployment Monitoring

After successful deployment, monitor for 24 hours:

```bash
# Check log file sizes growing
watch -n 60 'ls -lh logs/app/ logs/nginx/'

# Check Promtail is actively sending
docker logs dogetionary-promtail --tail 10 --follow

# Check Loki storage growing
docker exec dogetionary-loki du -sh /loki/chunks/
```

---

## Security Note

The `admin123` Grafana password should be changed in production:

```bash
# Update docker-compose.yml
# Find: GF_SECURITY_ADMIN_PASSWORD=admin123
# Replace with strong password

# Restart Grafana
docker-compose restart grafana
```
