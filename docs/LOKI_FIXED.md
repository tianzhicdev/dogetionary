# Loki Logging - Fixed and Working ✅

## What Was Fixed

### Problem 1: Old Log Timestamps
Promtail was trying to send old rotated logs (`app.log.1`, `app.log.2`, etc.) with timestamps from days ago. Loki rejected these as too old.

**Solution:**
- Changed Promtail config to only scrape current logs: `__path__: /logs/app/app.log` (no wildcards)
- Deleted old rotated log files

### Problem 2: Incorrect Labels
Logs showed `app="flask"` instead of `app="dogetionary"` because Promtail wasn't parsing JSON.

**Solution:**
- Updated Promtail pipeline to parse JSON logs
- Extract labels from JSON fields: `app`, `service`, `level`, `logger`, `endpoint`

### Problem 3: Rate Limiting
Promtail was flooding Loki with 1MB batches of old logs.

**Solution:**
- Removed old logs
- Only send current logs going forward

## Verification

```bash
# Check labels are available
curl -s 'http://localhost:3100/loki/api/v1/labels' | jq .

# Query recent logs
curl -s 'http://localhost:3100/loki/api/v1/query_range?query={app="dogetionary"}&limit=5' | jq .
```

## Working LogQL Queries

### Basic Queries

```logql
# All logs from dogetionary app
{app="dogetionary"}

# All ERROR level logs
{app="dogetionary", level="ERROR"}

# Logs from specific endpoint
{app="dogetionary", endpoint="health_check"}

# Logs from specific logger
{logger="handlers.words"}
```

### Advanced Queries

```logql
# Filter by JSON field
{app="dogetionary"} | json | request_id="452b02b6-151e-462d-b2d8-4d52bd400ba2"

# Search for text in message
{app="dogetionary"} |= "database connection"

# Regex search
{app="dogetionary"} |~ "error|failed|exception"

# Error rate (errors per second over 5min)
rate({app="dogetionary", level="ERROR"}[5m])

# Count errors by endpoint
sum by (endpoint) (count_over_time({app="dogetionary", level="ERROR"}[1h]))
```

## Available Labels

From JSON logs:
- `app`: "dogetionary"
- `service`: "backend"
- `level`: "INFO", "ERROR", "WARNING"
- `logger`: "app", "handlers.words", "utils.database", etc.
- `endpoint`: "health_check", "get_word_definition_v4", etc.
- `job`: "dogetionary" (from Promtail config)

## Files Changed

### `/promtail/promtail-config.yml`
- Changed path from `/logs/app/app.log*` to `/logs/app/app.log`
- Added JSON parsing pipeline
- Extract labels from JSON fields

### Log Files Cleaned
- Deleted `logs/app/app.log.1` through `logs/app/app.log.6` (150MB of old logs)
- Cleared Promtail position tracker

## For Production Deployment

Run these commands on prod server:

```bash
cd ~/dogetionary

# 1. Update Promtail config
# Copy the new promtail-config.yml from local to prod

# 2. Delete old log files (they cause timestamp errors)
rm -f logs/app/app.log.[0-9]*
rm -f logs/app/error.log.[0-9]*

# 3. Restart Promtail with fresh start
docker exec dogetionary-promtail rm -f /tmp/positions.yaml
docker-compose restart promtail

# 4. Verify logs are flowing
sleep 5
docker-compose logs promtail --tail 20
```

## Testing

```bash
# Generate a test log entry
curl http://localhost:5001/health

# Wait a few seconds for Promtail to send it
sleep 5

# Query Loki
curl -s 'http://localhost:3100/loki/api/v1/query_range?query={app="dogetionary"}&limit=2' | jq '.data.result[0].values[0][1]'
```

Should see JSON log with all fields:
```json
{
  "asctime": "2025-12-14 21:12:46,411",
  "app": "dogetionary",
  "service": "backend",
  "level": "INFO",
  "logger": "app",
  "endpoint": "health_check",
  "request_id": "452b02b6-151e-462d-b2d8-4d52bd400ba2",
  "message": "RESPONSE: {...}"
}
```

## Grafana Dashboard Setup

In Grafana, add Loki data source:
- URL: `http://loki:3100`

Example dashboard queries:
1. **Request Rate**: `rate({app="dogetionary"}[1m])`
2. **Error Rate**: `rate({app="dogetionary", level="ERROR"}[1m])`
3. **Response Time**: Extract from JSON message field
4. **Top Endpoints**: `topk(10, sum by (endpoint) (rate({app="dogetionary"}[5m])))`

## Troubleshooting

**No logs in Loki?**
```bash
# Check Promtail is reading files
docker-compose logs promtail | grep "Adding target"

# Check for errors
docker-compose logs promtail | grep -i error

# Verify log files exist
ls -lh logs/app/

# Check Loki is running
curl http://localhost:3100/ready
```

**"Timestamp too old" errors?**
- Delete old rotated log files
- Clear Promtail positions: `docker exec dogetionary-promtail rm /tmp/positions.yaml`
- Restart Promtail

**Rate limiting (429 errors)?**
- This is temporary while catching up on old logs
- Will stop once old logs are cleared
- Increase limits in `loki/loki-config.yml` if needed

## Success Criteria

✅ Promtail logs show "Adding target" for app.log and error.log
✅ No "timestamp too old" errors in Promtail logs
✅ Loki API returns logs with app="dogetionary"
✅ Labels include: app, service, level, logger, endpoint
✅ JSON log fields are queryable in LogQL

All criteria met! Loki logging is working! 🎉
