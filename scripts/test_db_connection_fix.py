#!/usr/bin/env python3
"""
Test script to verify database connection pool fixes.

This tests:
1. db_fetch_one() returns None for empty results (not exception)
2. Connections are properly cleaned up and returned to pool
3. No "lost synchronization" errors occur
"""

import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from utils.database import db_fetch_one, db_fetch_all, get_db_connection

def test_empty_result_handling():
    """Test that db_fetch_one() handles empty results gracefully"""
    print("TEST 1: Empty result handling")

    # Query that should return no results
    result = db_fetch_one("""
        SELECT * FROM user_preferences WHERE user_id = %s
    """, ('nonexistent-user-id-12345',))

    if result is None:
        print("✅ PASS: db_fetch_one() returned None for empty result")
    else:
        print(f"❌ FAIL: Expected None, got {result}")
        return False

    return True

def test_connection_pool_integrity():
    """Test that connections are properly returned to pool"""
    print("\nTEST 2: Connection pool integrity")

    # Get and release multiple connections
    for i in range(10):
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        result = cur.fetchone()
        cur.close()
        conn.close()

    print("✅ PASS: All connections returned to pool without errors")
    return True

def test_mixed_operations():
    """Test mixing empty and non-empty queries"""
    print("\nTEST 3: Mixed empty and non-empty queries")

    # This should succeed
    result1 = db_fetch_one("SELECT 1 as num")
    if result1 and result1.get('num') == 1:
        print("✅ PASS: Non-empty query worked")
    else:
        print(f"❌ FAIL: Expected {{'num': 1}}, got {result1}")
        return False

    # This should return None
    result2 = db_fetch_one("""
        SELECT * FROM user_preferences WHERE user_id = %s
    """, ('fake-user-99999',))

    if result2 is None:
        print("✅ PASS: Empty query returned None")
    else:
        print(f"❌ FAIL: Expected None, got {result2}")
        return False

    # Another non-empty query
    result3 = db_fetch_one("SELECT 2 as num")
    if result3 and result3.get('num') == 2:
        print("✅ PASS: Subsequent non-empty query worked")
    else:
        print(f"❌ FAIL: Expected {{'num': 2}}, got {result3}")
        return False

    return True

def test_connection_state_recovery():
    """Test that connections recover from error states"""
    print("\nTEST 4: Connection state recovery")

    conn = get_db_connection()
    try:
        cur = conn.cursor()
        # Intentionally cause an error
        try:
            cur.execute("SELECT * FROM nonexistent_table_xyz")
        except Exception as e:
            print(f"  Expected error occurred: {type(e).__name__}")

        cur.close()
        conn.close()

        # Now try to use the pool again - should work fine
        result = db_fetch_one("SELECT 1 as test")
        if result and result.get('test') == 1:
            print("✅ PASS: Connection pool recovered from error state")
            return True
        else:
            print(f"❌ FAIL: Pool did not recover, got {result}")
            return False
    except Exception as e:
        print(f"❌ FAIL: Unexpected error: {e}")
        return False

def main():
    print("=" * 60)
    print("Database Connection Pool Fix Test Suite")
    print("=" * 60)

    tests = [
        test_empty_result_handling,
        test_connection_pool_integrity,
        test_mixed_operations,
        test_connection_state_recovery,
    ]

    passed = 0
    failed = 0

    for test_func in tests:
        try:
            if test_func():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"❌ EXCEPTION in {test_func.__name__}: {e}")
            import traceback
            traceback.print_exc()
            failed += 1

    print("\n" + "=" * 60)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 60)

    return 0 if failed == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
