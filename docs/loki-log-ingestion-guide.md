# Loki Log Ingestion Guide

## Problem Identified

**Issue:** Loki is working locally but not in production.

**Root Cause:** **Promtail is not running on the production server.**

Loki itself is running fine, but without Promtail (the log collection agent), no logs are being sent to Loki.

---

## How Log Ingestion Works

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                   APPLICATION LOGS                           │
│                                                              │
│  Flask App → /logs/app/app.log                              │
│  Flask Errors → /logs/app/error.log                         │
│  Nginx Access → /logs/nginx/access.log                      │
│  Nginx Errors → /logs/nginx/error.log                       │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ (file system)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      PROMTAIL                                │
│  (Log Collection Agent)                                      │
│                                                              │
│  - Watches log files (tail -f)                              │
│  - Parses log lines (regex)                                 │
│  - Extracts timestamps                                      │
│  - Adds labels (job, app, level)                            │
│  - Handles multiline logs                                   │
│  - Sends to Loki via HTTP                                   │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ (HTTP POST)
                           │ http://loki:3100/loki/api/v1/push
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                         LOKI                                 │
│  (Log Aggregation System)                                    │
│                                                              │
│  - Receives logs from Promtail                              │
│  - Indexes by labels                                        │
│  - Stores in filesystem (/loki/chunks)                      │
│  - Provides query API                                       │
│  - Retention: 7 days (168h)                                 │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ (HTTP API)
                           │ http://loki:3100/loki/api/v1/query
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                       GRAFANA                                │
│  (Visualization)                                             │
│                                                              │
│  - Queries Loki for logs                                    │
│  - Displays in UI                                           │
│  - Provides search/filtering                                │
│  - Shows in real-time                                       │
└─────────────────────────────────────────────────────────────┘
```

---

## Detailed Log Flow

### Step 1: Application Writes Logs

**Flask App** writes logs to files:
```
/logs/app/app.log       # All application logs
/logs/app/error.log     # Error logs only
```

**Log Format:**
```
2025-12-14 16:40:23,456 - app.services.user_service - INFO - User 123 saved word: hello
2025-12-14 16:40:24,789 - app.handlers.words - ERROR - Failed to fetch definition
Traceback (most recent call last):
  File "handlers/words.py", line 45, in get_definition
    ...
```

### Step 2: Promtail Watches Files

**Promtail Configuration:** `promtail/promtail-config.yml`

```yaml
scrape_configs:
  - job_name: dogetionary_app
    static_configs:
      - targets:
          - localhost
        labels:
          job: dogetionary
          app: flask
          log_type: all
          __path__: /logs/app/app.log*  # Watch app.log and rotated files
```

**What Promtail Does:**

1. **File Watching**
   - Uses `inotify` (Linux) to watch `/logs/app/app.log*`
   - Detects new lines immediately
   - Handles log rotation (app.log, app.log.1, app.log.2...)

2. **Multiline Aggregation**
   ```yaml
   - multiline:
       firstline: '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
       max_wait_time: 3s
   ```
   - Combines stack traces into single log entry
   - Waits up to 3s for more lines

3. **Parsing with Regex**
   ```yaml
   - regex:
       expression: '^(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}) - (?P<logger>\S+) - (?P<level>\w+) - (?P<message>.*)'
   ```
   - Extracts: timestamp, logger name, log level, message
   - Named groups become metadata

4. **Timestamp Parsing**
   ```yaml
   - timestamp:
       source: timestamp
       format: '2006-01-02 15:04:05,000'
   ```
   - Converts string timestamp to Unix timestamp
   - Ensures correct chronological ordering in Loki

5. **Label Addition**
   ```yaml
   - labels:
       level:  # Adds 'level' label from extracted field
   ```
   - Labels: `job=dogetionary`, `app=flask`, `level=INFO|ERROR|DEBUG`
   - Used for filtering and searching in Grafana

### Step 3: Promtail Sends to Loki

**HTTP POST Request:**
```http
POST http://loki:3100/loki/api/v1/push
Content-Type: application/json

{
  "streams": [
    {
      "stream": {
        "job": "dogetionary",
        "app": "flask",
        "level": "INFO"
      },
      "values": [
        ["1702571623456000000", "User 123 saved word: hello"]
      ]
    }
  ]
}
```

**Protocol:**
- HTTP/1.1
- Batches multiple log lines
- Compresses with gzip
- Retries on failure (with backoff)

### Step 4: Loki Indexes and Stores

**Loki Storage:**

```
/loki/
├── chunks/              # Log data (compressed)
│   ├── fake/           # Organization (default: "fake")
│   │   └── <chunk-files>
├── tsdb-index/         # TSDB index files
│   └── index_20436
├── tsdb-cache/         # Query cache
└── wal/                # Write-Ahead Log
    └── checkpoint.000015
```

**Index by Labels:**
- Creates indexes for: `{job="dogetionary", app="flask", level="INFO"}`
- Allows fast queries like: `{app="flask", level="ERROR"}`
- Uses TSDB (Time Series Database) format

**Retention:**
- Configured: 7 days (168 hours)
- Automatic cleanup via compactor
- Deletes old chunks automatically

### Step 5: Grafana Queries Loki

**LogQL Query Example:**
```logql
{job="dogetionary", app="flask"} |= "error" | level="ERROR"
```

**Query Flow:**
1. Grafana sends LogQL to Loki
2. Loki queries index for matching streams
3. Retrieves chunks from filesystem
4. Decompresses and filters
5. Returns log lines to Grafana
6. Grafana renders in UI

---

## Current Status Comparison

### Local Environment (Working)

| Component | Status | Port | Details |
|-----------|--------|------|---------|
| Loki | ✅ Running | 3100 | Receiving logs |
| Promtail | ✅ Running | 9080 | Sending logs |
| Grafana | ✅ Running | 3000 | Displaying logs |
| Logs Directory | ✅ Exists | - | `/logs/app/` mounted |

**Log Query Result:** Logs visible in Grafana

### Production Environment (Not Working)

| Component | Status | Port | Details |
|-----------|--------|------|---------|
| Loki | ✅ Running | 3100 | Waiting for logs |
| Promtail | ❌ **NOT RUNNING** | - | **THIS IS THE PROBLEM** |
| Grafana | ✅ Running | 3000 | No logs to display |
| Logs Directory | ✅ Exists | - | `/logs/app/` exists with logs |

**Log Query Result:** No logs (`total_entries=0`)

---

## Problem Diagnosis

### Why Promtail is Not Running

**To investigate on remote server:**

```bash
ssh root@69.167.170.85
su - tianzhic
cd ~/dogetionary

# Check container status
docker-compose ps

# Look for promtail logs
docker-compose logs promtail

# Try to start promtail manually
docker-compose up -d promtail

# Check for errors
docker-compose logs --tail=100 promtail
```

### Possible Causes

1. **Container Failed to Start**
   - Configuration error in `promtail-config.yml`
   - Missing files or directories
   - Port conflict

2. **Volume Mount Issues**
   - `/logs/app` directory not accessible
   - Permission issues
   - Path doesn't exist

3. **Network Issues**
   - Cannot reach Loki at `http://loki:3100`
   - Docker network misconfigured

4. **Resource Constraints**
   - Out of memory
   - Disk full
   - Too many file descriptors

---

## How to Fix

### Step 1: Check Promtail Logs

```bash
ssh root@69.167.170.85 "su - tianzhic -c 'cd ~/dogetionary && docker-compose logs promtail'"
```

**Look for:**
- Error messages
- Config parsing errors
- File permission errors
- Network connection errors

### Step 2: Verify Configuration

```bash
ssh root@69.167.170.85 "su - tianzhic -c 'cd ~/dogetionary && cat promtail/promtail-config.yml'"
```

**Check:**
- URL correct: `http://loki:3100/loki/api/v1/push`
- Paths exist: `/logs/app/app.log*`
- Valid YAML syntax

### Step 3: Check Volume Mounts

```bash
ssh root@69.167.170.85 "su - tianzhic -c 'cd ~/dogetionary && ls -la logs/app/'"
```

**Verify:**
- Directory exists
- Has log files
- Readable permissions

### Step 4: Start Promtail

```bash
ssh root@69.167.170.85 "su - tianzhic -c 'cd ~/dogetionary && docker-compose up -d promtail'"
```

**Expected output:**
```
Creating dogetionary-promtail ... done
```

### Step 5: Verify Promtail Started

```bash
ssh root@69.167.170.85 "su - tianzhic -c 'cd ~/dogetionary && docker-compose ps | grep promtail'"
```

**Expected:**
```
dogetionary-promtail   /usr/bin/promtail -conf ...   Up      9080/tcp
```

### Step 6: Check Promtail is Sending Logs

```bash
ssh root@69.167.170.85 "su - tianzhic -c 'cd ~/dogetionary && docker-compose logs --tail=50 promtail'"
```

**Look for:**
```
level=info ts=... msg="Starting Promtail"
level=info ts=... msg="Seeked /logs/app/app.log"
level=info ts=... msg="Successfully sent batch"
```

### Step 7: Verify Loki Receives Logs

```bash
ssh root@69.167.170.85 "su - tianzhic -c 'cd ~/dogetionary && docker-compose logs --tail=20 loki'"
```

**Look for:**
```
level=info ts=... msg="POST /loki/api/v1/push"
```

### Step 8: Query Loki

```bash
# From local machine
ssh -L 3100:localhost:3100 root@69.167.170.85

# Then in another terminal
curl 'http://localhost:3100/loki/api/v1/label/job/values'
```

**Expected:**
```json
{
  "status": "success",
  "data": ["dogetionary"]
}
```

---

## Diagnostic Commands

### Quick Health Check

```bash
#!/bin/bash
# Run on remote server

cd ~/dogetionary

echo "=== Container Status ==="
docker-compose ps

echo ""
echo "=== Loki Status ==="
docker-compose logs --tail=5 loki

echo ""
echo "=== Promtail Status ==="
docker-compose logs --tail=5 promtail

echo ""
echo "=== Logs Directory ==="
ls -lh logs/app/ | head -10

echo ""
echo "=== Loki Query Test ==="
curl -s 'http://localhost:3100/loki/api/v1/label/job/values' | jq .
```

### Check Log Ingestion Rate

```bash
# Query Loki for log count in last hour
curl -G -s 'http://localhost:3100/loki/api/v1/query' \
  --data-urlencode 'query=count_over_time({job="dogetionary"}[1h])' | jq .
```

### Check Promtail Positions

```bash
# Promtail tracks its position in each log file
docker exec dogetionary-promtail cat /tmp/positions.yaml
```

**Expected:**
```yaml
positions:
  /logs/app/app.log: 38181790  # Byte offset in file
  /logs/app/error.log: 0
```

---

## Testing Log Flow

### Generate Test Log

```bash
# On remote server
ssh root@69.167.170.85 "su - tianzhic -c 'echo \"2025-12-14 16:00:00,000 - test - INFO - Test log from script\" >> ~/dogetionary/logs/app/app.log'"
```

### Verify in Promtail

```bash
# Check promtail picked it up
docker-compose logs promtail | grep -i "test log"
```

### Verify in Loki

```bash
# Query Loki
curl -G -s 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="dogetionary"} |= "Test log from script"' \
  --data-urlencode 'limit=10' | jq .
```

### Verify in Grafana

1. Open Grafana: `http://69.167.170.85:3000`
2. Go to Explore
3. Select Loki data source
4. Query: `{job="dogetionary"} |= "Test log"`
5. Should see the test log

---

## Configuration Reference

### Promtail Config (`promtail/promtail-config.yml`)

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml  # Tracks file reading position

clients:
  - url: http://loki:3100/loki/api/v1/push  # Where to send logs

scrape_configs:
  - job_name: dogetionary_app
    static_configs:
      - targets: [localhost]
        labels:
          job: dogetionary
          app: flask
          log_type: all
          __path__: /logs/app/app.log*  # Glob pattern for log files

    pipeline_stages:
      # 1. Multiline: Combine stack traces
      - multiline:
          firstline: '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
          max_wait_time: 3s

      # 2. Regex: Parse log line
      - regex:
          expression: '^(?P<timestamp>...) - (?P<logger>...) - (?P<level>...) - (?P<message>...)'

      # 3. Timestamp: Convert to Unix time
      - timestamp:
          source: timestamp
          format: '2006-01-02 15:04:05,000'

      # 4. Labels: Add extracted fields as labels
      - labels:
          level:
```

### Loki Config (`loki/loki-config.yml`)

```yaml
auth_enabled: false  # No authentication required

server:
  http_listen_port: 3100

storage_config:
  tsdb_shipper:
    active_index_directory: /loki/tsdb-index
    cache_location: /loki/tsdb-cache
  filesystem:
    directory: /loki/chunks  # Where log data is stored

limits_config:
  retention_period: 168h  # 7 days
  reject_old_samples_max_age: 168h
```

### Docker Compose Volumes

```yaml
promtail:
  volumes:
    - ./promtail/promtail-config.yml:/etc/promtail/config.yml
    - ./logs/app:/logs/app        # Mount app logs
    - ./logs/nginx:/logs/nginx    # Mount nginx logs

loki:
  volumes:
    - ./loki/loki-config.yml:/etc/loki/local-config.yaml
    - loki_data:/loki             # Persistent storage
```

---

## Troubleshooting Checklist

### Promtail Not Starting

- [ ] Check `docker-compose ps` - is promtail listed?
- [ ] Check `docker-compose logs promtail` - any errors?
- [ ] Verify config file exists: `promtail/promtail-config.yml`
- [ ] Verify config is valid YAML
- [ ] Check logs directory is mounted correctly
- [ ] Verify network connectivity to Loki

### Promtail Running But No Logs

- [ ] Check positions file: `/tmp/positions.yaml` inside container
- [ ] Verify log files exist: `ls -la logs/app/`
- [ ] Check file permissions (should be readable)
- [ ] Look for errors in `docker-compose logs promtail`
- [ ] Verify regex pattern matches your log format
- [ ] Test with simple log: `echo "..." >> logs/app/app.log`

### Loki Not Receiving Logs

- [ ] Check Loki is running: `docker-compose ps loki`
- [ ] Verify Promtail can reach Loki: `docker exec promtail wget -O- http://loki:3100/ready`
- [ ] Check Loki logs for POST requests: `docker-compose logs loki | grep POST`
- [ ] Verify network is correct: `docker network inspect dogetionary-network`
- [ ] Check disk space: `df -h`

### Grafana Not Showing Logs

- [ ] Verify Loki data source is configured
- [ ] Test Loki connection in Grafana
- [ ] Try simple query: `{job="dogetionary"}`
- [ ] Check time range (last 1 hour?)
- [ ] Verify logs exist: `curl localhost:3100/loki/api/v1/label/job/values`

---

## Quick Fix Script

Save this as `scripts/fix_loki.sh`:

```bash
#!/bin/bash
# Quick Loki diagnostics and fix script

echo "=== Loki Diagnostic and Fix Script ==="
echo ""

# Check if we're on remote server
if [ ! -d "/home/tianzhic/dogetionary" ]; then
    echo "This script should run on the remote server"
    echo "Usage: ssh root@69.167.170.85 \"su - tianzhic -c 'cd ~/dogetionary && bash fix_loki.sh'\""
    exit 1
fi

cd /home/tianzhic/dogetionary

echo "1. Checking container status..."
docker-compose ps

echo ""
echo "2. Checking if promtail is defined..."
grep -q "promtail:" docker-compose.yml && echo "✓ Promtail found in docker-compose.yml" || echo "✗ Promtail NOT in docker-compose.yml"

echo ""
echo "3. Checking log directories..."
ls -la logs/app/ | head -5

echo ""
echo "4. Attempting to start promtail..."
docker-compose up -d promtail

echo ""
echo "5. Waiting for promtail to start..."
sleep 3

echo ""
echo "6. Checking promtail logs..."
docker-compose logs --tail=20 promtail

echo ""
echo "7. Verifying promtail is running..."
docker-compose ps | grep promtail

echo ""
echo "8. Testing Loki API..."
curl -s 'http://localhost:3100/loki/api/v1/label/job/values'

echo ""
echo "Done! Check above for any errors."
```

---

## Next Steps for You

1. **SSH to Production:**
   ```bash
   ssh root@69.167.170.85
   su - tianzhic
   cd ~/dogetionary
   ```

2. **Check Why Promtail Stopped:**
   ```bash
   docker-compose logs promtail
   ```

3. **Restart Promtail:**
   ```bash
   docker-compose up -d promtail
   ```

4. **Verify It's Working:**
   ```bash
   docker-compose ps | grep promtail
   docker-compose logs --tail=50 promtail
   ```

5. **Check Logs Flowing:**
   ```bash
   # Wait a minute, then check
   curl 'http://localhost:3100/loki/api/v1/label/job/values'
   ```

6. **Check in Grafana:**
   - Open `http://69.167.170.85:3000`
   - Go to Explore
   - Query: `{job="dogetionary"}`

---

## Common Issues and Solutions

### Issue: "no marks file found"

**Meaning:** Loki hasn't received any data yet
**Solution:** Promtail needs to be running and sending logs

### Issue: "total_entries=0"

**Meaning:** Query returned no log entries
**Solution:** Either no logs exist or promtail isn't running

### Issue: Promtail shows "permission denied"

**Solution:**
```bash
chmod -R 755 logs/
chown -R tianzhic:tianzhic logs/
```

### Issue: "connection refused" from Promtail to Loki

**Solution:**
```bash
# Check if Loki is running
docker-compose ps loki

# Check network
docker network inspect dogetionary-network | grep -A 10 "dogetionary-loki"
```

---

## Monitoring Best Practices

1. **Set Up Alerts**
   - Alert when promtail stops
   - Alert when log ingestion stops
   - Alert on error log spikes

2. **Regular Health Checks**
   - Monitor promtail uptime
   - Check disk space for `/loki`
   - Verify log files are rotating

3. **Retention Management**
   - Current: 7 days
   - Adjust based on needs
   - Monitor disk usage

4. **Performance Tuning**
   - Batch size for log sending
   - Compression settings
   - Cache sizes

---

**Last Updated:** 2025-12-14
**Status:** Production issue identified - Promtail not running
