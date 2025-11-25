# Monitoring & Observability

This document describes the monitoring infrastructure for Dogetionary, including logging, metrics, and dashboards.

## Table of Contents

1. [Overview](#overview)
2. [Logging System](#logging-system)
3. [Prometheus Metrics](#prometheus-metrics)
4. [Grafana Dashboards](#grafana-dashboards)
5. [Accessing Logs](#accessing-logs)
6. [Querying Metrics](#querying-metrics)
7. [Creating Custom Dashboards](#creating-custom-dashboards)
8. [Troubleshooting](#troubleshooting)

---

## Overview

The Dogetionary monitoring stack consists of three main components:

1. **Logging**: Structured logging with separate error tracking
2. **Prometheus**: Time-series metrics collection and storage
3. **Grafana**: Visualization and dashboarding

```
┌─────────────┐
│   Flask     │
│   App       │──────> Logs (error.log, app.log)
│             │
└──────┬──────┘
       │
       │ /metrics
       │ endpoint
       ▼
┌─────────────┐
│ Prometheus  │◄────── Scrapes every 10s
│             │
└──────┬──────┘
       │
       │ PromQL
       │ queries
       ▼
┌─────────────┐
│  Grafana    │────────> Dashboards
│             │
└─────────────┘
```

---

## Logging System

### Architecture

The logging system uses Python's built-in `logging` module with custom configuration:

- **Location**: `src/middleware/logging.py`
- **Error Handler**: `src/middleware/error_handler.py`
- **Log Directory**: `logs/app/`

### Log Files

| File | Purpose | Max Size | Backups |
|------|---------|----------|---------|
| `app.log` | All logs (INFO, DEBUG, ERROR) | 10MB | 5 |
| `error.log` | Errors only (ERROR, CRITICAL) | 10MB | 10 |

### Log Format

```
YYYY-MM-DD HH:MM:SS,mmm - module_name - LEVEL - [file.py:line] - message
```

**Example:**
```
2025-11-25 12:30:45,123 - handlers.words - ERROR - [words.py:542] - Failed to fetch definition for word='test'
```

### Configuration

**File**: `src/middleware/logging.py`

```python
def setup_logging(app):
    """
    Configure logging with:
    - app.log: All logs (INFO+)
    - error.log: Errors only (ERROR+)
    - Console output for development
    - Automatic log rotation
    """
```

Key features:
- **Rotating File Handler**: Automatically rotates when files reach max size
- **Dual Handlers**: Separate files for all logs and errors
- **Contextual Logging**: Includes file path and line number
- **Backup Management**: Keeps historical logs for debugging

### Global Error Handling

**File**: `src/middleware/error_handler.py`

Catches all unhandled exceptions and logs them with full context:

```python
@app.errorhandler(Exception)
def handle_exception(e):
    """
    Logs:
    - Exception type and message
    - HTTP endpoint and method
    - User-Agent and IP address
    - Request parameters
    - Full stack trace
    """
```

Registered in `src/app_refactored.py`:
```python
from middleware.error_handler import register_error_handlers
register_error_handlers(app)
```

---

## Accessing Logs

### Using the CLI Tool

We provide a convenient script for log access:

**File**: `scripts/view_logs.sh`

```bash
# View real-time errors
./scripts/view_logs.sh errors

# View last 50 errors
./scripts/view_logs.sh errors-recent

# View today's errors only
./scripts/view_logs.sh errors-today

# Count errors by date (last 7 days)
./scripts/view_logs.sh errors-count

# Search for specific pattern
./scripts/view_logs.sh errors-search "DatabaseError"

# View all real-time logs
./scripts/view_logs.sh app

# View last 100 app logs
./scripts/view_logs.sh app-recent

# Clean up old logs (30+ days)
./scripts/view_logs.sh clear-old
```

### Direct File Access

```bash
# View error log
cat logs/app/error.log

# Follow error log in real-time
tail -f logs/app/error.log

# View all logs
cat logs/app/app.log

# Follow all logs
tail -f logs/app/app.log

# Search logs
grep "exception" logs/app/error.log

# View rotated logs
cat logs/app/error.log.1
cat logs/app/error.log.2
```

### Docker Container Logs

```bash
# View container logs
docker logs dogetionary-app-1

# Follow in real-time
docker logs -f dogetionary-app-1

# Last 100 lines
docker logs --tail 100 dogetionary-app-1

# Since specific time
docker logs --since 2025-11-25T12:00:00 dogetionary-app-1
```

---

## Prometheus Metrics

### Architecture

Prometheus collects metrics from the Flask app via a `/metrics` endpoint.

- **Metrics Library**: `prometheus-client==0.19.0`
- **Metrics Definition**: `src/middleware/metrics.py`
- **Auto-Instrumentation**: `src/middleware/metrics_middleware.py`
- **Scrape Interval**: 10 seconds
- **Retention**: 30 days

### Metrics Categories

#### 1. HTTP Metrics

Track all HTTP requests automatically:

```python
# Total request count by endpoint, method, and status
http_requests_total{method="GET", endpoint="v3_api.health_check", status_code="200"}

# Request duration histogram (buckets: 10ms to 10s)
http_request_duration_seconds_bucket{method="GET", endpoint="v3_api.get_word_definition_v3", le="0.5"}

# In-flight requests gauge
http_requests_in_flight{method="GET", endpoint="v3_api.get_due_counts"}
```

#### 2. LLM Metrics

Track all LLM API calls (OpenAI, Groq):

```python
# Total LLM calls
llm_calls_total{provider="groq", model="llama-4-scout", status="success"}

# LLM request duration
llm_request_duration_seconds{provider="openai", model="gpt-4o-mini"}

# Token usage
llm_tokens_total{provider="groq", model="llama-4-scout", type="prompt"}
llm_tokens_total{provider="groq", model="llama-4-scout", type="completion"}

# Estimated cost in USD
llm_cost_usd_total{provider="openai", model="gpt-4o-mini"}

# Errors by type
llm_errors_total{provider="openai", model="gpt-4o-mini", error_type="RateLimitError"}
```

#### 3. Business Metrics

Track application-specific events:

```python
# Review submissions
reviews_total{result="correct"}
reviews_total{result="incorrect"}

# Words saved by users
words_saved_total{language="en"}

# Study schedules created
schedules_created_total{test_type="ielts"}
```

### Instrumentation

#### Automatic HTTP Tracking

All HTTP requests are automatically tracked by middleware:

**File**: `src/middleware/metrics_middleware.py`

```python
@app.before_request
def track_request_start():
    """Tracks request start time and increments in-flight counter"""

@app.after_request
def track_request_end(response):
    """Records duration, status code, and decrements in-flight counter"""
```

Registered in `src/app_refactored.py`:
```python
from middleware.metrics_middleware import (
    track_request_start,
    track_request_end
)
app.before_request(track_request_start)
app.after_request(track_request_end)
```

#### Automatic LLM Tracking

All LLM calls through `llm_completion()` are automatically tracked:

**File**: `src/utils/llm.py`

```python
def llm_completion(messages, model_name, ...):
    start_time = time.time()

    try:
        # Make LLM API call
        response = client.chat.completions.create(...)

        # Track success metrics
        llm_calls_total.labels(provider=provider, model=model, status='success').inc()
        llm_request_duration_seconds.labels(provider, model).observe(duration)

        # Track tokens and cost
        if response.usage:
            llm_tokens_total.labels(provider, model, type='prompt').inc(prompt_tokens)
            llm_tokens_total.labels(provider, model, type='completion').inc(completion_tokens)
            cost = estimate_cost(provider, model, response.usage)
            llm_cost_usd_total.labels(provider, model).inc(cost)

        return response
    except Exception as e:
        # Track error metrics
        llm_calls_total.labels(provider, model, status='error').inc()
        llm_errors_total.labels(provider, model, error_type=type(e).__name__).inc()
        raise
```

#### Manual Business Metrics

Track business events in your code:

```python
from middleware.metrics import reviews_total, words_saved_total, schedules_created_total

# Track a review
reviews_total.labels(result='correct').inc()

# Track word saved
words_saved_total.labels(language='en').inc()

# Track schedule creation
schedules_created_total.labels(test_type='toefl').inc()
```

### Cost Estimation

**File**: `src/middleware/metrics.py`

```python
PRICING = {
    'openai': {
        'gpt-4o': {'prompt': 0.000005, 'completion': 0.000015},  # $5/$15 per 1M tokens
        'gpt-4o-mini': {'prompt': 0.00000015, 'completion': 0.0000006},
        'gpt-3.5-turbo': {'prompt': 0.0000005, 'completion': 0.0000015},
    },
    'groq': {
        'llama-3.1-70b-versatile': {'prompt': 0.00000059, 'completion': 0.00000079},
        'llama-3.1-8b-instant': {'prompt': 0.00000005, 'completion': 0.00000008},
    }
}
```

**To add new models**: Update the `PRICING` dictionary with your model's pricing.

---

## Querying Metrics

### Accessing Prometheus

- **URL**: http://localhost:9090
- **Metrics Endpoint**: http://localhost:5001/metrics

### Useful PromQL Queries

#### HTTP Performance

```promql
# Request rate (requests per second)
sum(rate(http_requests_total[5m]))

# Request rate by endpoint
sum by (endpoint) (rate(http_requests_total[5m]))

# Error rate (5xx errors as percentage)
sum(rate(http_requests_total{status_code=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100

# P95 latency (95th percentile)
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# P95 latency by endpoint
histogram_quantile(0.95, sum by (endpoint, le) (rate(http_request_duration_seconds_bucket[5m])))

# Requests currently in-flight
sum(http_requests_in_flight)
```

#### LLM Performance

```promql
# LLM call rate
sum(rate(llm_calls_total[5m]))

# LLM call rate by provider/model
sum by (provider, model) (rate(llm_calls_total[5m]))

# LLM success rate (percentage)
sum(rate(llm_calls_total{status="success"}[5m])) / sum(rate(llm_calls_total[5m])) * 100

# P95 LLM latency
histogram_quantile(0.95, sum(rate(llm_request_duration_seconds_bucket[5m])) by (le))

# Token usage rate (tokens per second)
sum(rate(llm_tokens_total[5m]))

# Token usage by type
sum by (type) (rate(llm_tokens_total[5m]))

# Estimated cost per hour
sum(increase(llm_cost_usd_total[1h]))

# Estimated cost per day
sum(increase(llm_cost_usd_total[24h]))

# Error rate by type
sum by (error_type) (rate(llm_errors_total[5m]))
```

#### Business Metrics

```promql
# Total reviews per minute
sum(rate(reviews_total[1m])) * 60

# Review accuracy (correct as percentage)
sum(rate(reviews_total{result="correct"}[5m])) / sum(rate(reviews_total[5m])) * 100

# Words saved per hour
sum(increase(words_saved_total[1h]))

# Schedules created per day
sum(increase(schedules_created_total[24h]))
```

---

## Grafana Dashboards

### Accessing Grafana

- **URL**: http://localhost:3000
- **Username**: `admin`
- **Password**: `admin123`

### Pre-built Dashboards

#### 1. API Overview Dashboard

**URL**: http://localhost:3000/d/dogetionary-api

**Panels** (8 total):

1. **Request Rate (5m)** - Stat panel
   - Query: `sum(rate(http_requests_total[5m]))`
   - Shows current requests per second

2. **Error Rate (5xx)** - Stat panel with thresholds
   - Query: `sum(rate(http_requests_total{status_code=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100`
   - Green: <1%, Yellow: 1-5%, Red: >5%

3. **P95 Latency** - Stat panel
   - Query: `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))`
   - Shows 95th percentile response time

4. **In-Flight Requests** - Stat panel
   - Query: `sum(http_requests_in_flight)`
   - Shows active concurrent requests

5. **Request Rate by Endpoint** - Time series graph
   - Query: `sum by (endpoint) (rate(http_requests_total[5m]))`
   - Shows traffic breakdown by endpoint

6. **Latency by Endpoint (p50, p95, p99)** - Time series graph
   - Queries for 50th, 95th, and 99th percentiles by endpoint
   - Helps identify slow endpoints

7. **Status Code Distribution** - Pie chart
   - Query: `sum by (status_code) (rate(http_requests_total[5m]))`
   - Visual breakdown of 2xx, 4xx, 5xx responses

8. **Top 10 Endpoints by Traffic** - Table
   - Query: `topk(10, sum by (endpoint) (rate(http_requests_total[5m])))`
   - Ranked list of busiest endpoints

**Refresh**: Every 10 seconds

#### 2. LLM Metrics Dashboard

**URL**: http://localhost:3000/d/dogetionary-llm

**Panels** (8 total):

1. **LLM Call Rate** - Stat panel
   - Query: `sum(rate(llm_calls_total[5m]))`
   - Shows LLM calls per second

2. **LLM Success Rate** - Stat panel with thresholds
   - Query: `sum(rate(llm_calls_total{status="success"}[5m])) / sum(rate(llm_calls_total[5m])) * 100`
   - Red: <90%, Yellow: 90-95%, Green: >95%

3. **P95 LLM Latency** - Stat panel
   - Query: `histogram_quantile(0.95, sum(rate(llm_request_duration_seconds_bucket[5m])) by (le))`
   - Green: <5s, Yellow: 5-10s, Red: >10s

4. **Estimated Cost (24h)** - Stat panel in USD
   - Query: `sum(increase(llm_cost_usd_total[24h]))`
   - Shows daily LLM API spend

5. **LLM Calls by Provider/Model** - Time series graph (stacked)
   - Query: `sum by (provider, model) (rate(llm_calls_total[5m]))`
   - Shows usage breakdown by provider and model

6. **LLM Latency by Provider (p50, p95)** - Time series graph
   - Queries for 50th and 95th percentiles by provider/model
   - Compare performance across providers

7. **Token Usage (Hourly)** - Time series graph (stacked)
   - Query: `sum by (provider, model, type) (increase(llm_tokens_total[1h]))`
   - Shows prompt vs completion token usage

8. **LLM Errors by Type** - Time series graph
   - Query: `sum by (provider, model, error_type) (rate(llm_errors_total[5m]))`
   - Breakdown of error types (RateLimitError, APIError, etc.)

**Refresh**: Every 10 seconds

### Dashboard Configuration Files

- **API Overview**: `grafana/dashboards/api_overview.json`
- **LLM Metrics**: `grafana/dashboards/llm_metrics.json`
- **Datasource**: `grafana/provisioning/datasources/prometheus.yml`
- **Dashboard Provisioning**: `grafana/provisioning/dashboards/dashboard.yml`

---

## Creating Custom Dashboards

### Option 1: Via Grafana UI

1. Go to http://localhost:3000
2. Click **Dashboards** → **New** → **New Dashboard**
3. Click **Add visualization**
4. Select **Prometheus** datasource
5. Enter your PromQL query
6. Customize visualization (graph type, colors, thresholds)
7. Click **Save**

### Option 2: Export and Version Control

After creating a dashboard in the UI:

1. Click **Dashboard settings** (gear icon)
2. Click **JSON Model**
3. Copy the JSON
4. Save to `grafana/dashboards/your_dashboard.json`
5. Commit to Git

The dashboard will auto-load on next Grafana restart.

### Example: Custom Panel

**Goal**: Track average review time per user

```json
{
  "datasource": {
    "type": "prometheus",
    "uid": "PBFA97CFB590B2093"
  },
  "targets": [
    {
      "expr": "avg by (user_id) (rate(review_duration_seconds_sum[5m]) / rate(review_duration_seconds_count[5m]))",
      "legendFormat": "{{user_id}}"
    }
  ],
  "title": "Average Review Time by User",
  "type": "timeseries"
}
```

---

## Prometheus Configuration

### Configuration File

**File**: `prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s       # How often to scrape targets
  evaluation_interval: 15s   # How often to evaluate rules
  external_labels:
    cluster: 'dogetionary'
    environment: 'production'

scrape_configs:
  - job_name: 'dogetionary-app'
    static_configs:
      - targets: ['app:5000']  # Docker service name
    metrics_path: '/metrics'
    scrape_interval: 10s       # Override: scrape every 10s
```

### Docker Configuration

**File**: `docker-compose.yml`

```yaml
prometheus:
  image: prom/prometheus:latest
  ports:
    - "9090:9090"
  volumes:
    - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
    - prometheus_data:/prometheus  # Persistent storage
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.retention.time=30d'  # Keep data for 30 days
    - '--web.enable-lifecycle'
  networks:
    - dogetionary-network
```

### Checking Configuration

```bash
# Validate Prometheus config
docker exec dogetionary-prometheus-1 promtool check config /etc/prometheus/prometheus.yml

# Reload configuration without restart
curl -X POST http://localhost:9090/-/reload

# Check targets status
curl http://localhost:9090/api/v1/targets
```

---

## Grafana Configuration

### Docker Configuration

**File**: `docker-compose.yml`

```yaml
grafana:
  image: grafana/grafana:latest
  ports:
    - "3000:3000"
  volumes:
    - grafana_data:/var/lib/grafana  # Persistent storage
    - ./grafana/provisioning:/etc/grafana/provisioning  # Auto-provisioning
    - ./grafana/dashboards:/var/lib/grafana/dashboards  # Dashboard files
  environment:
    - GF_SECURITY_ADMIN_USER=admin
    - GF_SECURITY_ADMIN_PASSWORD=admin123
    - GF_USERS_ALLOW_SIGN_UP=false
  depends_on:
    - prometheus
```

### Auto-Provisioning

Grafana automatically loads:
1. **Datasources** from `grafana/provisioning/datasources/`
2. **Dashboards** from `grafana/provisioning/dashboards/`

**Datasource Config**: `grafana/provisioning/datasources/prometheus.yml`

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    uid: PBFA97CFB590B2093  # Fixed UID for consistency
    url: http://prometheus:9090
    isDefault: true
    editable: true
```

**Dashboard Provider**: `grafana/provisioning/dashboards/dashboard.yml`

```yaml
apiVersion: 1
providers:
  - name: 'Dogetionary Dashboards'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10  # Check for changes every 10s
    allowUiUpdates: true       # Allow editing in UI
    options:
      path: /var/lib/grafana/dashboards
```

### Updating Dashboards

After editing dashboard JSON files:

```bash
# Restart Grafana to reload dashboards
docker-compose restart grafana

# Or wait 10 seconds for auto-reload (updateIntervalSeconds: 10)
```

---

## Troubleshooting

### Logs Not Appearing

**Symptom**: No logs in `logs/app/` directory

**Solutions**:
```bash
# Check if directory exists
ls -la logs/app/

# Create directory if missing
mkdir -p logs/app/

# Check file permissions
ls -l logs/app/

# Check app container logs
docker logs dogetionary-app-1 | tail -50
```

### Prometheus Not Scraping

**Symptom**: "Target down" in Prometheus UI

**Solutions**:
```bash
# Check if /metrics endpoint works
curl http://localhost:5001/metrics

# Check if app container is running
docker ps | grep app

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | python3 -m json.tool

# Check Prometheus logs
docker logs dogetionary-prometheus-1

# Verify Prometheus can reach app (from inside Prometheus container)
docker exec dogetionary-prometheus-1 wget -qO- http://app:5000/metrics
```

### Grafana Datasource Error

**Symptom**: "Datasource prometheus is not found"

**Solutions**:
```bash
# Check datasource UID in dashboards matches actual UID
curl -s -u admin:admin123 http://localhost:3000/api/datasources | python3 -m json.tool

# If UID mismatch, update dashboard JSON files
# Replace "uid": "prometheus" with actual UID (e.g., "uid": "PBFA97CFB590B2093")

# Restart Grafana
docker-compose restart grafana
```

### Metrics Not Updating

**Symptom**: Metrics show old data or no data

**Solutions**:
```bash
# Check Prometheus scrape interval
curl http://localhost:9090/api/v1/status/config

# Force immediate scrape (not recommended for production)
curl -X POST http://localhost:9090/-/reload

# Check if app is generating metrics
curl http://localhost:5001/metrics | grep llm_calls_total

# Make test requests to generate metrics
curl "http://localhost:5001/v3/health"
curl "http://localhost:5001/v3/word?user_id=404AEA48-8AE8-4744-9411-5F36C1A63986&w=test"

# Check Prometheus query
curl "http://localhost:9090/api/v1/query?query=llm_calls_total"
```

### High Memory Usage

**Symptom**: Prometheus or Grafana using too much memory

**Solutions**:
```bash
# Check Prometheus storage size
du -sh prometheus_data/

# Reduce retention time in docker-compose.yml
# Change: '--storage.tsdb.retention.time=30d'
# To: '--storage.tsdb.retention.time=7d'

# Restart Prometheus
docker-compose restart prometheus

# Clean up old data
docker exec dogetionary-prometheus-1 rm -rf /prometheus/wal/*
```

### Dashboard Not Loading

**Symptom**: Dashboard shows blank or loading forever

**Solutions**:
```bash
# Check Grafana logs
docker logs dogetionary-grafana-1 | grep ERROR

# Test datasource connection
curl -s -u admin:admin123 -X POST http://localhost:3000/api/datasources/uid/PBFA97CFB590B2093/health

# Check dashboard JSON syntax
cat grafana/dashboards/api_overview.json | python3 -m json.tool

# Force dashboard reload
docker-compose restart grafana

# Check browser console for errors
# Open http://localhost:3000 and press F12
```

---

## Best Practices

### Logging

1. **Use appropriate log levels**:
   - `DEBUG`: Detailed information for diagnosing problems
   - `INFO`: General informational messages
   - `WARNING`: Warning messages for potentially harmful situations
   - `ERROR`: Error messages for failures
   - `CRITICAL`: Critical failures requiring immediate attention

2. **Include context in log messages**:
   ```python
   logger.error(f"Failed to fetch definition for word='{word}', user_id={user_id}")
   ```

3. **Don't log sensitive data**:
   - Never log passwords, API keys, tokens
   - Be careful with PII (emails, phone numbers)

4. **Use structured logging for complex data**:
   ```python
   logger.info(f"LLM call completed", extra={
       'provider': provider,
       'model': model,
       'duration': duration,
       'tokens': tokens
   })
   ```

### Metrics

1. **Use labels wisely**:
   - Keep cardinality low (avoid user_id as label)
   - Use consistent label names across metrics
   - Document what each label represents

2. **Choose the right metric type**:
   - **Counter**: Always-increasing values (requests, errors, bytes)
   - **Gauge**: Values that go up and down (in-flight requests, memory usage)
   - **Histogram**: Distributions (latency, request size)

3. **Name metrics clearly**:
   - Use `_total` suffix for counters
   - Use `_seconds` suffix for duration
   - Use units in names (`bytes`, `requests`, `usd`)

4. **Track both success and failure**:
   ```python
   llm_calls_total{status="success"}
   llm_calls_total{status="error"}
   ```

### Dashboards

1. **Organize by use case**:
   - API performance dashboard for developers
   - Business metrics dashboard for product managers
   - Cost tracking dashboard for finance

2. **Use appropriate time ranges**:
   - Real-time monitoring: Last 5-15 minutes
   - Debugging: Last 1-6 hours
   - Trend analysis: Last 7-30 days

3. **Set meaningful thresholds**:
   - Green/Yellow/Red for SLOs
   - Alert thresholds for automated notifications

4. **Document your panels**:
   - Add descriptions to panels
   - Include PromQL query in panel title if helpful
   - Link to runbooks for alerts

---

## Additional Resources

### Prometheus Documentation
- PromQL Basics: https://prometheus.io/docs/prometheus/latest/querying/basics/
- Best Practices: https://prometheus.io/docs/practices/naming/
- HTTP API: https://prometheus.io/docs/prometheus/latest/querying/api/

### Grafana Documentation
- Dashboard Best Practices: https://grafana.com/docs/grafana/latest/dashboards/
- Provisioning: https://grafana.com/docs/grafana/latest/administration/provisioning/
- PromQL in Grafana: https://grafana.com/docs/grafana/latest/datasources/prometheus/

### Python prometheus_client
- Client Library: https://github.com/prometheus/client_python
- Examples: https://github.com/prometheus/client_python/tree/master/examples

---

## Summary

The Dogetionary monitoring stack provides:

✅ **Comprehensive Logging**
- Separate error logs for quick debugging
- Automatic log rotation and backup
- Easy CLI access with `view_logs.sh`

✅ **Real-time Metrics**
- HTTP request tracking (rate, latency, errors)
- LLM call monitoring (tokens, cost, latency)
- Business metrics (reviews, words, schedules)

✅ **Visual Dashboards**
- API Overview: 8 panels for HTTP performance
- LLM Metrics: 8 panels for AI/ML tracking
- Auto-provisioned and version-controlled

✅ **Production-Ready**
- 30-day data retention
- Automatic instrumentation
- Docker-based deployment
- Easy to extend and customize

For questions or issues, check the [Troubleshooting](#troubleshooting) section or review the configuration files.
