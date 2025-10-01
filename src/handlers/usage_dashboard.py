"""
Usage dashboard with HTML tables for monitoring user activity
"""

from flask import Response, request
from utils.database import get_db_connection
from datetime import datetime, timedelta
import logging
import pytz
from services.analytics_service import analytics_service

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

        # 2. Lookups table - using definitions table data (no user_id since definitions are cached globally)
        cur.execute("""
            SELECT
                word,
                learning_language,
                native_language,
                created_at as lookup_time
            FROM definitions
            WHERE created_at >= %s
            ORDER BY created_at DESC
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

        # Get analytics data for graphs
        action_summary = analytics_service.get_action_summary(7)
        daily_action_counts = analytics_service.get_daily_action_counts(30)
        time_analytics = []  # Not needed for current charts
        monthly_metrics = analytics_service.get_monthly_daily_metrics(30)
        available_users = analytics_service.get_all_users()

        # Get selected user actions if user_id provided
        selected_user_id = request.args.get('user_id')
        user_actions = []
        if selected_user_id:
            user_actions = analytics_service.get_user_actions(selected_user_id)

        # Generate HTML
        html = generate_html_dashboard(new_users, lookups, saved_words, daily_stats, action_summary, daily_action_counts, time_analytics, monthly_metrics, available_users, selected_user_id, user_actions)

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

def generate_html_dashboard(new_users, lookups, saved_words, daily_stats, action_summary, daily_action_counts, time_analytics, monthly_metrics, available_users, selected_user_id, user_actions):
    """Generate HTML dashboard with tables"""

    # Get current time in NY
    now_ny = datetime.now(NY_TZ)

    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Dogetionary Usage Dashboard</title>
        <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
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
            .chart-container {
                background-color: white;
                padding: 20px;
                border-radius: 8px;
                margin-bottom: 20px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                position: relative;
                height: 400px;
            }
            .chart-grid {
                display: grid;
                grid-template-columns: 1fr 1fr;
                gap: 20px;
                margin-bottom: 20px;
            }
        </style>
    </head>
    <body>
        <h1>🐕 Dogetionary Usage Dashboard</h1>
        <p style="color: #666;">Last 7 days activity • Updated: """ + now_ny.strftime('%Y-%m-%d %H:%M:%S ET') + """</p>

        <!-- Monthly Analytics Charts Section -->
        <div class="section">
            <h2>📊 Monthly Analytics (Last 30 Days)</h2>
            <div class="chart-grid">
                <div class="chart-container">
                    <h3>Daily Unique Users</h3>
                    <canvas id="monthlyUniqueUsersChart"></canvas>
                </div>
                <div class="chart-container">
                    <h3>Daily Total Counts</h3>
                    <canvas id="monthlyTotalCountsChart"></canvas>
                </div>
            </div>
        </div>

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
            <h2>📊 API Endpoint Usage (Last 7 Days)</h2>
            <p style="color: #666; font-size: 0.9em;">Track which endpoints are being called to identify deprecated APIs</p>
    """

    # Add API usage analytics
    try:
        api_conn = get_db_connection()
        api_cur = api_conn.cursor()

        api_cur.execute("""
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
                    AVG(duration_ms) FILTER (WHERE timestamp >= NOW() - INTERVAL '7 days') as avg_duration_ms
                FROM api_usage_logs
                WHERE timestamp >= NOW() - INTERVAL '7 days'
                GROUP BY endpoint, method, api_version
            )
            SELECT * FROM endpoint_stats
            WHERE count_7d > 0
            ORDER BY count_7d DESC, endpoint ASC
        """)

        api_usage = api_cur.fetchall()
        api_cur.close()
        api_conn.close()

        if api_usage:
            html += """
                <table>
                    <thead>
                        <tr>
                            <th>Endpoint</th>
                            <th>Method</th>
                            <th>Version</th>
                            <th>1 Day</th>
                            <th>3 Days</th>
                            <th>7 Days</th>
                            <th>Last Call</th>
                            <th>Avg (ms)</th>
                        </tr>
                    </thead>
                    <tbody>
            """
            for row in api_usage:
                version = row['api_version'] or 'v1'
                version_style = 'color: #2196F3;' if row['api_version'] else 'color: #999;'
                html += f"""
                        <tr>
                            <td style="font-family: monospace;">{row['endpoint']}</td>
                            <td>{row['method']}</td>
                            <td style="{version_style}">{version}</td>
                            <td>{row['count_1d'] or 0}</td>
                            <td>{row['count_3d'] or 0}</td>
                            <td>{row['count_7d'] or 0}</td>
                            <td class="timestamp">{convert_to_ny_time(row['last_call_7d']).strftime('%m-%d %H:%M') if row['last_call_7d'] else '-'}</td>
                            <td>{round(row['avg_duration_ms'], 1) if row['avg_duration_ms'] else '-'}</td>
                        </tr>
                """
            html += """
                    </tbody>
                </table>
            """
        else:
            html += '<div class="no-data">No API calls tracked yet</div>'
    except Exception as e:
        html += f'<div class="no-data">Error loading API usage: {str(e)}</div>'

    html += """
        </div>

        <div class="section">
            <h2>🔍 Recent Lookups</h2>
            <p style="color: #666; font-size: 0.9em;">Cached word definitions from all users</p>
    """

    if lookups:
        html += """
            <table>
                <thead>
                    <tr>
                        <th>Word</th>
                        <th>Languages</th>
                        <th>Timestamp</th>
                    </tr>
                </thead>
                <tbody>
        """
        for lookup in lookups:
            ny_time = convert_to_ny_time(lookup['lookup_time'])
            html += f"""
                    <tr>
                        <td class="word">{lookup['word']}</td>
                        <td><span class="language">{lookup['learning_language'].upper()}</span> → <span class="language">{lookup['native_language'].upper()}</span></td>
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


    """

    # Generate daily data for the last 30 days
    import json

    # Create 30-day date range
    end_date = datetime.now().date()
    start_date = end_date - timedelta(days=29)  # 30 days total including today

    monthly_dates = []
    date_to_metrics = {}
    date_to_actions = {}

    # Create lookup dictionaries from analytics data
    for row in monthly_metrics:
        date_to_metrics[row['metric_date']] = row

    # Process daily action counts (multiple rows per date, one per action type)
    for row in daily_action_counts:
        date = row['action_date']
        if date not in date_to_actions:
            date_to_actions[date] = {'active': 0, 'search': 0, 'review': 0}

        # Categorize actions
        action = row['action']
        if action.startswith('dictionary'):
            date_to_actions[date]['search'] += row['count']
        elif action.startswith('review'):
            date_to_actions[date]['review'] += row['count']
        else:
            date_to_actions[date]['active'] += row['count']

    # Generate arrays for all 30 days
    active_users_data = []
    search_users_data = []
    review_users_data = []
    active_total_data = []
    search_total_data = []
    review_total_data = []

    current_date = start_date
    while current_date <= end_date:
        # Format date for display
        monthly_dates.append(current_date.strftime('%m/%d'))

        # Get metrics for this date (default to 0 if no data)
        metrics = date_to_metrics.get(current_date, {})
        actions = date_to_actions.get(current_date, {'active': 0, 'search': 0, 'review': 0})

        active_users_data.append(metrics.get('unique_active_users', 0))
        search_users_data.append(metrics.get('unique_search_users', 0))
        review_users_data.append(metrics.get('unique_review_users', 0))

        active_total_data.append(actions['active'])
        search_total_data.append(actions['search'])
        review_total_data.append(actions['review'])

        current_date += timedelta(days=1)

    # Convert to JSON for JavaScript
    monthly_dates_json = json.dumps(monthly_dates)
    active_users_json = json.dumps(active_users_data)
    search_users_json = json.dumps(search_users_data)
    review_users_json = json.dumps(review_users_data)
    active_total_json = json.dumps(active_total_data)
    search_total_json = json.dumps(search_total_data)
    review_total_json = json.dumps(review_total_data)

    # Generate JavaScript for monthly charts
    html += f"""
        <script>
        console.log('Creating monthly analytics charts...');

        // Monthly Unique Users Chart
        const uniqueCtx = document.getElementById('monthlyUniqueUsersChart').getContext('2d');
        const uniqueChart = new Chart(uniqueCtx, {{
            type: 'line',
            data: {{
                labels: {monthly_dates_json},
                datasets: [{{
                    label: 'Active Users',
                    data: {active_users_json},
                    borderColor: '#2196F3',
                    backgroundColor: '#2196F320',
                    fill: false,
                    tension: 0.1
                }}, {{
                    label: 'Search Users',
                    data: {search_users_json},
                    borderColor: '#4CAF50',
                    backgroundColor: '#4CAF5020',
                    fill: false,
                    tension: 0.1
                }}, {{
                    label: 'Review Users',
                    data: {review_users_json},
                    borderColor: '#FF9800',
                    backgroundColor: '#FF980020',
                    fill: false,
                    tension: 0.1
                }}]
            }},
            options: {{
                responsive: true,
                maintainAspectRatio: false,
                plugins: {{
                    title: {{
                        display: true,
                        text: 'Daily Unique Users by Activity (Last 30 Days)'
                    }}
                }},
                scales: {{
                    y: {{
                        beginAtZero: true,
                        title: {{
                            display: true,
                            text: 'Unique Users'
                        }}
                    }},
                    x: {{
                        title: {{
                            display: true,
                            text: 'Date'
                        }}
                    }}
                }}
            }}
        }});

        // Monthly Total Counts Chart
        const totalCtx = document.getElementById('monthlyTotalCountsChart').getContext('2d');
        const totalChart = new Chart(totalCtx, {{
            type: 'line',
            data: {{
                labels: {monthly_dates_json},
                datasets: [{{
                    label: 'Total Active Actions',
                    data: {active_total_json},
                    borderColor: '#2196F3',
                    backgroundColor: '#2196F320',
                    fill: false,
                    tension: 0.1
                }}, {{
                    label: 'Total Search Actions',
                    data: {search_total_json},
                    borderColor: '#4CAF50',
                    backgroundColor: '#4CAF5020',
                    fill: false,
                    tension: 0.1
                }}, {{
                    label: 'Total Review Actions',
                    data: {review_total_json},
                    borderColor: '#FF9800',
                    backgroundColor: '#FF980020',
                    fill: false,
                    tension: 0.1
                }}]
            }},
            options: {{
                responsive: true,
                maintainAspectRatio: false,
                plugins: {{
                    title: {{
                        display: true,
                        text: 'Daily Total Action Counts (Last 30 Days)'
                    }}
                }},
                scales: {{
                    y: {{
                        beginAtZero: true,
                        title: {{
                            display: true,
                            text: 'Total Actions'
                        }}
                    }},
                    x: {{
                        title: {{
                            display: true,
                            text: 'Date'
                        }}
                    }}
                }}
            }}
        }});

        console.log('Monthly charts created successfully');
        </script>
    """


    html += """
        <div class="section">
            <h2>👤 User Actions Viewer</h2>
            <form method="GET" style="margin-bottom: 20px;">
                <label for="user_id" style="font-weight: 600; margin-right: 10px;">Select User:</label>
                <select name="user_id" onchange="this.form.submit()" style="padding: 8px; border: 1px solid #ddd; border-radius: 4px; font-size: 14px;">
                    <option value="">-- Select a user --</option>
    """

    for user in available_users:
        selected = 'selected' if selected_user_id == user['user_id'] else ''
        html += f"""
                    <option value="{user['user_id']}" {selected}>{user['user_name']} ({user['user_id'][:8]}...)</option>
        """

    html += """
                </select>
            </form>
    """

    if selected_user_id and user_actions:
        html += """
            <table>
                <thead>
                    <tr>
                        <th>Timestamp</th>
                        <th>Action</th>
                        <th>Category</th>
                        <th>Metadata</th>
                        <th>Session ID</th>
                    </tr>
                </thead>
                <tbody>
        """

        for action in user_actions:
            ny_time = convert_to_ny_time(action['created_at'])
            metadata_str = str(action['metadata']) if action['metadata'] else '{}'
            session_id = action['session_id'][:8] + '...' if action['session_id'] else 'N/A'

            html += f"""
                    <tr>
                        <td class="timestamp">{ny_time.strftime('%Y-%m-%d %H:%M:%S ET')}</td>
                        <td class="word">{action['action']}</td>
                        <td><span class="language">{action['category'].upper()}</span></td>
                        <td style="max-width: 200px; word-wrap: break-word; font-size: 0.85em;">{metadata_str}</td>
                        <td class="user-id">{session_id}</td>
                    </tr>
            """

        html += """
                </tbody>
            </table>
        """
    elif selected_user_id:
        html += '<div class="no-data">No actions found for this user</div>'
    else:
        html += '<div class="no-data">Select a user to view their actions</div>'

    html += """
        </div>
    </body>
    </html>
    """

    return html