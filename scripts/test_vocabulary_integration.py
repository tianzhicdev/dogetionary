#!/usr/bin/env python3
"""
Integration tests for test vocabulary feature.
Tests the complete flow from enabling test mode to adding daily words.
"""

import requests
import json
import uuid
import time
from datetime import datetime

# Configuration
API_BASE = "http://localhost:5000"
TEST_USER_ID = str(uuid.uuid4())

def test_setup():
    """Setup test user"""
    print("📋 Setting up test user...")

    # Create user preferences
    response = requests.put(f"{API_BASE}/preferences", json={
        "user_id": TEST_USER_ID,
        "learning_language": "en",
        "native_language": "zh"
    })

    if response.status_code not in [200, 201]:
        print(f"✅ Test user created: {TEST_USER_ID}")
    else:
        print(f"ℹ️  Using existing test setup")

    return TEST_USER_ID

def test_get_initial_settings():
    """Test getting initial test settings"""
    print("\n📋 Test 1: Get initial settings")

    response = requests.get(f"{API_BASE}/v3/users/{TEST_USER_ID}/preferences")

    assert response.status_code == 200, f"Failed: {response.text}"
    data = response.json()

    # In new API, test_prep is null when no test is enabled
    assert data.get("test_prep") is None or data.get("test_prep") == ""
    print("✅ Initial settings retrieved (test prep disabled)")

def test_enable_toefl():
    """Test enabling TOEFL preparation"""
    print("\n📋 Test 2: Enable TOEFL preparation")

    response = requests.post(f"{API_BASE}/v3/users/{TEST_USER_ID}/preferences", json={
        "learning_language": "en",
        "native_language": "zh",
        "user_name": "Test User",
        "user_motto": "Learning",
        "test_prep": "TOEFL_ADVANCED",
        "study_duration_days": 30
    })

    assert response.status_code == 200, f"Failed: {response.text}"
    data = response.json()

    assert data["test_prep"] == "TOEFL_ADVANCED"
    print("✅ TOEFL preparation enabled")

def test_add_daily_words():
    """Test adding daily test words"""
    print("\n📋 Test 3: Add daily test words")

    response = requests.post(f"{API_BASE}/test-prep/add-words", json={
        "user_id": TEST_USER_ID,
        "learning_language": "en",
        "native_language": "zh"
    })

    assert response.status_code == 200, f"Failed: {response.text}"
    data = response.json()

    assert "words_added" in data
    assert len(data["words_added"]) > 0
    word_count = len(data["words_added"])
    print(f"✅ Added {word_count} TOEFL words: {data['words_added'][:5]}...")

    # Check progress
    if data.get("progress", {}).get("toefl"):
        progress = data["progress"]["toefl"]
        print(f"   Progress: {progress['saved']}/{progress['total']} ({progress['percentage']}%)")

    return data["words_added"]

def test_prevent_duplicate_daily_add():
    """Test that words can't be added twice in same day"""
    print("\n📋 Test 4: Prevent duplicate daily additions")

    response = requests.post(f"{API_BASE}/test-prep/add-words", json={
        "user_id": TEST_USER_ID,
        "learning_language": "en",
        "native_language": "zh"
    })

    assert response.status_code == 200, f"Failed: {response.text}"
    data = response.json()

    assert "message" in data
    assert "already added" in data["message"].lower()
    print("✅ Duplicate addition prevented")

def test_enable_both_tests():
    """Test switching from TOEFL to IELTS"""
    print("\n📋 Test 5: Switch from TOEFL to IELTS")

    response = requests.post(f"{API_BASE}/v3/users/{TEST_USER_ID}/preferences", json={
        "learning_language": "en",
        "native_language": "zh",
        "user_name": "Test User",
        "user_motto": "Learning",
        "test_prep": "IELTS_BEGINNER",
        "study_duration_days": 45
    })

    assert response.status_code == 200, f"Failed: {response.text}"
    data = response.json()

    assert data["test_prep"] == "IELTS_BEGINNER"
    print("✅ Successfully switched to IELTS")

def test_check_saved_words():
    """Verify that test words were added to saved_words"""
    print("\n📋 Test 6: Verify words in saved_words")

    response = requests.get(f"{API_BASE}/words/saved", params={
        "user_id": TEST_USER_ID
    })

    if response.status_code == 200:
        data = response.json()
        saved_count = len(data.get("words", []))
        print(f"✅ User has {saved_count} saved words")

        # Check if they match test vocabulary
        if saved_count > 0:
            first_word = data["words"][0]
            print(f"   Sample word: {first_word.get('word')}")

def test_get_vocabulary_stats():
    """Test getting overall vocabulary statistics"""
    print("\n📋 Test 7: Get vocabulary statistics")

    response = requests.get(f"{API_BASE}/test-prep/stats", params={
        "language": "en"
    })

    assert response.status_code == 200, f"Failed: {response.text}"
    data = response.json()

    stats = data["statistics"]
    print(f"✅ Vocabulary statistics:")
    print(f"   Total unique words: {stats['total_unique_words']}")
    print(f"   TOEFL words: {stats['toefl_words']}")
    print(f"   IELTS words: {stats['ielts_words']}")
    print(f"   Words in both: {stats['words_in_both']}")

def test_disable_all_tests():
    """Test disabling all test preparation"""
    print("\n📋 Test 8: Disable all test preparation")

    response = requests.post(f"{API_BASE}/v3/users/{TEST_USER_ID}/preferences", json={
        "learning_language": "en",
        "native_language": "zh",
        "user_name": "Test User",
        "user_motto": "Learning",
        "test_prep": None,
        "study_duration_days": 30
    })

    assert response.status_code == 200, f"Failed: {response.text}"
    data = response.json()

    assert data.get("test_prep") is None
    print("✅ All test preparation disabled")

def test_cannot_add_when_disabled():
    """Test that words can't be added when tests are disabled"""
    print("\n📋 Test 9: Cannot add words when disabled")

    response = requests.post(f"{API_BASE}/test-prep/add-words", json={
        "user_id": TEST_USER_ID,
        "learning_language": "en",
        "native_language": "zh"
    })

    assert response.status_code == 400, f"Expected 400, got {response.status_code}"
    data = response.json()

    assert "error" in data
    assert "not enabled" in data["error"].lower()
    print("✅ Word addition blocked when disabled")

def run_all_tests():
    """Run all integration tests"""
    print("🚀 Starting Test Vocabulary Integration Tests")
    print("=" * 50)

    try:
        # Setup
        test_setup()

        # Run tests
        test_get_initial_settings()
        test_enable_toefl()
        test_add_daily_words()
        test_prevent_duplicate_daily_add()
        test_enable_both_tests()
        test_check_saved_words()
        test_get_vocabulary_stats()
        test_disable_all_tests()
        test_cannot_add_when_disabled()

        print("\n" + "=" * 50)
        print("✅ All tests passed successfully!")
        return True

    except AssertionError as e:
        print(f"\n❌ Test failed: {e}")
        return False
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        return False

if __name__ == "__main__":
    success = run_all_tests()
    exit(0 if success else 1)