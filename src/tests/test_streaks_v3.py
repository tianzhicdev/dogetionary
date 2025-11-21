"""
Integration tests for V3 Streak Days functionality.

Tests:
- GET /v3/get-streak-days
- Automatic streak creation in submit_review
- Consecutive streak calculation logic
"""

import requests
import uuid
from datetime import datetime, timedelta
import psycopg2
from psycopg2.extras import RealDictCursor
import pytz

# Configuration
BASE_URL = "http://localhost:5000"
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'dbname': 'dogetionary',
    'user': 'dogeuser',
    'password': 'dogepass'
}

def get_db_connection():
    """Get a database connection"""
    return psycopg2.connect(**DB_CONFIG, cursor_factory=RealDictCursor)

def setup_test_user():
    """Create a test user with timezone"""
    user_id = str(uuid.uuid4())
    conn = get_db_connection()
    cur = conn.cursor()

    # Create user preferences with timezone
    cur.execute("""
        INSERT INTO user_preferences (user_id, learning_language, native_language, timezone)
        VALUES (%s, 'en', 'zh', 'UTC')
    """, (user_id,))

    conn.commit()
    cur.close()
    conn.close()

    return user_id

def cleanup_test_user(user_id):
    """Clean up test user data"""
    conn = get_db_connection()
    cur = conn.cursor()

    # Delete in order: reviews, saved_words, streak_days, user_preferences
    cur.execute("DELETE FROM reviews WHERE user_id = %s", (user_id,))
    cur.execute("DELETE FROM saved_words WHERE user_id = %s", (user_id,))
    cur.execute("DELETE FROM streak_days WHERE user_id = %s", (user_id,))
    cur.execute("DELETE FROM user_preferences WHERE user_id = %s", (user_id,))

    conn.commit()
    cur.close()
    conn.close()

def save_test_word(user_id, word):
    """Save a word for testing"""
    response = requests.post(f"{BASE_URL}/v3/save", json={
        "user_id": user_id,
        "word": word,
        "learning_language": "en",
        "native_language": "zh"
    })
    assert response.status_code == 201, f"Failed to save word: {response.text}"
    return response.json()['word_id']

def submit_test_review(user_id, word_id, response_bool):
    """Submit a review for testing"""
    response = requests.post(f"{BASE_URL}/v3/reviews/submit", json={
        "user_id": user_id,
        "word_id": word_id,
        "response": response_bool
    })
    assert response.status_code == 200, f"Failed to submit review: {response.text}"
    return response.json()

def insert_streak_date(user_id, date_str):
    """Manually insert a streak date for testing"""
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("""
        INSERT INTO streak_days (user_id, streak_date)
        VALUES (%s, %s)
        ON CONFLICT (user_id, streak_date) DO NOTHING
    """, (user_id, date_str))

    conn.commit()
    cur.close()
    conn.close()

def test_get_streak_days_no_streaks():
    """Test GET /v3/get-streak-days with no streak records"""
    print("Test 1: Get streak days with no streaks")

    user_id = setup_test_user()

    try:
        # Call get-streak-days
        response = requests.get(f"{BASE_URL}/v3/get-streak-days", params={
            "user_id": user_id
        })

        assert response.status_code == 200, f"Expected 200, got {response.status_code}"
        data = response.json()

        assert data['user_id'] == user_id
        assert data['streak_days'] == 0, f"Expected 0 streak days, got {data['streak_days']}"

        print("✅ Test 1 passed: No streaks = 0")

    finally:
        cleanup_test_user(user_id)

def test_get_streak_days_consecutive():
    """Test GET /v3/get-streak-days with consecutive dates"""
    print("\nTest 2: Get streak days with consecutive dates")

    user_id = setup_test_user()

    try:
        # Insert consecutive streak dates: today, yesterday, day before yesterday
        # Use UTC timezone to match backend
        tz = pytz.timezone('UTC')
        today = datetime.now(tz).date()
        insert_streak_date(user_id, today)
        insert_streak_date(user_id, today - timedelta(days=1))
        insert_streak_date(user_id, today - timedelta(days=2))

        # Call get-streak-days
        response = requests.get(f"{BASE_URL}/v3/get-streak-days", params={
            "user_id": user_id
        })

        assert response.status_code == 200
        data = response.json()

        assert data['streak_days'] == 3, f"Expected 3 streak days, got {data['streak_days']}"

        print("✅ Test 2 passed: Consecutive dates = 3")

    finally:
        cleanup_test_user(user_id)

def test_get_streak_days_with_gap():
    """Test GET /v3/get-streak-days with a gap in dates"""
    print("\nTest 3: Get streak days with gap (should reset)")

    user_id = setup_test_user()

    try:
        # Insert dates with gap: today, 3 days ago (missing yesterday and day before)
        tz = pytz.timezone('UTC')
        today = datetime.now(tz).date()
        insert_streak_date(user_id, today)
        insert_streak_date(user_id, today - timedelta(days=3))

        # Call get-streak-days
        response = requests.get(f"{BASE_URL}/v3/get-streak-days", params={
            "user_id": user_id
        })

        assert response.status_code == 200
        data = response.json()

        # Should only count today (1) because there's a gap
        assert data['streak_days'] == 1, f"Expected 1 streak day, got {data['streak_days']}"

        print("✅ Test 3 passed: Gap detected, streak = 1")

    finally:
        cleanup_test_user(user_id)

def test_get_streak_days_only_yesterday():
    """Test GET /v3/get-streak-days with only yesterday (missing today)"""
    print("\nTest 4: Get streak days with only yesterday (missing today)")

    user_id = setup_test_user()

    try:
        # Insert only yesterday's date
        tz = pytz.timezone('UTC')
        today = datetime.now(tz).date()
        insert_streak_date(user_id, today - timedelta(days=1))
        insert_streak_date(user_id, today - timedelta(days=2))
        insert_streak_date(user_id, today - timedelta(days=3))

        # Call get-streak-days
        response = requests.get(f"{BASE_URL}/v3/get-streak-days", params={
            "user_id": user_id
        })

        assert response.status_code == 200
        data = response.json()

        # Should be 0 because today is missing
        assert data['streak_days'] == 0, f"Expected 0 streak days, got {data['streak_days']}"

        print("✅ Test 4 passed: Missing today, streak = 0")

    finally:
        cleanup_test_user(user_id)

def test_streak_auto_creation_on_review():
    """Test automatic streak creation when user completes all reviews"""
    print("\nTest 5: Auto-create streak when user completes all reviews")

    user_id = setup_test_user()

    try:
        # Save one word
        word_id = save_test_word(user_id, "test")

        # Wait a bit to ensure word is due
        conn = get_db_connection()
        cur = conn.cursor()
        # Manually set created_at to 2 days ago to make it due
        cur.execute("""
            UPDATE saved_words
            SET created_at = NOW() - INTERVAL '2 days'
            WHERE id = %s
        """, (word_id,))
        conn.commit()
        cur.close()
        conn.close()

        # Submit review (correct answer)
        submit_test_review(user_id, word_id, True)

        # Check if streak was created
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT COUNT(*) as count
            FROM streak_days
            WHERE user_id = %s AND streak_date = CURRENT_DATE
        """, (user_id,))
        result = cur.fetchone()
        cur.close()
        conn.close()

        assert result['count'] == 1, f"Expected 1 streak record, got {result['count']}"

        # Verify get-streak-days returns 1
        response = requests.get(f"{BASE_URL}/v3/get-streak-days", params={
            "user_id": user_id
        })
        data = response.json()
        assert data['streak_days'] == 1, f"Expected 1 streak day, got {data['streak_days']}"

        print("✅ Test 5 passed: Streak auto-created after completing reviews")

    finally:
        cleanup_test_user(user_id)

def test_streak_idempotent():
    """Test that streak creation is idempotent"""
    print("\nTest 6: Streak creation is idempotent")

    user_id = setup_test_user()

    try:
        # Insert same date multiple times
        tz = pytz.timezone('UTC')
        today = datetime.now(tz).date()
        insert_streak_date(user_id, today)
        insert_streak_date(user_id, today)
        insert_streak_date(user_id, today)

        # Check only one record exists
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT COUNT(*) as count
            FROM streak_days
            WHERE user_id = %s AND streak_date = %s
        """, (user_id, today))
        result = cur.fetchone()
        cur.close()
        conn.close()

        assert result['count'] == 1, f"Expected 1 record, got {result['count']}"

        print("✅ Test 6 passed: Idempotent streak creation")

    finally:
        cleanup_test_user(user_id)

if __name__ == "__main__":
    print("=== Starting V3 Streak Days Integration Tests ===\n")

    try:
        test_get_streak_days_no_streaks()
        test_get_streak_days_consecutive()
        test_get_streak_days_with_gap()
        test_get_streak_days_only_yesterday()
        test_streak_auto_creation_on_review()
        test_streak_idempotent()

        print("\n=== ✅ All tests passed! ===")
    except AssertionError as e:
        print(f"\n=== ❌ Test failed: {e} ===")
        raise
    except Exception as e:
        print(f"\n=== ❌ Error: {e} ===")
        raise
