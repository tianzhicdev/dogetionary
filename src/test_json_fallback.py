#!/usr/bin/env python3
"""
Integration test for JSON validation fallback mechanism.

Tests that:
1. JSON validation happens inside llm_completion()
2. Invalid JSON triggers fallback to next model
3. Fallback chain logs show the retry behavior
4. Valid JSON from fallback model is returned successfully
"""

import sys
import os
import json
from unittest.mock import patch, Mock, MagicMock

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'src'))

def test_json_validation_in_llm_completion():
    """Test that JSON validation happens in llm_completion()"""
    print("\n=== Test 1: JSON Validation in llm_completion() ===\n")

    from utils.llm import llm_completion
    import openai

    # Mock OpenAI client to return invalid JSON
    mock_response = Mock()
    mock_response.choices = [Mock()]
    mock_response.choices[0].message.content = '{"invalid": "json",}'  # Trailing comma - invalid JSON
    mock_response.usage = Mock()
    mock_response.usage.prompt_tokens = 10
    mock_response.usage.completion_tokens = 20

    with patch('openai.OpenAI') as mock_client_class:
        mock_client = MagicMock()
        mock_client.chat.completions.create.return_value = mock_response
        mock_client_class.return_value = mock_client

        try:
            result = llm_completion(
                messages=[{"role": "user", "content": "test"}],
                model_name="gpt-4o-mini",
                use_case="test",
                response_format={"type": "json_object"}
            )
            print(f"❌ FAIL: Expected JSONDecodeError but got result: {result}")
            return False
        except json.JSONDecodeError as e:
            print(f"✅ PASS: JSON validation caught invalid JSON in llm_completion()")
            print(f"   Error: {e.msg} at line {e.lineno} column {e.colno}")
            return True


def test_fallback_on_json_error():
    """Test that fallback chain retries when JSON is invalid"""
    print("\n=== Test 2: Fallback Chain on JSON Error ===\n")

    from utils.llm import llm_completion_with_fallback
    import openai

    # Create mock responses
    # First model returns invalid JSON
    invalid_response = Mock()
    invalid_response.choices = [Mock()]
    invalid_response.choices[0].message.content = '{"invalid": "json",}'  # Trailing comma
    invalid_response.usage = Mock()
    invalid_response.usage.prompt_tokens = 10
    invalid_response.usage.completion_tokens = 20

    # Second model returns valid JSON
    valid_response = Mock()
    valid_response.choices = [Mock()]
    valid_response.choices[0].message.content = '{"valid": "json", "question": "test"}'
    valid_response.usage = Mock()
    valid_response.usage.prompt_tokens = 10
    valid_response.usage.completion_tokens = 20

    call_count = [0]

    def mock_create(**kwargs):
        call_count[0] += 1
        if call_count[0] == 1:
            print(f"   Call {call_count[0]}: Returning invalid JSON (will trigger fallback)")
            return invalid_response
        else:
            print(f"   Call {call_count[0]}: Returning valid JSON (fallback succeeds)")
            return valid_response

    with patch('openai.OpenAI') as mock_openai_class:
        # Mock OpenRouter client (used for question generation)
        mock_client = MagicMock()
        mock_client.chat.completions.create.side_effect = mock_create
        mock_openai_class.return_value = mock_client

        try:
            result = llm_completion_with_fallback(
                messages=[{"role": "user", "content": "Generate a question"}],
                use_case="question",
                response_format={"type": "json_object"}
            )

            if result is None:
                print(f"❌ FAIL: Fallback returned None (all models failed)")
                return False

            # Verify valid JSON was returned
            parsed = json.loads(result)
            if parsed.get("valid") == "json":
                print(f"✅ PASS: Fallback successfully returned valid JSON from second model")
                print(f"   Total API calls: {call_count[0]} (1st failed, 2nd succeeded)")
                return True
            else:
                print(f"❌ FAIL: Unexpected JSON content: {parsed}")
                return False

        except Exception as e:
            print(f"❌ FAIL: Unexpected exception: {type(e).__name__}: {e}")
            import traceback
            traceback.print_exc()
            return False


def test_all_models_fail_json_validation():
    """Test that None is returned when all models return invalid JSON"""
    print("\n=== Test 3: All Models Fail JSON Validation ===\n")

    from utils.llm import llm_completion_with_fallback
    import openai

    # All models return invalid JSON
    invalid_response = Mock()
    invalid_response.choices = [Mock()]
    invalid_response.choices[0].message.content = 'not valid json at all'
    invalid_response.usage = Mock()
    invalid_response.usage.prompt_tokens = 10
    invalid_response.usage.completion_tokens = 20

    call_count = [0]

    def mock_create(**kwargs):
        call_count[0] += 1
        print(f"   Call {call_count[0]}: Returning invalid JSON")
        return invalid_response

    with patch('openai.OpenAI') as mock_openai_class:
        mock_client = MagicMock()
        mock_client.chat.completions.create.side_effect = mock_create
        mock_openai_class.return_value = mock_client

        result = llm_completion_with_fallback(
            messages=[{"role": "user", "content": "test"}],
            use_case="question",
            response_format={"type": "json_object"}
        )

        if result is None:
            print(f"✅ PASS: Fallback correctly returned None after all models failed")
            print(f"   Total API calls: {call_count[0]} (tried all models in fallback chain)")
            return True
        else:
            print(f"❌ FAIL: Expected None but got: {result}")
            return False


def test_valid_json_no_fallback():
    """Test that fallback doesn't trigger when first model returns valid JSON"""
    print("\n=== Test 4: Valid JSON (No Fallback Needed) ===\n")

    from utils.llm import llm_completion_with_fallback
    import openai

    valid_response = Mock()
    valid_response.choices = [Mock()]
    valid_response.choices[0].message.content = '{"valid": "json", "status": "success"}'
    valid_response.usage = Mock()
    valid_response.usage.prompt_tokens = 10
    valid_response.usage.completion_tokens = 20

    call_count = [0]

    def mock_create(**kwargs):
        call_count[0] += 1
        print(f"   Call {call_count[0]}: Returning valid JSON")
        return valid_response

    with patch('openai.OpenAI') as mock_openai_class:
        mock_client = MagicMock()
        mock_client.chat.completions.create.side_effect = mock_create
        mock_openai_class.return_value = mock_client

        result = llm_completion_with_fallback(
            messages=[{"role": "user", "content": "test"}],
            use_case="question",
            response_format={"type": "json_object"}
        )

        if result and call_count[0] == 1:
            parsed = json.loads(result)
            if parsed.get("status") == "success":
                print(f"✅ PASS: First model returned valid JSON, no fallback triggered")
                print(f"   Total API calls: {call_count[0]} (only primary model)")
                return True

        print(f"❌ FAIL: Unexpected behavior. Call count: {call_count[0]}, Result: {result}")
        return False


if __name__ == "__main__":
    print("\n" + "="*70)
    print("JSON VALIDATION FALLBACK MECHANISM TEST")
    print("="*70)

    # Run all tests
    test1 = test_json_validation_in_llm_completion()
    test2 = test_fallback_on_json_error()
    test3 = test_all_models_fail_json_validation()
    test4 = test_valid_json_no_fallback()

    # Summary
    print("\n" + "="*70)
    print("TEST SUMMARY")
    print("="*70)
    tests = [
        ("JSON validation in llm_completion()", test1),
        ("Fallback on JSON error", test2),
        ("All models fail validation", test3),
        ("Valid JSON (no fallback)", test4),
    ]

    for name, passed in tests:
        status = "✅ PASSED" if passed else "❌ FAILED"
        print(f"{status}: {name}")

    all_passed = all(result for _, result in tests)
    if all_passed:
        print("\n🎉 ALL TESTS PASSED!")
        sys.exit(0)
    else:
        print("\n❌ SOME TESTS FAILED")
        sys.exit(1)
