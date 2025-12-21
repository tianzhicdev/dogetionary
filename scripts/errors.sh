#!/bin/bash
# Quick script to fetch latest error logs from production
# Usage: ./scripts/errors.sh [limit]

LIMIT=${1:-100}
HOURS=${2:-1}

curl -G "https://kwafy.com/loki/api/v1/query_range" \
  --data-urlencode "query={job=\"dogetionary_errors\"}" \
  --data-urlencode "limit=${LIMIT}" \
  --data-urlencode "start=$(date -u -v-${HOURS}H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "${HOURS} hours ago" '+%Y-%m-%dT%H:%M:%SZ')" \
  --data-urlencode "end=$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --data-urlencode "direction=backward" \
  -s | jq -r '
    .data.result[]?.values[]? |
    (.[0] | tonumber / 1000000000 | strftime("%Y-%m-%d %H:%M:%S")) + " " + .[1]
  ' 2>/dev/null || echo "Error: Failed to fetch logs or parse response"
