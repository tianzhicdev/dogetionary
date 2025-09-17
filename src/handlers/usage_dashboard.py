"""
Usage dashboard with HTML tables for monitoring user activity
"""

from flask import Response
from utils.database import get_db_connection
from datetime import datetime, timedelta
import logging
import pytz

logger = logging.getLogger(__name__)

# Define NY timezone
NY_TZ = pytz.timezone('America/New_York')

def get_usage_dashboard():
    """
    Generate HTML dashboard with usage analytics tables
    """
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # Get data for the past 7 days (in NY time)
        now_ny = datetime.now(NY_TZ)
        seven_days_ago = (now_ny - timedelta(days=7)).astimezone(pytz.UTC).replace(tzinfo=None)

        # 1. New users table (user_id, registration time)
        cur.execute("""
            SELECT
                user_id,
                created_at
            FROM user_preferences
            WHERE created_at >= %s
            ORDER BY created_at DESC
        """, (seven_days_ago,))

        new_users = cur.fetchall()

        # 2. Lookups table - we'll track saved words as proxy for lookups since we don't track individual lookups
        # For real lookups, we'd need a separate lookup_history table
        cur.execute("""
            SELECT DISTINCT
                sw.user_id,
                sw.word,
                MIN(sw.created_at) as first_lookup
            FROM saved_words sw
            WHERE sw.created_at >= %s
            GROUP BY sw.user_id, sw.word
            ORDER BY first_lookup DESC
            LIMIT 100
        """, (seven_days_ago,))

        lookups = cur.fetchall()

        # 3. Saved words table (user_id, word, learning_language, timestamp)
        cur.execute("""
            SELECT
                user_id,
                word,
                learning_language,
                created_at
            FROM saved_words
            WHERE created_at >= %s
            ORDER BY created_at DESC
            LIMIT 100
        """, (seven_days_ago,))

        saved_words = cur.fetchall()

        # Get daily counts for the past 7 days
        cur.execute("""
            WITH date_series AS (
                SELECT generate_series(
                    date_trunc('day', %s::timestamp),
                    date_trunc('day', CURRENT_TIMESTAMP),
                    '1 day'::interval
                )::date as day
            )
            SELECT
                ds.day,
                COALESCE(nu.count, 0) as new_users,
                COALESCE(sw.count, 0) as saved_words
            FROM date_series ds
            LEFT JOIN (
                SELECT
                    date_trunc('day', created_at)::date as day,
                    COUNT(*) as count
                FROM user_preferences
                WHERE created_at >= %s
                GROUP BY day
            ) nu ON ds.day = nu.day
            LEFT JOIN (
                SELECT
                    date_trunc('day', created_at)::date as day,
                    COUNT(*) as count
                FROM saved_words
                WHERE created_at >= %s
                GROUP BY day
            ) sw ON ds.day = sw.day
            ORDER BY ds.day DESC
        """, (seven_days_ago, seven_days_ago, seven_days_ago))

        daily_stats = cur.fetchall()

        cur.close()
        conn.close()

        # Generate HTML
        html = generate_html_dashboard(new_users, lookups, saved_words, daily_stats)

        return Response(html, mimetype='text/html')

    except Exception as e:
        logger.error(f"Error generating usage dashboard: {str(e)}")
        error_html = f"""
        <html>
        <head><title>Error</title></head>
        <body>
            <h1>Error generating dashboard</h1>
            <p>{str(e)}</p>
        </body>
        </html>
        """
        return Response(error_html, mimetype='text/html', status=500)

def convert_to_ny_time(timestamp):
    """Convert UTC timestamp to NY timezone"""
    if timestamp:
        utc_time = pytz.UTC.localize(timestamp)
        ny_time = utc_time.astimezone(NY_TZ)
        return ny_time
    return None

def generate_html_dashboard(new_users, lookups, saved_words, daily_stats):
    """Generate HTML dashboard with tables"""

    # Get current time in NY
    now_ny = datetime.now(NY_TZ)

    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Dogetionary Usage Dashboard</title>
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                margin: 20px;
                background-color: #f5f5f5;
            }
            h1 {
                color: #333;
                border-bottom: 2px solid #4CAF50;
                padding-bottom: 10px;
            }
            h2 {
                color: #555;
                margin-top: 30px;
            }
            table {
                background-color: white;
                border-collapse: collapse;
                width: 100%;
                margin-bottom: 30px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            th {
                background-color: #4CAF50;
                color: white;
                padding: 12px;
                text-align: left;
                font-weight: 600;
            }
            td {
                padding: 10px 12px;
                border-bottom: 1px solid #ddd;
            }
            tr:hover {
                background-color: #f9f9f9;
            }
            .timestamp {
                color: #666;
                font-size: 0.9em;
            }
            .user-id {
                font-family: 'Courier New', monospace;
                font-size: 0.85em;
                color: #2196F3;
            }
            .word {
                font-weight: 500;
                color: #333;
            }
            .language {
                background-color: #e3f2fd;
                color: #1976d2;
                padding: 2px 8px;
                border-radius: 3px;
                font-size: 0.85em;
                display: inline-block;
            }
            .summary-box {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 20px;
                border-radius: 8px;
                margin-bottom: 30px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            }
            .summary-stats {
                display: flex;
                justify-content: space-around;
                margin-top: 15px;
            }
            .stat-item {
                text-align: center;
            }
            .stat-value {
                font-size: 2em;
                font-weight: bold;
            }
            .stat-label {
                font-size: 0.9em;
                opacity: 0.9;
            }
            .section {
                background-color: white;
                padding: 20px;
                border-radius: 8px;
                margin-bottom: 20px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            .daily-stats {
                background-color: #fff3e0;
            }
            .daily-stats td {
                text-align: center;
            }
            .no-data {
                text-align: center;
                padding: 20px;
                color: #999;
                font-style: italic;
            }
        </style>
    </head>
    <body>
        <h1>🐕 Dogetionary Usage Dashboard</h1>
        <p style="color: #666;">Last 7 days activity • Updated: """ + now_ny.strftime('%Y-%m-%d %H:%M:%S ET') + """</p>

        <div class="summary-box">
            <h3 style="margin-top: 0;">Weekly Summary</h3>
            <div class="summary-stats">
                <div class="stat-item">
                    <div class="stat-value">""" + str(len(new_users)) + """</div>
                    <div class="stat-label">New Users</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">""" + str(len(lookups)) + """</div>
                    <div class="stat-label">Lookups</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value">""" + str(len(saved_words)) + """</div>
                    <div class="stat-label">Saved Words</div>
                </div>
            </div>
        </div>

        <div class="section">
            <h2>📊 Daily Statistics</h2>
            <table class="daily-stats">
                <thead>
                    <tr>
                        <th>Date</th>
                        <th>New Users</th>
                        <th>Words Saved</th>
                    </tr>
                </thead>
                <tbody>
    """

    # Add daily stats
    for row in daily_stats:
        html += f"""
                    <tr>
                        <td>{row['day'].strftime('%Y-%m-%d')}</td>
                        <td><strong>{row['new_users']}</strong></td>
                        <td><strong>{row['saved_words']}</strong></td>
                    </tr>
        """

    html += """
                </tbody>
            </table>
        </div>

        <div class="section">
            <h2>👤 New Users</h2>
    """

    if new_users:
        html += """
            <table>
                <thead>
                    <tr>
                        <th>User ID</th>
                        <th>Registration Time</th>
                    </tr>
                </thead>
                <tbody>
        """
        for user in new_users:
            ny_time = convert_to_ny_time(user['created_at'])
            html += f"""
                    <tr>
                        <td class="user-id">{user['user_id']}</td>
                        <td class="timestamp">{ny_time.strftime('%Y-%m-%d %H:%M:%S ET')}</td>
                    </tr>
            """
        html += """
                </tbody>
            </table>
        """
    else:
        html += '<div class="no-data">No new users in the last 7 days</div>'

    html += """
        </div>

        <div class="section">
            <h2>🔍 Recent Lookups</h2>
            <p style="color: #666; font-size: 0.9em;">Note: Showing saved words as proxy for lookups</p>
    """

    if lookups:
        html += """
            <table>
                <thead>
                    <tr>
                        <th>User ID</th>
                        <th>Word</th>
                        <th>Timestamp</th>
                    </tr>
                </thead>
                <tbody>
        """
        for lookup in lookups:
            ny_time = convert_to_ny_time(lookup['first_lookup'])
            html += f"""
                    <tr>
                        <td class="user-id">{lookup['user_id']}</td>
                        <td class="word">{lookup['word']}</td>
                        <td class="timestamp">{ny_time.strftime('%Y-%m-%d %H:%M:%S ET')}</td>
                    </tr>
            """
        html += """
                </tbody>
            </table>
        """
    else:
        html += '<div class="no-data">No lookups in the last 7 days</div>'

    html += """
        </div>

        <div class="section">
            <h2>💾 Saved Words</h2>
    """

    if saved_words:
        html += """
            <table>
                <thead>
                    <tr>
                        <th>User ID</th>
                        <th>Word</th>
                        <th>Learning Language</th>
                        <th>Timestamp</th>
                    </tr>
                </thead>
                <tbody>
        """
        for word in saved_words:
            ny_time = convert_to_ny_time(word['created_at'])
            html += f"""
                    <tr>
                        <td class="user-id">{word['user_id']}</td>
                        <td class="word">{word['word']}</td>
                        <td><span class="language">{word['learning_language'].upper()}</span></td>
                        <td class="timestamp">{ny_time.strftime('%Y-%m-%d %H:%M:%S ET')}</td>
                    </tr>
            """
        html += """
                </tbody>
            </table>
        """
    else:
        html += '<div class="no-data">No saved words in the last 7 days</div>'

    html += """
        </div>
    </body>
    </html>
    """

    return html