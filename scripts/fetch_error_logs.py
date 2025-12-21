#!/usr/bin/env python3
"""
Fetch error logs from production Loki instance.

Usage:
    python scripts/fetch_error_logs.py                    # Last 100 errors
    python scripts/fetch_error_logs.py --limit 50         # Last 50 errors
    python scripts/fetch_error_logs.py --hours 24         # Errors from last 24 hours
    python scripts/fetch_error_logs.py --job dogetionary_errors  # Specific job
    python scripts/fetch_error_logs.py --query '{job="dogetionary"} |= "Traceback"'  # Custom query
"""

import argparse
import requests
import sys
from datetime import datetime, timedelta
from typing import Optional

LOKI_URL = "https://kwafy.com/loki/api/v1/query_range"


def fetch_loki_logs(
    query: str,
    hours: int = 1,
    limit: int = 100,
    start_time: Optional[str] = None,
    end_time: Optional[str] = None
) -> dict:
    """
    Fetch logs from Loki API.

    Args:
        query: LogQL query string
        hours: Number of hours to look back (default: 1)
        limit: Maximum number of log entries (default: 100)
        start_time: Optional ISO format start time (overrides hours)
        end_time: Optional ISO format end time (overrides hours)

    Returns:
        JSON response from Loki
    """
    # Calculate time range
    if end_time:
        end = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
    else:
        end = datetime.utcnow()

    if start_time:
        start = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
    else:
        start = end - timedelta(hours=hours)

    # Prepare query parameters
    params = {
        'query': query,
        'start': start.isoformat() + 'Z',
        'end': end.isoformat() + 'Z',
        'limit': limit,
        'direction': 'backward'  # Most recent first
    }

    print(f"🔍 Querying Loki: {LOKI_URL}", file=sys.stderr)
    print(f"   Query: {query}", file=sys.stderr)
    print(f"   Time range: {start.isoformat()} to {end.isoformat()}", file=sys.stderr)
    print(f"   Limit: {limit}", file=sys.stderr)
    print("", file=sys.stderr)

    try:
        response = requests.get(LOKI_URL, params=params, timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"❌ Error querying Loki: {e}", file=sys.stderr)
        sys.exit(1)


def format_log_entry(timestamp_ns: str, log_line: str) -> str:
    """Format a single log entry with timestamp."""
    # Convert nanosecond timestamp to datetime
    timestamp_sec = int(timestamp_ns) / 1_000_000_000
    dt = datetime.fromtimestamp(timestamp_sec)
    formatted_time = dt.strftime('%Y-%m-%d %H:%M:%S')

    return f"[{formatted_time}] {log_line}"


def print_logs(response: dict, show_metadata: bool = False):
    """Print logs from Loki response."""
    data = response.get('data', {})
    result_type = data.get('resultType')
    results = data.get('result', [])

    if not results:
        print("✅ No logs found matching query", file=sys.stderr)
        return

    total_entries = 0
    for stream in results:
        stream_labels = stream.get('stream', {})
        values = stream.get('values', [])

        if show_metadata:
            print(f"\n📊 Stream: {stream_labels}", file=sys.stderr)
            print(f"   Entries: {len(values)}", file=sys.stderr)
            print("", file=sys.stderr)

        for timestamp_ns, log_line in values:
            print(format_log_entry(timestamp_ns, log_line))
            total_entries += 1

    print("", file=sys.stderr)
    print(f"✅ Found {total_entries} log entries", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Fetch error logs from production Loki',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Fetch last 100 errors
  %(prog)s

  # Fetch last 50 errors from last 6 hours
  %(prog)s --limit 50 --hours 6

  # Fetch errors from specific job
  %(prog)s --job dogetionary_errors

  # Custom LogQL query
  %(prog)s --query '{job="dogetionary"} |= "Traceback"'

  # Show metadata about log streams
  %(prog)s --metadata

Common LogQL patterns:
  - All errors: {job="dogetionary"} |~ "(?i)error"
  - Python tracebacks: {job="dogetionary"} |= "Traceback"
  - Specific handler: {job="dogetionary"} |= "review_batch" |= "error"
  - Error level: {job="dogetionary"} | json | level="ERROR"
"""
    )

    parser.add_argument(
        '--query',
        help='Custom LogQL query (overrides --job)',
        default=None
    )
    parser.add_argument(
        '--job',
        help='Loki job name (default: dogetionary_errors)',
        default='dogetionary_errors'
    )
    parser.add_argument(
        '--limit',
        type=int,
        help='Maximum number of log entries (default: 100)',
        default=100
    )
    parser.add_argument(
        '--hours',
        type=int,
        help='Number of hours to look back (default: 1)',
        default=1
    )
    parser.add_argument(
        '--start',
        help='Start time in ISO format (e.g., 2025-12-20T00:00:00Z)',
        default=None
    )
    parser.add_argument(
        '--end',
        help='End time in ISO format (e.g., 2025-12-20T23:59:59Z)',
        default=None
    )
    parser.add_argument(
        '--metadata',
        action='store_true',
        help='Show metadata about log streams'
    )

    args = parser.parse_args()

    # Build LogQL query
    if args.query:
        query = args.query
    else:
        query = f'{{job="{args.job}"}}'

    # Fetch logs
    response = fetch_loki_logs(
        query=query,
        hours=args.hours,
        limit=args.limit,
        start_time=args.start,
        end_time=args.end
    )

    # Print logs
    print_logs(response, show_metadata=args.metadata)


if __name__ == '__main__':
    main()
