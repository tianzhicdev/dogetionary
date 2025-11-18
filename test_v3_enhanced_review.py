#!/usr/bin/env python3
"""
Test script for V3 enhanced review with lazy definition loading.
"""

import requests
import json
import psycopg2
from psycopg2.extras import RealDictCursor

# Test configuration
BASE_URL = "http://localhost:5000"
TEST_USER_ID = "12345678-1234-5678-1234-567812345678"  # Valid UUID for testing

def setup_test_user():
    """Create test user with a new word in schedule."""
    conn = psycopg2.connect(
        host="localhost",
        port=5432,
        database="dogetionary",
        user="dogeuser",
        password="dogepass"
    )
    cur = conn.cursor(cursor_factory=RealDictCursor)

    # Clear existing test data
    cur.execute("DELETE FROM daily_schedule_entries WHERE schedule_id IN (SELECT id FROM study_schedules WHERE user_id = %s)", (TEST_USER_ID,))
    cur.execute("DELETE FROM study_schedules WHERE user_id = %s", (TEST_USER_ID,))
    cur.execute("DELETE FROM reviews WHERE word_id IN (SELECT id FROM saved_words WHERE user_id = %s)", (TEST_USER_ID,))
    cur.execute("DELETE FROM saved_words WHERE user_id = %s", (TEST_USER_ID,))
    cur.execute("DELETE FROM definitions WHERE word = %s", ('ephemeral',))
    cur.execute("DELETE FROM review_questions WHERE word = %s", ('ephemeral',))
    cur.execute("DELETE FROM user_preferences WHERE user_id = %s", (TEST_USER_ID,))
    conn.commit()

    # Create user preferences
    cur.execute("""
        INSERT INTO user_preferences (user_id, learning_language, native_language, user_name, user_motto)
        VALUES (%s, 'en', 'zh', 'TestUser', 'Testing V3!')
    """, (TEST_USER_ID,))

    # Create study schedule
    cur.execute("""
        INSERT INTO study_schedules (user_id, test_type, target_end_date)
        VALUES (%s, 'TOEFL', CURRENT_DATE + INTERVAL '30 days')
        RETURNING id
    """, (TEST_USER_ID,))
    schedule_id = cur.fetchone()['id']

    # Add a new word to today's schedule (word without cached definition)
    cur.execute("""
        INSERT INTO daily_schedule_entries (schedule_id, scheduled_date, new_words)
        VALUES (%s, CURRENT_DATE, %s)
    """, (schedule_id, json.dumps(['ephemeral'])))

    conn.commit()
    cur.close()
    conn.close()

    print(f"✓ Test user {TEST_USER_ID} set up with new word 'ephemeral' in schedule")

def test_enhanced_review():
    """Test enhanced review endpoint with lazy definition loading."""
    print("\n=== Testing Enhanced Review with Lazy Definition Loading ===")

    # Call enhanced review endpoint
    url = f"{BASE_URL}/v3/review_next_enhanced"
    params = {"user_id": TEST_USER_ID}

    print(f"\nCalling: GET {url}?user_id={TEST_USER_ID}")
    response = requests.get(url, params=params)

    print(f"Status Code: {response.status_code}")

    if response.status_code == 200:
        data = response.json()
        print(f"\n✓ Success! Response:")
        print(json.dumps(data, indent=2))

        # Verify structure
        assert 'word' in data, "Missing 'word' field"
        assert 'question' in data, "Missing 'question' field"
        assert 'definition' in data, "Missing 'definition' field"
        assert data['word'] == 'ephemeral', f"Expected 'ephemeral', got '{data['word']}'"

        # Verify definition has V3 structure
        definition = data['definition']
        assert 'valid_word_score' in definition, "Missing valid_word_score"
        assert 'suggestion' in definition, "Missing suggestion"
        assert 'part_of_speech' in definition.get('definitions', [{}])[0], "Missing part_of_speech in definition"

        print(f"\n✓ Definition validation score: {definition.get('valid_word_score')}")
        print(f"✓ Question type: {data['question'].get('question_type')}")
        print(f"✓ Is new word: {data.get('is_new_word')}")

        return True
    else:
        print(f"\n✗ Request failed: {response.text}")
        return False

def check_backend_logs():
    """Check backend logs for V3 definition generation messages."""
    print("\n=== Checking Backend Logs ===")
    import subprocess

    result = subprocess.run(
        ["docker-compose", "logs", "--tail=50", "app"],
        capture_output=True,
        text=True
    )

    logs = result.stdout

    # Look for V3 definition generation log messages
    if "Successfully fetched and cached V3 definition for 'ephemeral'" in logs:
        print("✓ Found V3 definition generation log")

        # Extract the validation score from logs
        for line in logs.split('\n'):
            if 'ephemeral' in line and 'score:' in line:
                print(f"  {line.strip()}")
    else:
        print("Relevant backend logs:")
        for line in logs.split('\n'):
            if 'ephemeral' in line.lower() or 'definition' in line.lower():
                print(f"  {line.strip()}")

if __name__ == "__main__":
    try:
        setup_test_user()
        success = test_enhanced_review()
        check_backend_logs()

        if success:
            print("\n✓✓✓ All tests passed! V3 definition generation working correctly. ✓✓✓")
        else:
            print("\n✗✗✗ Tests failed ✗✗✗")
            exit(1)
    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
