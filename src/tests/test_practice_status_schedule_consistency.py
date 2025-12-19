"""
Integration test to verify practice status and schedule endpoints return consistent results.

This test addresses the bug where:
- Schedule endpoint returned many new words for today
- Practice status endpoint returned 0 for all counts

Root cause: practice_status.py checked `test_type` (which was None) instead of `test_prep_enabled`.
"""

import requests
import json
from datetime import date, timedelta

BASE_URL = "http://localhost:5000"


def test_practice_status_schedule_consistency():
    """
    Test that practice status and schedule endpoints are consistent.

    When user has:
    - test prep enabled (e.g., business_english_enabled=true)
    - target_end_date in the future
    - new words scheduled for today

    Then both endpoints should show the new words.
    """

    # Use a test user ID
    user_id = "C5AC37AC-DC1A-4947-96DC-BE9DAC7CA8AD"

    print(f"\n{'='*60}")
    print(f"Testing practice status and schedule consistency")
    print(f"User ID: {user_id}")
    print(f"{'='*60}\n")

    # Get practice status
    practice_status_response = requests.get(
        f"{BASE_URL}/v3/practice-status",
        params={"user_id": user_id}
    )

    print(f"Practice Status Response ({practice_status_response.status_code}):")
    practice_data = practice_status_response.json()
    print(json.dumps(practice_data, indent=2))

    # Get today's schedule
    schedule_response = requests.get(
        f"{BASE_URL}/v3/schedule/today",
        params={"user_id": user_id}
    )

    print(f"\nSchedule Response ({schedule_response.status_code}):")
    schedule_data = schedule_response.json()

    # Print summary instead of full response (could be large)
    schedule_summary = {
        "date": schedule_data.get("date"),
        "user_has_schedule": schedule_data.get("user_has_schedule"),
        "has_schedule": schedule_data.get("has_schedule"),
        "test_type": schedule_data.get("test_type"),
        "summary": schedule_data.get("summary"),
        "new_words_count": len(schedule_data.get("new_words", [])),
        "test_practice_count": len(schedule_data.get("test_practice_words", [])),
        "non_test_practice_count": len(schedule_data.get("non_test_practice_words", []))
    }
    print(json.dumps(schedule_summary, indent=2))

    # Verify consistency
    print(f"\n{'='*60}")
    print("Consistency Check:")
    print(f"{'='*60}")

    # Extract counts
    practice_new = practice_data.get("new_words_count", 0)
    practice_test = practice_data.get("test_practice_count", 0)
    practice_non_test = practice_data.get("non_test_practice_count", 0)

    schedule_new = schedule_summary["new_words_count"]
    schedule_test = schedule_summary["test_practice_count"]
    schedule_non_test = schedule_summary["non_test_practice_count"]

    print(f"New words:         Practice={practice_new:3d}  Schedule={schedule_new:3d}  Match: {practice_new == schedule_new}")
    print(f"Test practice:     Practice={practice_test:3d}  Schedule={schedule_test:3d}  Match: {practice_test == schedule_test}")
    print(f"Non-test practice: Practice={practice_non_test:3d}  Schedule={schedule_non_test:3d}  Match: {practice_non_test == schedule_non_test}")

    # Check if user has schedule configured
    if not schedule_data.get("user_has_schedule"):
        print("\n⚠️  User does not have schedule configured (test prep disabled or no target_end_date)")
        print("✅ PASS: Both endpoints should return 0 when no schedule is configured")
        assert practice_new == 0 and schedule_new == 0, "Both should return 0 new words when no schedule"
        return

    # If user has schedule, counts should match
    if schedule_data.get("has_schedule"):
        print(f"\n✅ User has schedule configured with tasks for today")

        # Counts should match between endpoints
        assert practice_new == schedule_new, \
            f"New words count mismatch: practice={practice_new}, schedule={schedule_new}"
        assert practice_test == schedule_test, \
            f"Test practice count mismatch: practice={practice_test}, schedule={schedule_test}"
        assert practice_non_test == schedule_non_test, \
            f"Non-test practice count mismatch: practice={practice_non_test}, schedule={schedule_non_test}"

        print("✅ PASS: All counts match between practice status and schedule endpoints")
    else:
        print(f"\n⚠️  User has schedule configured but no tasks for today")
        print("✅ PASS: Both endpoints should return 0 for today")
        assert practice_new == 0 and schedule_new == 0, "Both should return 0 when no tasks today"


if __name__ == "__main__":
    try:
        test_practice_status_schedule_consistency()
        print(f"\n{'='*60}")
        print("✅ TEST PASSED")
        print(f"{'='*60}\n")
    except AssertionError as e:
        print(f"\n{'='*60}")
        print(f"❌ TEST FAILED: {e}")
        print(f"{'='*60}\n")
        raise
    except Exception as e:
        print(f"\n{'='*60}")
        print(f"❌ TEST ERROR: {e}")
        print(f"{'='*60}\n")
        raise
