# Load Testing for Dogetionary API

This directory contains load testing scripts for the Dogetionary practice mode API endpoints.

## Overview

The `load_test.py` script tests the following critical endpoints:

1. **`GET /v3/practice-status`** - Get practice status
2. **`GET /v3/next-review-words-batch`** - Fetch review questions (one-by-one)
3. **`POST /v3/reviews/submit`** - Submit review answers
4. **`GET /v3/videos/<id>`** - Download video for video questions
5. **`GET /v3/due_counts`** - Get due word counts

## Installation

```bash
# Install dependencies
pip install locust requests

# Or use the requirements file
pip install -r load_test_requirements.txt
```

## Usage

### Option 1: Locust Web UI (Recommended)

The web UI provides real-time graphs and detailed statistics.

```bash
# Start Locust web interface
locust -f load_test.py --host=https://kwafy.com

# Open browser to http://localhost:8089
# Configure number of users and spawn rate in the UI
```

### Option 2: Locust Headless Mode

Run tests from command line without UI:

```bash
# Run with 10 users, spawn rate of 2/sec, for 60 seconds
locust -f load_test.py \
    --host=https://kwafy.com \
    --headless \
    --users 10 \
    --spawn-rate 2 \
    --run-time 60s

# Run with 50 users for 5 minutes
locust -f load_test.py \
    --host=https://kwafy.com \
    --headless \
    --users 50 \
    --spawn-rate 5 \
    --run-time 5m
```

### Option 3: Simple Benchmark Mode

Lightweight testing without Locust (uses only `requests`):

```bash
# Run simple benchmark with 10 users for 30 seconds
python load_test.py --simple --users 10 --duration 30

# Run with custom settings
python load_test.py \
    --simple \
    --host https://kwafy.com \
    --users 20 \
    --duration 60
```

## Test User Configuration

**Important:** Update the test users in `load_test.py` with valid user IDs from your system:

```python
test_users = [
    {"user_id": "test_user_1", "learning_language": "en", "native_language": "zh"},
    {"user_id": "test_user_2", "learning_language": "en", "native_language": "zh"},
    # Add more test users...
]
```

## User Behavior Simulation

The script simulates realistic user practice sessions:

1. User starts practice session
2. Checks practice status (weight: 3)
3. Fetches review questions one-by-one (weight: 5)
4. Downloads videos if question type is `video_mc`
5. Submits answers (correct/incorrect randomly) (weight: 4)
6. Checks due counts periodically (weight: 2)
7. Waits 1-5 seconds between actions (simulates reading/thinking)

## Performance Report

After the test completes, a detailed report is generated:

```
================================================================================
LOAD TEST PERFORMANCE REPORT
================================================================================
Timestamp: 2025-12-18T00:30:00
Total Requests: 1250
Successful: 1245
Failed: 5
Success Rate: 99.60%

--------------------------------------------------------------------------------
ENDPOINT PERFORMANCE
--------------------------------------------------------------------------------
Endpoint                                    Count      Min      Avg      P50      P95      P99      Max
--------------------------------------------------------------------------------
/v3/practice-status                           250     45ms    120ms    115ms    180ms    220ms    350ms
/v3/next-review-words-batch                   425     80ms    250ms    240ms    400ms    550ms    800ms
/v3/reviews/submit                            320     60ms    150ms    145ms    230ms    280ms    400ms
/v3/videos/<id>                               155    200ms    450ms    420ms    650ms    800ms   1200ms
/v3/due_counts                                100     40ms    100ms     95ms    150ms    180ms    250ms
================================================================================
```

Reports are saved to `load_test_report_YYYYMMDD_HHMMSS.txt`

## Performance Targets

Based on the current architecture (one-by-one question fetching), here are recommended targets:

| Endpoint | Target P95 | Target P99 | Notes |
|----------|-----------|-----------|-------|
| `practice-status` | < 200ms | < 300ms | Lightweight query |
| `next-review-words-batch` | < 500ms | < 800ms | Complex query with question generation |
| `reviews/submit` | < 300ms | < 500ms | Database write + cache update |
| `videos/<id>` | < 1000ms | < 2000ms | Binary data transfer (size-dependent) |
| `due_counts` | < 150ms | < 250ms | Fibonacci calculation + query |

## Advanced Configuration

### Custom Task Weights

Modify task weights in `PracticeModeUser` class:

```python
@task(5)  # Higher weight = more frequent
def get_review_batch(self):
    ...

@task(2)  # Lower weight = less frequent
def get_due_counts(self):
    ...
```

### Custom Wait Times

Adjust user think time:

```python
class PracticeModeUser(HttpUser):
    # Wait 2-8 seconds between tasks
    wait_time = between(2, 8)
```

### Distributed Load Testing

Run Locust in distributed mode for higher load:

```bash
# Start master
locust -f load_test.py --host=https://kwafy.com --master

# Start workers (on same or different machines)
locust -f load_test.py --worker --master-host=<master-ip>
locust -f load_test.py --worker --master-host=<master-ip>
```

## Monitoring

While running tests, monitor:

1. **API Server**:
   - CPU usage
   - Memory usage
   - Response times
   - Error rates

2. **Database**:
   - Query performance (`/metrics` endpoint)
   - Connection pool saturation
   - Slow query log

3. **Cache** (if applicable):
   - Hit rate
   - Eviction rate

## Troubleshooting

### High Failure Rate

- Check server capacity
- Verify test users exist in database
- Check network connectivity
- Review server logs for errors

### Slow Response Times

- Check database query performance
- Review N+1 query patterns
- Check cache hit rates
- Monitor server resource usage

### Connection Errors

- Increase timeout values
- Check connection pool settings
- Verify server can handle concurrent connections

## Example Commands

```bash
# Quick 1-minute test with 10 users
locust -f load_test.py --host=https://kwafy.com --headless -u 10 -r 2 -t 1m

# Sustained load: 50 users for 10 minutes
locust -f load_test.py --host=https://kwafy.com --headless -u 50 -r 5 -t 10m

# Stress test: ramp up to 100 users
locust -f load_test.py --host=https://kwafy.com --headless -u 100 -r 10 -t 5m

# Simple benchmark (no Locust required)
python load_test.py --simple --users 10 --duration 30
```

## Quick Start with Helper Script

Use the helper script for common scenarios:

```bash
# Make script executable (first time only)
chmod +x scripts/run_load_test.sh

# Run smoke test (safest - 5 users, 30s)
./scripts/run_load_test.sh smoke

# Run quick test (10 users, 1 minute)
./scripts/run_load_test.sh quick

# Run standard load test (25 users, 5 minutes)
./scripts/run_load_test.sh load

# Start web UI for manual control
./scripts/run_load_test.sh web

# Simple benchmark (no Locust required)
./scripts/run_load_test.sh simple
```

## Important Notes

⚠️ **Production Testing:**
- There is no staging environment - tests run against **production** (kwafy.com)
- **Always coordinate with team** before running load tests on production
- **Start with SMOKE tests** (5 users) first to verify everything works
- **Monitor server health** closely during tests
- **Gradually increase load** - never jump straight to stress tests
- **Run during low-traffic periods** (if possible)
- Use the `smoke` or `quick` scenarios for routine testing
- Only run `stress` or `spike` tests with explicit approval

**Testing Best Practices:**
- The script simulates realistic practice sessions, not just endpoint hammering
- Test users should be dedicated test accounts (not real user data)
- Monitor `/metrics` endpoint during tests
- Watch database query performance
- Keep tests short initially (1-2 minutes)
- Review server logs after each test
