#!/usr/bin/env python3
"""
Test script to verify schedule visibility logic.
Tests that has_schedule is True whenever a user has created a schedule,
regardless of whether they have tasks today.
"""

import requests
import uuid
from datetime import date, timedelta

BASE_URL = "http://localhost:5000"

def test_schedule_visibility():
    print("=" * 60)
    print("Testing Schedule Visibility Logic")
    print("=" * 60)

    # Create test user
    user_id = str(uuid.uuid4())
    print(f"\n1. Created test user: {user_id}")

    # Test 1: User with no schedule
    print("\n2. Testing user with NO schedule...")
    response = requests.get(f"{BASE_URL}/v3/schedule/today", params={"user_id": user_id})
    data = response.json()
    print(f"   Response: {data}")

    if data["has_schedule"] == False:
        print("   ✅ PASS: has_schedule is False (no schedule created)")
    else:
        print("   ❌ FAIL: has_schedule should be False")
        return False

    # Test 2: Create a schedule
    print("\n3. Creating schedule...")
    target_date = (date.today() + timedelta(days=60)).isoformat()
    schedule_response = requests.post(
        f"{BASE_URL}/v3/schedule/create",
        json={
            "user_id": user_id,
            "test_type": "TOEFL",
            "target_end_date": target_date
        }
    )

    if schedule_response.status_code == 200:
        print(f"   ✅ Schedule created successfully")
    else:
        print(f"   ❌ FAIL: Could not create schedule: {schedule_response.text}")
        return False

    # Test 3: Check schedule visibility - should be True now
    print("\n4. Testing user WITH schedule (tasks for today)...")
    response = requests.get(f"{BASE_URL}/v3/schedule/today", params={"user_id": user_id})
    data = response.json()
    print(f"   has_schedule: {data['has_schedule']}")
    print(f"   new_words count: {len(data.get('new_words', []))}")

    if data["has_schedule"] == True:
        print("   ✅ PASS: has_schedule is True (schedule exists with tasks)")
    else:
        print("   ❌ FAIL: has_schedule should be True")
        return False

    # Test 4: Remove all new words from today to simulate completed day
    print("\n5. Simulating all tasks completed for today...")
    # We'll use the next-review-word endpoint to deplete today's new words
    words_reviewed = 0
    max_reviews = 100  # Safety limit

    while words_reviewed < max_reviews:
        response = requests.get(
            f"{BASE_URL}/v3/next-review-word-with-scheduled-new-words",
            params={"user_id": user_id}
        )
        result = response.json()

        if result["count"] == 0:
            break

        # Check if it's a new word
        if result["saved_words"][0].get("is_new_word"):
            words_reviewed += 1
            if words_reviewed % 10 == 0:
                print(f"   Reviewed {words_reviewed} new words...")
        else:
            # No more new words
            break

    print(f"   Reviewed {words_reviewed} new words total")

    # Test 5: Check schedule visibility after completing all tasks
    print("\n6. Testing user WITH schedule (NO tasks remaining for today)...")
    response = requests.get(f"{BASE_URL}/v3/schedule/today", params={"user_id": user_id})
    data = response.json()
    print(f"   has_schedule: {data['has_schedule']}")
    print(f"   new_words count: {len(data.get('new_words', []))}")
    print(f"   message: {data.get('message')}")

    if data["has_schedule"] == True:
        print("   ✅ PASS: has_schedule is STILL True (schedule exists, even with no tasks)")
        print("   ✅ This means schedule tab will remain visible!")
    else:
        print("   ❌ FAIL: has_schedule should be True even when no tasks remain")
        return False

    print("\n" + "=" * 60)
    print("✅ ALL TESTS PASSED!")
    print("Schedule tab will persist as long as user has a schedule,")
    print("regardless of whether there are tasks for today.")
    print("=" * 60)
    return True

if __name__ == "__main__":
    success = test_schedule_visibility()
    exit(0 if success else 1)
