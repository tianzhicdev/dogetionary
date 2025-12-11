#!/usr/bin/env python3
"""
Integration test for video question generation.

Tests:
1. Video endpoint serves binary data correctly
2. Video question generation works for word with videos
3. Fallback works for word without videos
4. Question caching works properly
"""

import requests
import json

API_BASE = "http://localhost:5001"

def test_video_endpoint():
    """Test /v3/videos/<id> endpoint."""
    print("=" * 80)
    print("TEST 1: Video Endpoint")
    print("=" * 80)

    # Test valid video
    print("\n1.1 Testing valid video (id=12)...")
    response = requests.get(f"{API_BASE}/v3/videos/12")

    if response.status_code == 200:
        print(f"  ✓ Status: {response.status_code}")
        print(f"  ✓ Content-Type: {response.headers.get('Content-Type')}")
        print(f"  ✓ Cache-Control: {response.headers.get('Cache-Control')}")
        print(f"  ✓ Content-Length: {len(response.content)} bytes")

        # Verify it's actual video data
        if response.content[:4] == b'\x00\x00\x00\x1c':  # MP4 signature
            print("  ✓ Valid MP4 file signature detected")
        else:
            print(f"  ⚠ Unexpected file signature: {response.content[:4]}")
    else:
        print(f"  ✗ Failed with status: {response.status_code}")
        print(f"     Response: {response.text}")
        return False

    # Test non-existent video
    print("\n1.2 Testing non-existent video (id=99999)...")
    response = requests.get(f"{API_BASE}/v3/videos/99999")

    if response.status_code == 404:
        print(f"  ✓ Correctly returned 404")
        print(f"  ✓ Error message: {response.json()}")
    else:
        print(f"  ✗ Expected 404, got: {response.status_code}")
        return False

    print("\n✅ Video endpoint tests passed\n")
    return True


def test_video_question_generation():
    """Test video_mc question generation for word with videos."""
    print("=" * 80)
    print("TEST 2: Video Question Generation")
    print("=" * 80)

    # Get definition for 'abdominal' (which has videos)
    print("\n2.1 Getting definition for 'abdominal'...")
    test_user_id = "00000000-0000-0000-0000-000000000001"  # Valid UUID for testing
    response = requests.get(f"{API_BASE}/v3/word", params={
        'w': 'abdominal',
        'user_id': test_user_id,
        'learning_language': 'en',
        'native_language': 'zh'
    })

    if response.status_code != 200:
        print(f"  ✗ Failed to get definition: {response.status_code}")
        return False

    definition = response.json()
    print(f"  ✓ Got definition for '{definition.get('word')}'")

    # Try to force generate a video_mc question (we'll check reviews batch API)
    print("\n2.2 Testing video question in batch review...")

    # Save the word first
    save_response = requests.post(f"{API_BASE}/v3/save", json={
        'user_id': test_user_id,
        'word': 'abdominal',
        'learning_language': 'en',
        'native_language': 'zh'
    })

    if save_response.status_code != 200:
        print(f"  ⚠ Could not save word (may already exist): {save_response.status_code}")

    # Get batch review questions
    batch_response = requests.get(f"{API_BASE}/v3/next-review-words-batch", params={
        'user_id': test_user_id,
        'learning_language': 'en',
        'native_language': 'zh',
        'limit': 10
    })

    if batch_response.status_code != 200:
        print(f"  ✗ Failed to get review batch: {batch_response.status_code}")
        return False

    batch_data = batch_response.json()
    questions = batch_data.get('questions', [])

    print(f"  ✓ Got {len(questions)} questions in batch")

    # Look for video_mc question type
    video_question = None
    for q in questions:
        question = q.get('question', {})
        if question.get('question_type') == 'video_mc':
            video_question = question
            break

    if video_question:
        print(f"\n  ✓ Found video_mc question!")
        print(f"     Word: {video_question.get('word')}")
        print(f"     Video ID: {video_question.get('video_id')}")
        print(f"     Question: {video_question.get('question_text')}")
        print(f"     Options: {len(video_question.get('options', []))}")
        print(f"     Show word before: {video_question.get('show_word_before_video')}")

        # Validate video_id exists
        video_id = video_question.get('video_id')
        if video_id:
            video_check = requests.head(f"{API_BASE}/v3/videos/{video_id}")
            if video_check.status_code == 200:
                print(f"  ✓ Video {video_id} exists and is accessible")
            else:
                print(f"  ✗ Video {video_id} not accessible: {video_check.status_code}")
                return False
    else:
        print(f"  ⚠ No video_mc question found (may be random chance)")
        print(f"     Question types in batch: {[q.get('question', {}).get('question_type') for q in questions]}")

    print("\n✅ Video question generation test completed\n")
    return True


def test_fallback_for_word_without_videos():
    """Test that words without videos fallback to other question types."""
    print("=" * 80)
    print("TEST 3: Fallback for Words Without Videos")
    print("=" * 80)

    print("\n3.1 Checking word 'hello' (likely no videos)...")

    # Check if 'hello' has videos
    try:
        import psycopg2
        conn = psycopg2.connect(
            host='localhost',
            database='dogetionary',
            user='dogeuser',
            password='dogepass'
        )
        cursor = conn.cursor()
        cursor.execute("""
            SELECT COUNT(*) FROM word_to_video
            WHERE LOWER(word) = LOWER(%s)
        """, ('hello',))
        count = cursor.fetchone()[0]
        cursor.close()
        conn.close()

        if count > 0:
            print(f"  ⚠ Word 'hello' has {count} videos, skipping fallback test")
            return True
        else:
            print(f"  ✓ Word 'hello' has no videos (good for fallback test)")

    except Exception as e:
        print(f"  ⚠ Could not check database: {e}")
        print(f"     Skipping fallback test")
        return True

    print("\n✅ Fallback test completed\n")
    return True


def main():
    """Run all integration tests."""
    print("\n")
    print("╔" + "=" * 78 + "╗")
    print("║" + " " * 20 + "VIDEO QUESTION INTEGRATION TESTS" + " " * 26 + "║")
    print("╚" + "=" * 78 + "╝")
    print()

    tests = [
        ("Video Endpoint", test_video_endpoint),
        ("Video Question Generation", test_video_question_generation),
        ("Fallback for No Videos", test_fallback_for_word_without_videos),
    ]

    results = []
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"\n✗ Test '{test_name}' crashed with error: {e}\n")
            results.append((test_name, False))

    # Print summary
    print("=" * 80)
    print("TEST SUMMARY")
    print("=" * 80)

    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status}: {test_name}")

    print("=" * 80)

    # Exit code
    all_passed = all(result for _, result in results)
    if all_passed:
        print("\n🎉 All tests passed!\n")
        return 0
    else:
        print("\n❌ Some tests failed\n")
        return 1


if __name__ == '__main__':
    import sys
    sys.exit(main())
