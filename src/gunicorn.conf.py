"""
Gunicorn Configuration for Dogetionary API

Production-ready WSGI server configuration optimized for 100+ concurrent users.
"""

import multiprocessing
import os

# Server Socket
bind = "0.0.0.0:5000"
backlog = 2048  # Number of pending connections (default 2048)

# Worker Processes
# Formula: (2 x CPU cores) + 1
# For 4 vCPU: (2 x 4) + 1 = 9 workers
# But we use 4 workers to conserve memory for LLM operations
workers = int(os.environ.get('GUNICORN_WORKERS', 4))

# Worker Class
# 'sync' = traditional blocking workers (good for CPU-bound + external API calls)
# 'gevent' or 'eventlet' would be better for pure I/O, but OpenAI SDK works best with sync
worker_class = 'sync'

# Threads per worker
# Total concurrent requests = workers × threads = 4 × 2 = 8
# This is conservative to avoid memory pressure from LLM operations
threads = 2

# Worker Connections (for async workers like gevent, not used with sync)
worker_connections = 1000

# Timeout
# Set high because:
# - LLM API calls can take 2-10 seconds
# - Video processing can take 5-15 seconds
# - Question generation with retries can take up to 30 seconds
timeout = 120  # 2 minutes

# Keep-alive
keepalive = 5

# Graceful Timeout
# Time to wait for workers to finish during graceful shutdown
graceful_timeout = 30

# Max Requests
# Restart workers after this many requests to prevent memory leaks
max_requests = 1000
max_requests_jitter = 100  # Add randomness to avoid all workers restarting simultaneously

# Logging
accesslog = '/app/logs/gunicorn-access.log'
errorlog = '/app/logs/gunicorn-error.log'
loglevel = 'info'
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Process Naming
proc_name = 'dogetionary-api'

# Preload Application
# Load application before forking workers (saves memory via copy-on-write)
preload_app = True

# Graceful Reload
# Use SIGHUP to reload workers gracefully without dropping requests
reload = False  # Set to True for development

# Worker Tmp Directory
# Use /dev/shm (RAM disk) for worker heartbeat files (faster than disk)
worker_tmp_dir = '/dev/shm'

# Forwarded Allow IPS
# Trust Nginx reverse proxy headers
forwarded_allow_ips = '*'

# Server Mechanics
daemon = False  # Don't daemonize (Docker manages the process)
pidfile = None  # Don't create PID file
umask = 0
user = None
group = None
tmp_upload_dir = None

# Hooks

def on_starting(server):
    """Called before the master process is initialized."""
    server.log.info("=" * 60)
    server.log.info("Dogetionary API - Starting Gunicorn")
    server.log.info(f"Workers: {workers}, Threads per worker: {threads}")
    server.log.info(f"Total concurrent requests: {workers * threads}")
    server.log.info(f"Timeout: {timeout}s, Graceful timeout: {graceful_timeout}s")
    server.log.info("=" * 60)

def on_reload(server):
    """Called to recycle workers during a reload via SIGHUP."""
    server.log.info("Reloading Gunicorn workers...")

def when_ready(server):
    """Called after the server is ready to accept requests."""
    server.log.info("✅ Gunicorn is ready to accept requests")

def pre_fork(server, worker):
    """Called before a worker is forked."""
    pass

def post_fork(server, worker):
    """Called after a worker is forked."""
    server.log.info(f"Worker spawned (pid: {worker.pid})")

def worker_exit(server, worker):
    """Called when a worker exits."""
    server.log.info(f"Worker exiting (pid: {worker.pid})")

def pre_exec(server):
    """Called before a new master process is forked."""
    server.log.info("Forking new master process...")
