"""
Due Words Service

Provides shared query building logic for determining which words are due for review.
Used by both get_due_counts() and get_review_words_batch() for consistency.
"""

import logging
from typing import Optional, List, Tuple

logger = logging.getLogger(__name__)


def build_due_words_base_query(
    user_id: str,
    exclude_words: Optional[List[str]] = None
) -> Tuple[str, List]:
    """
    Build base query components for finding due words with consistent logic.

    A word is considered "due" if:
    1. It has never been reviewed (due 1 day after creation)
    2. It has been reviewed and next_review_date <= CURRENT_DATE

    This function builds the FROM and WHERE clauses that both counting
    and fetching functions can use with their own SELECT statements.

    Args:
        user_id: User UUID string
        exclude_words: Optional list of words to exclude from results

    Returns:
        Tuple of (from_where_clause, params_list)

    Example:
        from_where, params = build_due_words_base_query(user_id, exclude_words=['cat', 'dog'])

        # For counting:
        count_query = f"SELECT COUNT(*) as due_count {from_where}"

        # For fetching:
        fetch_query = f"SELECT sw.id, sw.word {from_where} ORDER BY RANDOM() LIMIT 10"
    """
    # Build exclude clause if needed
    exclude_clause = ""
    exclude_params = []

    if exclude_words:
        placeholders = ','.join(['%s'] * len(exclude_words))
        exclude_clause = f"AND sw.word NOT IN ({placeholders})"
        exclude_params = list(exclude_words)

    # Build the FROM and WHERE clauses
    # Using CURRENT_DATE for consistent date-only comparison across all use cases
    from_where_clause = f"""
        FROM saved_words sw
        LEFT JOIN (
            SELECT
                word_id,
                next_review_date,
                ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
            FROM reviews
        ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
        WHERE sw.user_id = %s
        AND (sw.is_known IS NULL OR sw.is_known = FALSE)
        AND COALESCE(latest_review.next_review_date, (sw.created_at + INTERVAL '1 day')::date) <= CURRENT_DATE
        {exclude_clause}
    """

    # Build params list: [user_id, ...exclude_words]
    params = [user_id] + exclude_params

    return from_where_clause, params


def get_total_saved_words_count(user_id: str, conn) -> int:
    """
    Get total count of saved words for a user (excluding known words).

    This is separate from due words count - it's the total vocabulary size.

    Args:
        user_id: User UUID string
        conn: Database connection

    Returns:
        Total count of saved words
    """
    cur = conn.cursor()

    cur.execute("""
        SELECT COUNT(*) as total_count
        FROM saved_words
        WHERE user_id = %s
        AND (is_known IS NULL OR is_known = FALSE)
    """, (user_id,))

    result = cur.fetchone()
    cur.close()

    return result['total_count'] if result else 0
