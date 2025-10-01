"""
API Usage Analytics Handler

Provides analytics on endpoint usage for tracking API deprecation
and client version migration.
"""

from flask import jsonify, request
import logging
from utils.database import get_db_connection

logger = logging.getLogger(__name__)

def get_api_usage_analytics():
    """
    GET /api/usage

    Returns endpoint usage statistics:
    - Past 1 day: count and last call timestamp
    - Past 3 days: count and last call timestamp
    - Past 7 days: count and last call timestamp
    """
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # Get endpoint usage statistics for different time periods
        cur.execute("""
            WITH endpoint_stats AS (
                SELECT
                    endpoint,
                    method,
                    api_version,
                    MAX(timestamp) FILTER (WHERE timestamp >= NOW() - INTERVAL '1 day') as last_call_1d,
                    COUNT(*) FILTER (WHERE timestamp >= NOW() - INTERVAL '1 day') as count_1d,
                    MAX(timestamp) FILTER (WHERE timestamp >= NOW() - INTERVAL '3 days') as last_call_3d,
                    COUNT(*) FILTER (WHERE timestamp >= NOW() - INTERVAL '3 days') as count_3d,
                    MAX(timestamp) FILTER (WHERE timestamp >= NOW() - INTERVAL '7 days') as last_call_7d,
                    COUNT(*) FILTER (WHERE timestamp >= NOW() - INTERVAL '7 days') as count_7d,
                    AVG(duration_ms) FILTER (WHERE timestamp >= NOW() - INTERVAL '7 days') as avg_duration_ms_7d
                FROM api_usage_logs
                WHERE timestamp >= NOW() - INTERVAL '7 days'
                GROUP BY endpoint, method, api_version
            )
            SELECT
                endpoint,
                method,
                api_version,
                last_call_1d,
                count_1d,
                last_call_3d,
                count_3d,
                last_call_7d,
                count_7d,
                avg_duration_ms_7d
            FROM endpoint_stats
            WHERE count_7d > 0
            ORDER BY count_7d DESC, endpoint ASC
        """)

        endpoints = []
        for row in cur.fetchall():
            endpoints.append({
                "endpoint": row['endpoint'],
                "method": row['method'],
                "api_version": row['api_version'],
                "past_1_day": {
                    "count": row['count_1d'] or 0,
                    "last_call": row['last_call_1d'].isoformat() if row['last_call_1d'] else None
                },
                "past_3_days": {
                    "count": row['count_3d'] or 0,
                    "last_call": row['last_call_3d'].isoformat() if row['last_call_3d'] else None
                },
                "past_7_days": {
                    "count": row['count_7d'] or 0,
                    "last_call": row['last_call_7d'].isoformat() if row['last_call_7d'] else None
                },
                "avg_duration_ms": round(row['avg_duration_ms_7d'], 2) if row['avg_duration_ms_7d'] else None
            })

        # Get summary statistics
        cur.execute("""
            SELECT
                COUNT(DISTINCT endpoint) as total_endpoints,
                COUNT(*) as total_calls_7d,
                COUNT(DISTINCT user_id) as unique_users_7d,
                AVG(duration_ms) as avg_duration_ms
            FROM api_usage_logs
            WHERE timestamp >= NOW() - INTERVAL '7 days'
        """)

        summary = cur.fetchone()

        # Get version breakdown
        cur.execute("""
            SELECT
                COALESCE(api_version, 'unversioned') as version,
                COUNT(*) as call_count,
                COUNT(DISTINCT endpoint) as endpoint_count,
                MAX(timestamp) as last_call
            FROM api_usage_logs
            WHERE timestamp >= NOW() - INTERVAL '7 days'
            GROUP BY api_version
            ORDER BY call_count DESC
        """)

        versions = []
        for row in cur.fetchall():
            versions.append({
                "version": row['version'],
                "call_count": row['call_count'],
                "endpoint_count": row['endpoint_count'],
                "last_call": row['last_call'].isoformat() if row['last_call'] else None
            })

        cur.close()
        conn.close()

        return jsonify({
            "summary": {
                "total_endpoints": summary['total_endpoints'] or 0,
                "total_calls_7d": summary['total_calls_7d'] or 0,
                "unique_users_7d": summary['unique_users_7d'] or 0,
                "avg_duration_ms": round(summary['avg_duration_ms'], 2) if summary['avg_duration_ms'] else None
            },
            "version_breakdown": versions,
            "endpoints": endpoints
        })

    except Exception as e:
        logger.error(f"Error getting API usage analytics: {str(e)}")
        return jsonify({"error": f"Failed to get API usage analytics: {str(e)}"}), 500
