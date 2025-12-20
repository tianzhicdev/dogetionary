# Due Words Query Analysis: Extract Common Logic

## Executive Summary

**YES** - There is significant overlap between `get_review_words_batch()` and `get_due_counts()` that can be extracted into a shared function.

Both functions implement the **same core logic** for determining which words are "due for review", but:
- `get_due_counts()` **counts** due words
- `get_review_words_batch()` **fetches** due words with additional filtering

**Recommendation**: Extract shared due words query logic into a reusable service function.

---

## Current State

### Function 1: `get_due_counts()` (reads.py:421-439)

**Purpose**: Count how many words are due for review

**Query logic**:
```sql
SELECT
    COUNT(*) as total_count,
    COUNT(CASE
        WHEN COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= NOW()
        THEN 1
    END) as due_count
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
```

**Returns**: `{total_count, due_count}`

---

### Function 2: `get_review_words_batch()` (review_batch.py:73-93)

**Purpose**: Fetch actual due words for review questions

**Query logic**:
```sql
SELECT sw.id as saved_word_id, sw.word, sw.learning_language, sw.native_language
FROM saved_words sw
LEFT JOIN (
    SELECT word_id, next_review_date,
           ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
    FROM reviews
) r ON sw.id = r.word_id AND r.rn = 1
WHERE sw.user_id = %s
AND (sw.is_known IS NULL OR sw.is_known = FALSE)
AND (
    r.next_review_date IS NULL OR  -- Never reviewed
    r.next_review_date <= CURRENT_DATE  -- Due today or earlier
)
{exclude_clause}  -- Optional: exclude certain words
ORDER BY RANDOM()
LIMIT %s
```

**Returns**: List of word rows with `{saved_word_id, word, learning_language, native_language}`

---

## Common Patterns

### 1. Identical LEFT JOIN with ROW_NUMBER()

Both use **exact same pattern** to get latest review:
```sql
LEFT JOIN (
    SELECT
        word_id,
        next_review_date,
        ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
    FROM reviews
) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
```

**Purpose**: Get the most recent review for each word (with next_review_date)

### 2. Identical Base Filters

Both filter on:
```sql
WHERE sw.user_id = %s
AND (sw.is_known IS NULL OR sw.is_known = FALSE)
```

**Purpose**: Only include words that belong to user and are not marked as "known"

### 3. Similar Due Logic

**`get_due_counts()` uses**:
```sql
COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= NOW()
```

**`get_review_words_batch()` uses**:
```sql
r.next_review_date IS NULL OR  -- Never reviewed (due after 1 day)
r.next_review_date <= CURRENT_DATE  -- Reviewed before (due by date)
```

**Difference**:
- `get_due_counts()`: Uses `NOW()` (datetime precision) and `COALESCE` for unreviewed words
- `get_review_words_batch()`: Uses `CURRENT_DATE` (date precision) and explicit NULL check

**This is a subtle inconsistency!** They should use the same logic.

---

## Differences

### 1. Return Data

- **`get_due_counts()`**: Returns counts only (aggregation)
- **`get_review_words_batch()`**: Returns actual word rows (with SELECT fields)

### 2. Additional Features in `get_review_words_batch()`

- ✅ `exclude_clause`: Filter out specific words
- ✅ `ORDER BY RANDOM()`: Randomize word selection
- ✅ `LIMIT`: Return only N words

### 3. Timestamp Precision

- **`get_due_counts()`**: Uses `NOW()` (includes time)
- **`get_review_words_batch()`**: Uses `CURRENT_DATE` (date only)

**This inconsistency could cause edge cases!**

---

## Proposed Extraction Strategy

### Option 1: Extract Base CTE (Recommended)

Create a **base query builder** that both functions can use:

```python
def build_due_words_base_query(
    user_id: str,
    exclude_words: list = None,
    use_datetime: bool = False  # NOW() vs CURRENT_DATE
) -> tuple[str, list]:
    """
    Build base query for due words with consistent logic.

    Returns:
        (query_string, params_list)
    """
    # Build exclude clause
    exclude_clause = ""
    exclude_params = []
    if exclude_words:
        placeholders = ','.join(['%s'] * len(exclude_words))
        exclude_clause = f"AND sw.word NOT IN ({placeholders})"
        exclude_params = list(exclude_words)

    # Choose date comparison (consistent across both functions)
    date_comparison = "NOW()" if use_datetime else "CURRENT_DATE"

    base_query = f"""
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
        AND COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= {date_comparison}
        {exclude_clause}
    """

    params = [user_id] + exclude_params

    return base_query, params
```

**Usage in `get_due_counts()`**:
```python
def get_due_counts():
    user_id = request.args.get('user_id')

    base_query, params = build_due_words_base_query(user_id, use_datetime=True)

    count_query = f"""
        SELECT
            COUNT(*) as total_words,
            COUNT(*) as due_count  -- All words in base query are due
        {base_query}
    """

    cur.execute(count_query, params)
    result = cur.fetchone()

    return jsonify({
        "user_id": user_id,
        "overdue_count": result['due_count'],
        "total_count": result['total_words']  # Total saved words (separate query)
    })
```

**Usage in `get_review_words_batch()`**:
```python
def get_review_words_batch():
    user_id = request.args.get('user_id')
    count = int(request.args.get('count', '10'))
    exclude_words = set(...)  # Parse from request

    base_query, params = build_due_words_base_query(
        user_id,
        exclude_words=list(exclude_words),
        use_datetime=False  # Use CURRENT_DATE for consistency
    )

    fetch_query = f"""
        SELECT sw.id as saved_word_id, sw.word, sw.learning_language, sw.native_language
        {base_query}
        ORDER BY RANDOM()
        LIMIT %s
    """

    cur.execute(fetch_query, params + [count])
    due_words = cur.fetchall()
    ...
```

---

### Option 2: Create Due Words Service Function

Alternative: Create a service function that encapsulates both use cases:

```python
# services/due_words_service.py

def get_due_words_query(
    user_id: str,
    mode: str = 'fetch',  # 'fetch' or 'count'
    exclude_words: list = None,
    limit: int = None,
    randomize: bool = True
) -> dict:
    """
    Unified due words query service.

    Args:
        user_id: User UUID
        mode: 'fetch' (get words) or 'count' (count only)
        exclude_words: Optional words to exclude
        limit: Optional limit for fetch mode
        randomize: Random order (fetch mode only)

    Returns:
        For 'count' mode: {total_count, due_count}
        For 'fetch' mode: list of word dicts
    """
    conn = get_db_connection()
    cur = conn.cursor()

    # Base subquery for latest review
    base_from = """
        FROM saved_words sw
        LEFT JOIN (
            SELECT
                word_id,
                next_review_date,
                ROW_NUMBER() OVER (PARTITION BY word_id ORDER BY reviewed_at DESC) as rn
            FROM reviews
        ) latest_review ON sw.id = latest_review.word_id AND latest_review.rn = 1
    """

    # Base WHERE conditions
    base_where = """
        WHERE sw.user_id = %s
        AND (sw.is_known IS NULL OR sw.is_known = FALSE)
        AND COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= CURRENT_DATE
    """

    params = [user_id]

    # Add exclusions
    if exclude_words:
        placeholders = ','.join(['%s'] * len(exclude_words))
        base_where += f" AND sw.word NOT IN ({placeholders})"
        params.extend(exclude_words)

    if mode == 'count':
        # Count mode
        query = f"""
            SELECT COUNT(*) as due_count
            {base_from}
            {base_where}
        """
        cur.execute(query, params)
        result = cur.fetchone()

        # Also get total saved words count
        cur.execute("""
            SELECT COUNT(*) as total_count
            FROM saved_words
            WHERE user_id = %s
            AND (is_known IS NULL OR is_known = FALSE)
        """, (user_id,))
        total = cur.fetchone()

        cur.close()
        conn.close()

        return {
            'due_count': result['due_count'],
            'total_count': total['total_count']
        }

    elif mode == 'fetch':
        # Fetch mode
        query = f"""
            SELECT sw.id as saved_word_id, sw.word, sw.learning_language, sw.native_language
            {base_from}
            {base_where}
        """

        if randomize:
            query += " ORDER BY RANDOM()"

        if limit:
            query += " LIMIT %s"
            params.append(limit)

        cur.execute(query, params)
        words = cur.fetchall()

        cur.close()
        conn.close()

        return [dict(row) for row in words]
```

---

## Benefits of Extraction

### 1. Consistency

- **Single source of truth** for "what words are due"
- **No more discrepancies** between NOW() vs CURRENT_DATE
- **Same logic** used for counting and fetching

### 2. Maintainability

- **One place to update** due word logic
- **Easier to test** (single function to unit test)
- **DRY principle** (Don't Repeat Yourself)

### 3. Bug Prevention

- **Current inconsistency**: `get_due_counts()` might count a word as due, but `get_review_words_batch()` might not fetch it (or vice versa)
- **After extraction**: Both use exact same logic, guaranteed consistency

### 4. Future Extensibility

- Easy to add new parameters (e.g., filter by language, test type)
- Can support both datetime and date precision with a flag
- Centralized place for performance optimizations

---

## Recommended Approach

**Recommend Option 1: Extract Base CTE**

**Why**:
- Less invasive change
- Each function keeps its specific SELECT fields
- Shared logic is clearly separated
- Easy to understand and test

**Implementation steps**:
1. Create `build_due_words_base_query()` in a new service file
2. Update `get_due_counts()` to use the builder
3. Update `get_review_words_batch()` to use the builder
4. **Fix the NOW() vs CURRENT_DATE inconsistency** (choose one standard)
5. Add unit tests for the builder function

---

## Inconsistency to Fix

### Current Problem

Two different date comparison methods:

**`get_due_counts()`**:
```sql
COALESCE(latest_review.next_review_date, sw.created_at + INTERVAL '1 day') <= NOW()
```

**`get_review_words_batch()`**:
```sql
r.next_review_date IS NULL OR r.next_review_date <= CURRENT_DATE
```

### Recommended Standard

Use **`CURRENT_DATE`** (date precision) for both:

**Reason**:
- Reviews are scheduled by **date**, not datetime
- Simpler logic (no time-of-day edge cases)
- Consistent with how `next_review_date` is stored (as a date)
- Matches user expectation ("due today" = "due on this date")

**Unified logic**:
```sql
COALESCE(latest_review.next_review_date, (sw.created_at + INTERVAL '1 day')::date) <= CURRENT_DATE
```

---

## Files to Modify

If we proceed with extraction:

1. **Create**: `src/services/due_words_service.py` (new file, ~80 lines)
2. **Modify**: `src/handlers/reads.py` (get_due_counts)
3. **Modify**: `src/handlers/review_batch.py` (get_review_words_batch)
4. **Test**: Add unit tests for the new service

**Total changes**: ~100 lines added, ~60 lines removed, net +40 lines

---

## Impact Analysis

### Low Risk

- ✅ Pure refactoring (no behavior change intended)
- ✅ Both functions have clear inputs/outputs
- ✅ Can be tested independently
- ✅ Gradual migration possible (one function at a time)

### Medium Impact

- Changes core logic for "what words are due"
- Affects review scheduling UX
- Should have integration tests

### High Value

- Eliminates current inconsistency bug
- Makes future changes easier
- Improves code quality significantly

---

## Testing Strategy

### Unit Tests

```python
def test_build_due_words_base_query_no_exclusions():
    query, params = build_due_words_base_query("user-123")
    assert "user-123" in params
    assert "sw.word NOT IN" not in query

def test_build_due_words_base_query_with_exclusions():
    query, params = build_due_words_base_query("user-123", exclude_words=["cat", "dog"])
    assert params == ["user-123", "cat", "dog"]
    assert "sw.word NOT IN" in query

def test_due_words_logic_consistency():
    # Verify count matches actual fetch
    counts = get_due_words_query(user_id, mode='count')
    words = get_due_words_query(user_id, mode='fetch')
    assert counts['due_count'] == len(words)
```

### Integration Tests

```python
def test_due_counts_matches_batch_fetch():
    """Ensure get_due_counts() and get_review_words_batch() agree"""
    # Call get_due_counts
    due_count_response = client.get('/v3/due_counts?user_id=test-user')
    due_count = due_count_response.json['overdue_count']

    # Call get_review_words_batch with high limit
    batch_response = client.get('/v3/next-review-words-batch?user_id=test-user&count=1000')
    batch_words = [q for q in batch_response.json['questions'] if q['source'] == 'due']

    # Should match (or batch_words <= due_count if limit exceeded)
    assert len(batch_words) == min(due_count, 1000)
```

---

## Answer to Your Question

> "we should extract the commonality between get_review_words_batch and get_due_counts; research, no code yet; perhaps a function they both call;"

**Answer**: **YES, absolutely!**

**Common logic to extract**:
1. ✅ Latest review LEFT JOIN with ROW_NUMBER()
2. ✅ Base WHERE filters (user_id, is_known)
3. ✅ Due date calculation logic

**Recommendation**:
- Extract into `build_due_words_base_query()` function
- Fix NOW() vs CURRENT_DATE inconsistency
- Use query builder pattern (Option 1)

**Benefits**:
- Eliminates current bug (inconsistent date logic)
- Single source of truth
- Easier to maintain and test

**Next steps**:
1. Decide on standard date comparison (CURRENT_DATE recommended)
2. Create `services/due_words_service.py`
3. Extract shared query builder
4. Update both functions to use it
5. Add tests

This is similar to the `get_or_create_saved_word()` helper we just created - same pattern of extracting common database logic! ✅
