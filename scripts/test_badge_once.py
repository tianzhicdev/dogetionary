#!/usr/bin/env python3
"""
Integration test for badge one-time display feature.

Tests that:
1. Badges are returned on first earn
2. Badges are NOT returned on subsequent reviews after being earned
3. Both score-based and test-completion badges work correctly
"""

import requests
import uuid
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

BASE_URL = "http://localhost:5001"

def test_score_badge_once():
    """Test that score badges are only returned once."""
    print("\n=== Testing Score Badge One-Time Display ===")

    # Create a unique test user
    user_id = str(uuid.uuid4())
    print(f"Test user ID: {user_id}")

    # Set user preferences
    response = requests.post(f"{BASE_URL}/v3/users/{user_id}/preferences", json={
        "learning_language": "en",
        "native_language": "zh"
    })
    assert response.status_code == 200, f"Failed to set preferences: {response.text}"
    print("✓ User preferences set")

    # Submit enough reviews to earn score_1 badge (1 review = 2 points if correct)
    # Score 1 milestone should be earned immediately with first correct review
    response = requests.post(f"{BASE_URL}/reviews/submit", json={
        "user_id": user_id,
        "word": "test_word_1",
        "learning_language": "en",
        "native_language": "zh",
        "response": True,  # Correct answer = 2 points
        "question_type": "mc_definition"
    })
    assert response.status_code == 200, f"Failed first review: {response.text}"
    data = response.json()
    print(f"✓ First review submitted (score: {data['new_score']})")

    # Check if score_1 badge was returned
    if data.get('new_badges') and any(b['badge_id'] == 'score_1' for b in data['new_badges']):
        print("✓ Badge 'score_1' returned on first earn")
    else:
        print(f"✗ FAIL: Expected badge 'score_1' not returned. Badges: {data.get('new_badges')}")
        return False

    # Submit another review - badge should NOT be returned again
    response = requests.post(f"{BASE_URL}/reviews/submit", json={
        "user_id": user_id,
        "word": "test_word_1",
        "learning_language": "en",
        "native_language": "zh",
        "response": True,
        "question_type": "mc_definition"
    })
    assert response.status_code == 200, f"Failed second review: {response.text}"
    data = response.json()
    print(f"✓ Second review submitted (score: {data['new_score']})")

    # Check that score_1 badge is NOT returned again
    if data.get('new_badges') and any(b['badge_id'] == 'score_1' for b in data['new_badges']):
        print(f"✗ FAIL: Badge 'score_1' returned again (should only show once). Badges: {data['new_badges']}")
        return False
    else:
        print("✓ Badge 'score_1' NOT returned on second review (correct behavior)")

    # Verify badge is in user_badges table
    import psycopg2
    conn = psycopg2.connect(
        host="localhost",
        port=5432,
        database="dogetionary",
        user="dogeuser",
        password="dogepass"
    )
    cur = conn.cursor()
    cur.execute("""
        SELECT badge_id, badge_type, earned_at, shown_at
        FROM user_badges
        WHERE user_id = %s AND badge_id = 'score_1'
    """, (user_id,))
    result = cur.fetchone()
    cur.close()
    conn.close()

    if result:
        print(f"✓ Badge 'score_1' found in user_badges table: {result}")
    else:
        print("✗ FAIL: Badge 'score_1' not found in user_badges table")
        return False

    print("\n✅ Score badge one-time display test PASSED")
    return True


def test_completion_badge_once():
    """Test that completion badges are only returned once."""
    print("\n=== Testing Completion Badge One-Time Display ===")

    # Create a unique test user
    user_id = str(uuid.uuid4())
    print(f"Test user ID: {user_id}")

    # Set user preferences with DEMO test enabled
    response = requests.post(f"{BASE_URL}/v3/users/{user_id}/preferences", json={
        "learning_language": "en",
        "native_language": "zh",
        "test_prep": "DEMO",
        "study_duration_days": 30
    })
    assert response.status_code == 200, f"Failed to set preferences: {response.text}"
    print("✓ User preferences set (DEMO test enabled)")

    # Get all DEMO words
    import psycopg2
    conn = psycopg2.connect(
        host="localhost",
        port=5432,
        database="dogetionary",
        user="dogeuser",
        password="dogepass"
    )
    cur = conn.cursor()
    cur.execute("""
        SELECT word FROM bundle_vocabularies
        WHERE is_demo = TRUE AND language = 'en'
        ORDER BY word
    """)
    demo_words = [row[0] for row in cur.fetchall()]
    cur.close()
    conn.close()

    print(f"✓ Found {len(demo_words)} DEMO words")

    if len(demo_words) == 0:
        print("✗ SKIP: No DEMO words in database")
        return True  # Skip test if no DEMO words

    # Review all but one DEMO word
    for i, word in enumerate(demo_words[:-1]):
        response = requests.post(f"{BASE_URL}/reviews/submit", json={
            "user_id": user_id,
            "word": word,
            "learning_language": "en",
            "native_language": "zh",
            "response": True,
            "question_type": "mc_definition"
        })
        assert response.status_code == 200, f"Failed to review word '{word}': {response.text}"

        # Badge should NOT be returned yet (not complete)
        data = response.json()
        if data.get('new_badges') and any(b['badge_id'] == 'DEMO' for b in data['new_badges']):
            print(f"✗ FAIL: DEMO badge returned prematurely on word {i+1}/{len(demo_words)}")
            return False

    print(f"✓ Reviewed {len(demo_words)-1}/{len(demo_words)} DEMO words (no badge yet)")

    # Review the last word - DEMO badge should be returned
    last_word = demo_words[-1]
    response = requests.post(f"{BASE_URL}/reviews/submit", json={
        "user_id": user_id,
        "word": last_word,
        "learning_language": "en",
        "native_language": "zh",
        "response": True,
        "question_type": "mc_definition"
    })
    assert response.status_code == 200, f"Failed to review last word '{last_word}': {response.text}"
    data = response.json()

    if data.get('new_badges') and any(b['badge_id'] == 'DEMO' for b in data['new_badges']):
        print("✓ DEMO badge returned on completion")
    else:
        print(f"✗ FAIL: DEMO badge not returned on completion. Badges: {data.get('new_badges')}")
        return False

    # Review any DEMO word again - badge should NOT be returned
    response = requests.post(f"{BASE_URL}/reviews/submit", json={
        "user_id": user_id,
        "word": demo_words[0],
        "learning_language": "en",
        "native_language": "zh",
        "response": True,
        "question_type": "mc_definition"
    })
    assert response.status_code == 200, f"Failed second review: {response.text}"
    data = response.json()

    if data.get('new_badges') and any(b['badge_id'] == 'DEMO' for b in data['new_badges']):
        print(f"✗ FAIL: DEMO badge returned again (should only show once). Badges: {data['new_badges']}")
        return False
    else:
        print("✓ DEMO badge NOT returned on subsequent review (correct behavior)")

    # Verify badge is in user_badges table
    conn = psycopg2.connect(
        host="localhost",
        port=5432,
        database="dogetionary",
        user="dogeuser",
        password="dogepass"
    )
    cur = conn.cursor()
    cur.execute("""
        SELECT badge_id, badge_type, earned_at, shown_at
        FROM user_badges
        WHERE user_id = %s AND badge_id = 'DEMO'
    """, (user_id,))
    result = cur.fetchone()
    cur.close()
    conn.close()

    if result:
        print(f"✓ Badge 'DEMO' found in user_badges table: {result}")
    else:
        print("✗ FAIL: Badge 'DEMO' not found in user_badges table")
        return False

    print("\n✅ Completion badge one-time display test PASSED")
    return True


if __name__ == "__main__":
    print("\n" + "="*60)
    print("BADGE ONE-TIME DISPLAY INTEGRATION TEST")
    print("="*60)

    # Check if backend is running (use a simple endpoint that doesn't require auth)
    try:
        # Try to create a test user as a health check
        test_user_id = str(uuid.uuid4())
        response = requests.post(f"{BASE_URL}/v3/users/{test_user_id}/preferences", json={
            "learning_language": "en",
            "native_language": "zh"
        })
        if response.status_code not in [200, 201]:
            print(f"✗ Backend check failed: {response.status_code} - {response.text}")
            sys.exit(1)
    except Exception as e:
        print(f"✗ Could not connect to backend at {BASE_URL}: {e}")
        sys.exit(1)

    print("✓ Backend is running")

    # Run tests
    test1_passed = test_score_badge_once()
    test2_passed = test_completion_badge_once()

    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    print(f"Score badge test: {'✅ PASSED' if test1_passed else '❌ FAILED'}")
    print(f"Completion badge test: {'✅ PASSED' if test2_passed else '❌ FAILED'}")

    if test1_passed and test2_passed:
        print("\n🎉 ALL TESTS PASSED!")
        sys.exit(0)
    else:
        print("\n❌ SOME TESTS FAILED")
        sys.exit(1)
