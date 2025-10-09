#!/usr/bin/env python3
"""
Integration tests for word prepopulation features

Tests:
1. GET /v3/<learning_lang>/<native_lang>/all_words endpoint
2. /v3/word with generateImage=false parameter
3. /v3/word with generateImage=true parameter (smart image generation)
"""

import requests
import sys

BASE_URL = "http://localhost:5000"


def test_all_words_endpoint():
    """Test the all_words endpoint returns a list of words"""
    print("📝 Test 1: GET /v3/en/zh/all_words endpoint")

    response = requests.get(f"{BASE_URL}/v3/en/zh/all_words")

    if response.status_code != 200:
        print(f"  ❌ Failed: HTTP {response.status_code}")
        return False

    data = response.json()

    if not isinstance(data, list):
        print(f"  ❌ Failed: Expected list, got {type(data)}")
        return False

    print(f"  ✅ Passed: Returned {len(data)} words")
    return True


def test_generate_image_false():
    """Test that generateImage=false doesn't generate images"""
    print("\n📝 Test 2: /v3/word with generateImage=false")

    # First, create a test word without image
    params = {
        'w': 'testword123',
        'user_id': '00000000-0000-0000-0000-000000000000',
        'learning_lang': 'en',
        'native_lang': 'zh',
        'generateImage': 'false'
    }

    response = requests.get(f"{BASE_URL}/v3/word", params=params, timeout=60)

    if response.status_code != 200:
        print(f"  ❌ Failed: HTTP {response.status_code}")
        return False

    data = response.json()

    if 'image_status' not in data:
        print(f"  ❌ Failed: No image_status in response")
        return False

    image_status = data['image_status']

    if image_status.get('has_image', False):
        print(f"  ❌ Failed: Image was generated when generateImage=false")
        return False

    print(f"  ✅ Passed: No image generated (image_status={image_status})")
    return True


def test_generate_image_true():
    """Test that generateImage=true generates missing images"""
    print("\n📝 Test 3: /v3/word with generateImage=true (smart generation)")

    # Use the word from previous test (has definition but no image)
    params = {
        'w': 'testword123',
        'user_id': '00000000-0000-0000-0000-000000000000',
        'learning_lang': 'en',
        'native_lang': 'zh',
        'generateImage': 'true'
    }

    response = requests.get(f"{BASE_URL}/v3/word", params=params, timeout=120)

    if response.status_code != 200:
        print(f"  ❌ Failed: HTTP {response.status_code}")
        return False

    data = response.json()

    if 'image_status' not in data:
        print(f"  ❌ Failed: No image_status in response")
        return False

    image_status = data['image_status']

    if not image_status.get('has_image', False):
        print(f"  ❌ Failed: Image was not generated")
        return False

    if not image_status.get('generated_now', False):
        print(f"  ⚠️  Warning: Image exists but wasn't generated now (might be cached)")

    print(f"  ✅ Passed: Image generated (image_status={image_status})")

    # Test again to verify it doesn't regenerate
    print("\n📝 Test 3b: Verify image is cached on second request")

    response2 = requests.get(f"{BASE_URL}/v3/word", params=params, timeout=60)
    data2 = response2.json()
    image_status2 = data2['image_status']

    if image_status2.get('generated_now', False):
        print(f"  ❌ Failed: Image was regenerated when it should be cached")
        return False

    if not image_status2.get('has_image', False):
        print(f"  ❌ Failed: Cached image not found")
        return False

    print(f"  ✅ Passed: Image cached (image_status={image_status2})")
    return True


def main():
    print("=" * 60)
    print("🧪 Dogetionary Prepopulation Integration Tests")
    print("=" * 60)

    # Check if server is running
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=5)
        if response.status_code != 200:
            print(f"❌ Server not healthy at {BASE_URL}")
            sys.exit(1)
    except Exception as e:
        print(f"❌ Cannot connect to server at {BASE_URL}: {e}")
        sys.exit(1)

    print(f"✅ Server is running at {BASE_URL}\n")

    # Run tests
    results = []
    results.append(("all_words endpoint", test_all_words_endpoint()))
    results.append(("generateImage=false", test_generate_image_false()))
    results.append(("generateImage=true (smart)", test_generate_image_true()))

    # Summary
    print("\n" + "=" * 60)
    print("📊 Test Summary")
    print("=" * 60)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status}: {name}")

    print("=" * 60)
    print(f"Results: {passed}/{total} tests passed")

    if passed == total:
        print("✨ All tests passed!")
        sys.exit(0)
    else:
        print(f"❌ {total - passed} test(s) failed")
        sys.exit(1)


if __name__ == '__main__':
    main()
