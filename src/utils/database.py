import os
import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor
from config.config import SUPPORTED_LANGUAGES
from contextlib import contextmanager
from typing import Optional, List, Dict, Any, Union
import logging
import atexit

logger = logging.getLogger(__name__)

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')

# =============================================================================
# CONNECTION POOL CONFIGURATION
# =============================================================================

# Global connection pool instance
_connection_pool = None

class PooledConnectionWrapper:
    """
    Wrapper for database connections that automatically returns them to the pool.

    When close() is called, returns the connection to the pool instead of closing it.
    """
    def __init__(self, conn, pool):
        self._conn = conn
        self._pool = pool
        self._closed = False

    def close(self):
        """Return connection to pool instead of closing"""
        if not self._closed and self._pool is not None and self._conn is not None:
            try:
                self._pool.putconn(self._conn)
                self._closed = True
            except Exception as e:
                logger.error(f"Failed to return connection to pool: {str(e)}")
                try:
                    self._conn.close()
                except:
                    pass

    def cursor(self, *args, **kwargs):
        """Forward cursor creation to underlying connection"""
        return self._conn.cursor(*args, **kwargs)

    def commit(self):
        """Forward commit to underlying connection"""
        return self._conn.commit()

    def rollback(self):
        """Forward rollback to underlying connection"""
        return self._conn.rollback()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None:
            try:
                self._conn.rollback()
            except:
                pass
        self.close()
        return False

    def __getattr__(self, name):
        """Forward all other attributes to underlying connection"""
        return getattr(self._conn, name)

def _initialize_connection_pool():
    """
    Initialize the database connection pool.

    Uses ThreadedConnectionPool for thread-safe connection management.
    Pool size: 5 min connections, 20 max connections

    This is called lazily on first connection request.
    """
    global _connection_pool

    if _connection_pool is not None:
        return

    try:
        # Extract connection parameters from DATABASE_URL
        # Format: postgresql://user:pass@host:port/dbname
        import re
        match = re.match(r'postgresql://([^:]+):([^@]+)@([^:]+):(\d+)/(.+)', DATABASE_URL)

        if not match:
            logger.error(f"Invalid DATABASE_URL format: {DATABASE_URL}")
            raise ValueError("Invalid DATABASE_URL format")

        user, password, host, port, dbname = match.groups()

        _connection_pool = pool.ThreadedConnectionPool(
            minconn=5,      # Minimum connections to maintain
            maxconn=20,     # Maximum connections allowed
            user=user,
            password=password,
            host=host,
            port=port,
            database=dbname,
            cursor_factory=RealDictCursor
        )

        logger.info("✅ Database connection pool initialized (min=5, max=20)")

        # Register cleanup on exit
        atexit.register(_close_connection_pool)

    except Exception as e:
        logger.error(f"Failed to initialize connection pool: {str(e)}")
        raise

def _close_connection_pool():
    """Close all connections in the pool on application shutdown."""
    global _connection_pool
    if _connection_pool is not None:
        _connection_pool.closeall()
        logger.info("✅ Database connection pool closed")
        _connection_pool = None

def _return_connection_to_pool(conn):
    """
    Return a connection to the pool.

    Args:
        conn: Database connection to return

    Note:
        This is called automatically by context managers.
        For manual connection management, call conn.close() which will
        trigger putconn() via the pool's connection wrapper.
    """
    global _connection_pool
    if _connection_pool is not None and conn is not None:
        try:
            _connection_pool.putconn(conn)
        except Exception as e:
            logger.error(f"Failed to return connection to pool: {str(e)}")
            # Fallback: close the connection directly
            try:
                conn.close()
            except:
                pass

def validate_language(lang: str) -> bool:
    """Validate if language code is supported"""
    return lang in SUPPORTED_LANGUAGES

def get_db_connection():
    """
    Get a database connection from the connection pool.

    Returns:
        PooledConnectionWrapper: A wrapped connection that automatically returns to pool on close()

    Note:
        Connections must be returned to the pool by calling conn.close()
        Use context managers (db_cursor, with statements) for automatic cleanup.
    """
    global _connection_pool

    # Lazy initialization of connection pool
    if _connection_pool is None:
        _initialize_connection_pool()

    try:
        raw_conn = _connection_pool.getconn()
        # Wrap connection so close() returns it to the pool
        return PooledConnectionWrapper(raw_conn, _connection_pool)
    except pool.PoolError as e:
        logger.error(f"Connection pool exhausted: {str(e)}")
        raise
    except Exception as e:
        logger.error(f"Failed to get connection from pool: {str(e)}")
        raise

@contextmanager
def db_cursor(commit: bool = False):
    """Context manager for database operations with automatic resource cleanup.

    Args:
        commit: Whether to commit the transaction (default: False for read operations)

    Yields:
        cursor: Database cursor with RealDictCursor for dict-like results

    Example:
        with db_cursor(commit=True) as cur:
            cur.execute("INSERT INTO ...")

    Note:
        Automatically returns connection to pool on exit
    """
    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        yield cur
        if commit:
            conn.commit()
    except Exception as e:
        if conn and commit:
            conn.rollback()
        logger.error(f"Database error: {str(e)}")
        raise
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()  # Wrapper automatically returns to pool

def db_execute(query: str, params: Optional[tuple] = None, commit: bool = False) -> int:
    """Execute a query without returning results (INSERT, UPDATE, DELETE).

    Args:
        query: SQL query to execute
        params: Query parameters
        commit: Whether to commit the transaction

    Returns:
        Number of affected rows

    Example:
        rows = db_execute(
            "UPDATE users SET active = %s WHERE id = %s",
            (True, user_id),
            commit=True
        )
    """
    with db_cursor(commit=commit) as cur:
        cur.execute(query, params)
        return cur.rowcount

def db_fetch_one(query: str, params: Optional[tuple] = None) -> Optional[Dict[str, Any]]:
    """Fetch a single row from the database.

    Args:
        query: SQL query to execute
        params: Query parameters

    Returns:
        Single row as dictionary or None if no results

    Example:
        user = db_fetch_one(
            "SELECT * FROM users WHERE id = %s",
            (user_id,)
        )
    """
    with db_cursor() as cur:
        cur.execute(query, params)
        return cur.fetchone()

def db_fetch_all(query: str, params: Optional[tuple] = None) -> List[Dict[str, Any]]:
    """Fetch all rows from the database.

    Args:
        query: SQL query to execute
        params: Query parameters

    Returns:
        List of rows as dictionaries

    Example:
        words = db_fetch_all(
            "SELECT * FROM saved_words WHERE user_id = %s",
            (user_id,)
        )
    """
    with db_cursor() as cur:
        cur.execute(query, params)
        return cur.fetchall()

def db_fetch_scalar(query: str, params: Optional[tuple] = None) -> Any:
    """Fetch a single value from the database.

    Args:
        query: SQL query to execute
        params: Query parameters

    Returns:
        Single value or None if no results

    Example:
        count = db_fetch_scalar(
            "SELECT COUNT(*) FROM saved_words WHERE user_id = %s",
            (user_id,)
        )
    """
    result = db_fetch_one(query, params)
    if result and len(result) > 0:
        return list(result.values())[0]
    return None

def db_insert_returning(query: str, params: Optional[tuple] = None, commit: bool = True) -> Optional[Dict[str, Any]]:
    """Execute INSERT query with RETURNING clause.

    Args:
        query: SQL INSERT query with RETURNING clause
        params: Query parameters
        commit: Whether to commit the transaction

    Returns:
        Inserted row data or None

    Example:
        result = db_insert_returning(
            "INSERT INTO saved_words (user_id, word) VALUES (%s, %s) RETURNING id, created_at",
            (user_id, word)
        )
    """
    with db_cursor(commit=commit) as cur:
        cur.execute(query, params)
        return cur.fetchone()

def db_bulk_insert(table: str, columns: List[str], values: List[tuple], commit: bool = True) -> int:
    """Bulk insert multiple rows efficiently.

    Args:
        table: Table name
        columns: List of column names
        values: List of tuples containing values for each row
        commit: Whether to commit the transaction

    Returns:
        Number of inserted rows

    Example:
        rows = db_bulk_insert(
            "saved_words",
            ["user_id", "word", "language"],
            [(user1, "hello", "en"), (user2, "world", "en")]
        )
    """
    if not values:
        return 0

    placeholders = ",".join(["%s"] * len(columns))
    columns_str = ",".join(columns)
    query = f"INSERT INTO {table} ({columns_str}) VALUES ({placeholders})"

    with db_cursor(commit=commit) as cur:
        cur.executemany(query, values)
        return cur.rowcount

def db_transaction(operations: List[tuple], commit: bool = True) -> List[Any]:
    """Execute multiple operations in a single transaction.

    Args:
        operations: List of (query, params) tuples
        commit: Whether to commit the transaction

    Returns:
        List of results (rowcount for each operation)

    Example:
        results = db_transaction([
            ("UPDATE users SET active = %s WHERE id = %s", (True, user_id)),
            ("INSERT INTO logs (user_id, action) VALUES (%s, %s)", (user_id, "activated"))
        ])
    """
    results = []
    with db_cursor(commit=commit) as cur:
        for query, params in operations:
            cur.execute(query, params)
            results.append(cur.rowcount)
    return results