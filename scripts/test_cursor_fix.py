#!/usr/bin/env python3
"""
Test script to verify cursor fetch fixes.

Tests that the fixed functions handle empty results gracefully without
corrupting connection state.
"""

import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from services.audio_service import audio_exists
from handlers.reads import get_forgetting_curve
from utils.database import db_fetch_one

def test_audio_exists_empty_result():
    """Test that audio_exists() handles empty results gracefully"""
    print("TEST 1: audio_exists() with non-existent audio")

    # This should return False without throwing exception
    result = audio_exists('nonexistent-text-xyz-12345', 'en')

    if result == False:
        print("✅ PASS: audio_exists() returned False for non-existent audio")
    else:
        print(f"❌ FAIL: Expected False, got {result}")
        return False

    return True

def test_sequential_queries():
    """Test that multiple queries work after empty results"""
    print("\nTEST 2: Sequential queries after empty results")

    # First query - should return None
    result1 = db_fetch_one("""
        SELECT * FROM audio WHERE text_content = %s
    """, ('fake-text-99999',))

    if result1 is None:
        print("✅ PASS: First query returned None")
    else:
        print(f"❌ FAIL: Expected None, got {result1}")
        return False

    # Second query - should still work (connection not corrupted)
    result2 = db_fetch_one("SELECT 1 as test")

    if result2 and result2.get('test') == 1:
        print("✅ PASS: Second query succeeded (connection not corrupted)")
    else:
        print(f"❌ FAIL: Expected {{'test': 1}}, got {result2}")
        return False

    # Third query - another empty result
    result3 = db_fetch_one("""
        SELECT * FROM audio WHERE text_content = %s
    """, ('another-fake-99999',))

    if result3 is None:
        print("✅ PASS: Third query returned None")
    else:
        print(f"❌ FAIL: Expected None, got {result3}")
        return False

    # Fourth query - should still work
    result4 = db_fetch_one("SELECT 2 as test")

    if result4 and result4.get('test') == 2:
        print("✅ PASS: Fourth query succeeded (connection still healthy)")
    else:
        print(f"❌ FAIL: Expected {{'test': 2}}, got {result4}")
        return False

    return True

def test_mixed_empty_and_non_empty():
    """Test mixing empty and non-empty queries"""
    print("\nTEST 3: Mixed empty and non-empty queries")

    for i in range(5):
        # Alternate between empty and non-empty queries
        if i % 2 == 0:
            result = db_fetch_one(f"SELECT {i} as num")
            if result and result.get('num') == i:
                print(f"  ✅ Query {i+1}: Non-empty query succeeded")
            else:
                print(f"  ❌ Query {i+1}: Failed")
                return False
        else:
            result = db_fetch_one("""
                SELECT * FROM audio WHERE text_content = %s
            """, (f'fake-{i}',))
            if result is None:
                print(f"  ✅ Query {i+1}: Empty query returned None")
            else:
                print(f"  ❌ Query {i+1}: Expected None, got {result}")
                return False

    print("✅ PASS: All mixed queries succeeded")
    return True

def main():
    print("=" * 60)
    print("Database Cursor Fix Test Suite")
    print("=" * 60)

    tests = [
        test_audio_exists_empty_result,
        test_sequential_queries,
        test_mixed_empty_and_non_empty,
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
