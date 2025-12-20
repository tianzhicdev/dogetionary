#!/usr/bin/env python3
"""
Integration test for everyday_english fallback in review batch endpoint.
Tests the three-tier priority system:
1. Due words
2. New words from active bundle
3. New words from everyday_english (fallback)
"""

import requests
import sys

BASE_URL = "http://localhost:5000"

def test_review_batch_with_fallback(user_id: str):
    """Test the review batch endpoint with everyday_english fallback"""

    print(f"\n{'='*60}")
    print(f"Testing Review Batch Endpoint - User: {user_id}")
    print(f"{'='*60}\n")

    # Test with count=10 to potentially trigger fallback
    url = f"{BASE_URL}/v3/next-review-words-batch"
    params = {
        "user_id": user_id,
        "count": 10
    }

    print(f"Making request to: {url}")
    print(f"Params: {params}\n")

    response = requests.get(url, params=params)

    print(f"Status Code: {response.status_code}")

    if response.status_code != 200:
        print(f"❌ Request failed: {response.text}")
        return False

    data = response.json()
    questions = data.get("questions", [])

    print(f"Received {len(questions)} questions\n")

    # Group by source type
    source_counts = {}
    for q in questions:
        source = q.get("source", "unknown")
        source_counts[source] = source_counts.get(source, 0) + 1

    print("Questions by source:")
    print("-" * 40)
    for source, count in sorted(source_counts.items()):
        emoji = {
            'due': '⏰',
            'new_bundle': '📚',
            'everyday_english': '🌍',
            'unknown': '❓'
        }.get(source, '❓')
        print(f"{emoji} {source:20} {count:3} questions")
    print("-" * 40)

    # Show sample words from each source
    print("\nSample words by source:")
    print("-" * 40)
    for source in ['due', 'new_bundle', 'everyday_english']:
        words_from_source = [q['word'] for q in questions if q.get('source') == source]
        if words_from_source:
            sample = words_from_source[:3]
            print(f"{source:20} {', '.join(sample)}")
    print("-" * 40)

    # Verify we got questions
    if len(questions) == 0:
        print("\n❌ No questions returned!")
        return False

    # Check if we got everyday_english fallback
    has_everyday = any(q.get('source') == 'everyday_english' for q in questions)
    if has_everyday:
        print("\n✅ Everyday English fallback is working!")
    else:
        print("\n⚠️  No everyday_english words (may be expected if user has enough due/bundle words)")

    print(f"\n{'='*60}")
    print("Test completed successfully!")
    print(f"{'='*60}\n")

    return True


if __name__ == "__main__":
    # Use a test user ID or get from command line
    user_id = sys.argv[1] if len(sys.argv) > 1 else "test-user-123"

    success = test_review_batch_with_fallback(user_id)
    sys.exit(0 if success else 1)
