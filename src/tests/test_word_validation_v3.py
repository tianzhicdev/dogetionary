"""
Integration tests for V3 word validation endpoint
Tests word validation scores and suggestions
"""

import requests
import json

BASE_URL = "http://localhost:5000"
TEST_USER_ID = "550e8400-e29b-41d4-a716-446655440000"


def test_valid_word():
    """Test that a valid dictionary word gets high score"""
    response = requests.get(f"{BASE_URL}/v3/word", params={
        "w": "apple",
        "user_id": TEST_USER_ID,
        "learning_lang": "en",
        "native_lang": "zh"
    })

    assert response.status_code == 200
    data = response.json()

    print(f"\n✓ Valid word test (apple):")
    print(f"  Score: {data['definition_data']['valid_word_score']}")
    print(f"  Suggestion: {data['definition_data']['suggestion']}")

    assert data['definition_data']['valid_word_score'] >= 0.9, "Valid word should have score >= 0.9"
    assert data['definition_data']['suggestion'] is None, "Valid word should have no suggestion"
    assert 'definition_data' in data, "Should include definition"


def test_internet_slang():
    """Test that internet slang is recognized as valid"""
    response = requests.get(f"{BASE_URL}/v3/word", params={
        "w": "rizz",
        "user_id": TEST_USER_ID,
        "learning_lang": "en",
        "native_lang": "zh"
    })

    assert response.status_code == 200
    data = response.json()

    print(f"\n✓ Internet slang test (rizz):")
    print(f"  Score: {data['definition_data']['valid_word_score']}")
    print(f"  Suggestion: {data['definition_data']['suggestion']}")

    assert data['definition_data']['valid_word_score'] >= 0.9, "Internet slang should be valid"
    assert 'definition_data' in data


def test_brand_name():
    """Test that brand names are recognized as valid"""
    response = requests.get(f"{BASE_URL}/v3/word", params={
        "w": "iPhone",
        "user_id": TEST_USER_ID,
        "learning_lang": "en",
        "native_lang": "zh"
    })

    assert response.status_code == 200
    data = response.json()

    print(f"\n✓ Brand name test (iPhone):")
    print(f"  Score: {data['definition_data']['valid_word_score']}")
    print(f"  Suggestion: {data['definition_data']['suggestion']}")

    assert data['definition_data']['valid_word_score'] >= 0.9, "Brand names should be valid"


def test_common_phrase():
    """Test that common phrases are recognized as valid"""
    response = requests.get(f"{BASE_URL}/v3/word", params={
        "w": "sort of",
        "user_id": TEST_USER_ID,
        "learning_lang": "en",
        "native_lang": "zh"
    })

    assert response.status_code == 200
    data = response.json()

    print(f"\n✓ Common phrase test (sort of):")
    print(f"  Score: {data['definition_data']['valid_word_score']}")
    print(f"  Suggestion: {data['definition_data']['suggestion']}")

    assert data['definition_data']['valid_word_score'] >= 0.9, "Common phrases should be valid"


def test_misspelled_word():
    """Test that misspelled words get suggestions"""
    response = requests.get(f"{BASE_URL}/v3/word", params={
        "w": "definitly",
        "user_id": TEST_USER_ID,
        "learning_lang": "en",
        "native_lang": "zh"
    })

    assert response.status_code == 200
    data = response.json()

    print(f"\n✓ Misspelled word test (definitly):")
    print(f"  Score: {data['definition_data']['valid_word_score']}")
    print(f"  Suggestion: {data['definition_data']['suggestion']}")

    assert data['definition_data']['valid_word_score'] < 0.9, "Misspelled word should have low score"
    assert data['definition_data']['suggestion'] is not None, "Misspelled word should have suggestion"
    assert 'definition_data' in data, "Should still provide definition"


def test_typo_with_suggestion():
    """Test that typos get appropriate suggestions"""
    response = requests.get(f"{BASE_URL}/v3/word", params={
        "w": "appl",
        "user_id": TEST_USER_ID,
        "learning_lang": "en",
        "native_lang": "zh"
    })

    assert response.status_code == 200
    data = response.json()

    print(f"\n✓ Typo test (appl):")
    print(f"  Score: {data['definition_data']['valid_word_score']}")
    print(f"  Suggestion: {data['definition_data']['suggestion']}")

    assert data['definition_data']['valid_word_score'] < 0.9, "Typo should have low score"
    assert data['definition_data']['suggestion'] is not None, "Typo should have suggestion"


def test_gibberish():
    """Test that gibberish gets very low score"""
    response = requests.get(f"{BASE_URL}/v3/word", params={
        "w": "asdfgh",
        "user_id": TEST_USER_ID,
        "learning_lang": "en",
        "native_lang": "zh"
    })

    assert response.status_code == 200
    data = response.json()

    print(f"\n✓ Gibberish test (asdfgh):")
    print(f"  Score: {data['definition_data']['valid_word_score']}")
    print(f"  Suggestion: {data['definition_data']['suggestion']}")

    assert data['definition_data']['valid_word_score'] < 0.5, "Gibberish should have very low score"
    assert 'definition_data' in data, "Should still provide definition attempt"


def run_all_tests():
    """Run all validation tests"""
    print("=" * 60)
    print("V3 WORD VALIDATION INTEGRATION TESTS")
    print("=" * 60)

    tests = [
        ("Valid Word (apple)", test_valid_word),
        ("Internet Slang (rizz)", test_internet_slang),
        ("Brand Name (iPhone)", test_brand_name),
        ("Common Phrase (sort of)", test_common_phrase),
        ("Misspelled Word (definitly)", test_misspelled_word),
        ("Typo (appl)", test_typo_with_suggestion),
        ("Gibberish (asdfgh)", test_gibberish),
    ]

    passed = 0
    failed = 0

    for test_name, test_func in tests:
        try:
            test_func()
            passed += 1
            print(f"  ✅ PASSED\n")
        except AssertionError as e:
            failed += 1
            print(f"  ❌ FAILED: {e}\n")
        except Exception as e:
            failed += 1
            print(f"  ❌ ERROR: {e}\n")

    print("=" * 60)
    print(f"RESULTS: {passed} passed, {failed} failed")
    print("=" * 60)

    return failed == 0


if __name__ == "__main__":
    success = run_all_tests()
    exit(0 if success else 1)
