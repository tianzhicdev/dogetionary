import os
import psycopg2
from psycopg2.extras import RealDictCursor
from config.config import SUPPORTED_LANGUAGES
from contextlib import contextmanager
from typing import Optional, List, Dict, Any, Union
import logging

logger = logging.getLogger(__name__)

DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')

def validate_language(lang: str) -> bool:
    """Validate if language code is supported"""
    return lang in SUPPORTED_LANGUAGES

def get_db_connection():
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)

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
            conn.close()

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