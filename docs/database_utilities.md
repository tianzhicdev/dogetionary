# Database Utility Functions

## Overview
The database utility functions in `/src/utils/database.py` significantly reduce boilerplate code for database operations throughout the application.

## Key Utility Functions

### 1. `db_cursor(commit=False)`
Context manager that handles connection, cursor creation, commits, rollbacks, and cleanup automatically.

**Before:**
```python
conn = get_db_connection()
cur = conn.cursor()
try:
    cur.execute(query, params)
    result = cur.fetchone()
    conn.commit()
finally:
    cur.close()
    conn.close()
```

**After:**
```python
with db_cursor(commit=True) as cur:
    cur.execute(query, params)
    result = cur.fetchone()
```

### 2. `db_fetch_one(query, params)`
Fetch a single row without manual connection management.

**Before:**
```python
conn = get_db_connection()
cur = conn.cursor()
cur.execute(query, params)
result = cur.fetchone()
cur.close()
conn.close()
```

**After:**
```python
result = db_fetch_one(query, params)
```

### 3. `db_fetch_all(query, params)`
Fetch all rows with automatic cleanup.

**Before:**
```python
conn = get_db_connection()
cur = conn.cursor()
cur.execute(query, params)
results = cur.fetchall()
cur.close()
conn.close()
```

**After:**
```python
results = db_fetch_all(query, params)
```

### 4. `db_insert_returning(query, params)`
Insert data and return the inserted row.

**Before:**
```python
conn = get_db_connection()
cur = conn.cursor()
cur.execute("INSERT ... RETURNING ...", params)
result = cur.fetchone()
conn.commit()
cur.close()
conn.close()
```

**After:**
```python
result = db_insert_returning("INSERT ... RETURNING ...", params)
```

### 5. `db_execute(query, params, commit=False)`
Execute queries without returning results (UPDATE, DELETE).

**Before:**
```python
conn = get_db_connection()
cur = conn.cursor()
cur.execute(query, params)
conn.commit()
cur.close()
conn.close()
```

**After:**
```python
db_execute(query, params, commit=True)
```

## Benefits

1. **Reduced Lines of Code**: Each database operation saves 5-10 lines of boilerplate
2. **Automatic Resource Cleanup**: Connections and cursors are always properly closed
3. **Consistent Error Handling**: All database errors are logged and re-raised
4. **Transaction Safety**: Automatic rollback on errors when committing
5. **Improved Readability**: Focus on business logic instead of connection management

## Migration Example

Here's a real example from the codebase showing the reduction in boilerplate:

### Original Code (actions.py - save_word function):
```python
conn = get_db_connection()
cur = conn.cursor()

cur.execute("""
    INSERT INTO saved_words (user_id, word, learning_language, native_language, metadata)
    VALUES (%s, %s, %s, %s, %s)
    ON CONFLICT ON CONSTRAINT saved_words_user_id_word_learning_language_native_language_key
    DO UPDATE SET metadata = EXCLUDED.metadata
    RETURNING id, created_at
""", (user_id, word, learning_lang, native_lang, json.dumps(metadata)))

result = cur.fetchone()
conn.commit()
conn.close()
```

### Refactored Code:
```python
result = db_insert_returning("""
    INSERT INTO saved_words (user_id, word, learning_language, native_language, metadata)
    VALUES (%s, %s, %s, %s, %s)
    ON CONFLICT ON CONSTRAINT saved_words_user_id_word_learning_language_native_language_key
    DO UPDATE SET metadata = EXCLUDED.metadata
    RETURNING id, created_at
""", (user_id, word, learning_lang, native_lang, json.dumps(metadata)))
```

## Usage Guidelines

1. Use `db_fetch_one()` for SELECT queries expecting a single row
2. Use `db_fetch_all()` for SELECT queries expecting multiple rows
3. Use `db_insert_returning()` for INSERT with RETURNING clause
4. Use `db_execute()` for UPDATE/DELETE operations
5. Use `db_cursor()` context manager for complex multi-statement transactions
6. Use `db_transaction()` for executing multiple operations atomically

## Testing
All utility functions have been tested with integration tests in `/scripts/test_db_utils.py`.