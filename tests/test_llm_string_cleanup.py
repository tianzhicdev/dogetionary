#!/usr/bin/env python3
"""
Unit tests for LLM JSON string cleanup functions.

Tests normalize_whitespace_string() and clean_json_strings() functions
from utils/llm.py to ensure all LLM responses have clean, normalized strings.
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from utils.llm import normalize_whitespace_string, clean_json_strings


# ============================================================================
# normalize_whitespace_string() Tests
# ============================================================================

def test_normalize_multiple_spaces():
    """Test collapsing multiple spaces to single space"""
    assert normalize_whitespace_string("a  b") == "a b"
    assert normalize_whitespace_string("a   b   c") == "a b c"
    assert normalize_whitespace_string("hello     world") == "hello world"
    print("✓ Test: Multiple spaces → single space")


def test_normalize_tabs():
    """Test converting tabs to single space"""
    assert normalize_whitespace_string("a\tb") == "a b"
    assert normalize_whitespace_string("a\t\tb") == "a b"
    assert normalize_whitespace_string("hello\tworld") == "hello world"
    print("✓ Test: Tabs → single space")


def test_normalize_newlines():
    """Test converting newlines to single space"""
    assert normalize_whitespace_string("a\nb") == "a b"
    assert normalize_whitespace_string("a\n\nb") == "a b"
    assert normalize_whitespace_string("a\rb") == "a b"
    assert normalize_whitespace_string("line1\nline2\nline3") == "line1 line2 line3"
    print("✓ Test: Newlines → single space")


def test_normalize_leading_trailing():
    """Test stripping leading and trailing whitespace"""
    assert normalize_whitespace_string("  a") == "a"
    assert normalize_whitespace_string("a  ") == "a"
    assert normalize_whitespace_string("  a  ") == "a"
    assert normalize_whitespace_string("\t\na\n\t") == "a"
    print("✓ Test: Leading/trailing whitespace removed")


def test_normalize_mixed_whitespace():
    """Test handling mixed whitespace types"""
    assert normalize_whitespace_string("  a\t\tb  \nc  ") == "a b c"
    assert normalize_whitespace_string("Hello.  World") == "Hello. World"
    assert normalize_whitespace_string("What  does   'hello'  mean?") == "What does 'hello' mean?"
    print("✓ Test: Mixed whitespace types normalized")


def test_normalize_already_clean():
    """Test that already clean strings are unchanged"""
    assert normalize_whitespace_string("hello world") == "hello world"
    assert normalize_whitespace_string("a b c") == "a b c"
    assert normalize_whitespace_string("Clean string.") == "Clean string."
    print("✓ Test: Already clean strings unchanged")


def test_normalize_empty_and_whitespace_only():
    """Test edge cases: empty string and whitespace-only strings"""
    assert normalize_whitespace_string("") == ""
    assert normalize_whitespace_string("   ") == ""
    assert normalize_whitespace_string("\t\n\r") == ""
    print("✓ Test: Empty and whitespace-only strings")


# ============================================================================
# clean_json_strings() Tests
# ============================================================================

def test_clean_simple_dict():
    """Test cleaning strings in a simple dict"""
    input_data = {"text": "a  b"}
    expected = {"text": "a b"}
    assert clean_json_strings(input_data) == expected
    print("✓ Test: Simple dict with messy string")


def test_clean_nested_dict():
    """Test cleaning strings in nested dicts"""
    input_data = {
        "question": "What  does   'hello'  mean?",
        "meta": {
            "analysis": "This  is   analysis"
        }
    }
    expected = {
        "question": "What does 'hello' mean?",
        "meta": {
            "analysis": "This is analysis"
        }
    }
    assert clean_json_strings(input_data) == expected
    print("✓ Test: Nested dicts with messy strings")


def test_clean_list():
    """Test cleaning strings in lists"""
    input_data = ["a  b", "c  d", "e  f"]
    expected = ["a b", "c d", "e f"]
    assert clean_json_strings(input_data) == expected
    print("✓ Test: List with messy strings")


def test_clean_dict_with_list():
    """Test cleaning strings in dict containing list"""
    input_data = {
        "options": [
            {"text": "Option   A  with  spaces"},
            {"text": "Option  B"}
        ]
    }
    expected = {
        "options": [
            {"text": "Option A with spaces"},
            {"text": "Option B"}
        ]
    }
    assert clean_json_strings(input_data) == expected
    print("✓ Test: Dict with list of dicts")


def test_clean_preserves_non_strings():
    """Test that non-string values are preserved unchanged"""
    input_data = {
        "text": "a  b",
        "number": 123,
        "float": 45.67,
        "bool_true": True,
        "bool_false": False,
        "null": None
    }
    expected = {
        "text": "a b",
        "number": 123,
        "float": 45.67,
        "bool_true": True,
        "bool_false": False,
        "null": None
    }
    result = clean_json_strings(input_data)
    assert result == expected
    # Additional type checks
    assert isinstance(result["number"], int)
    assert isinstance(result["float"], float)
    assert isinstance(result["bool_true"], bool)
    assert isinstance(result["bool_false"], bool)
    assert result["null"] is None
    print("✓ Test: Non-string values preserved")


def test_clean_real_question_format():
    """Test cleaning a realistic question response from LLM"""
    input_data = {
        "question_type": "MEANING_IN_CONTEXT",
        "analysis": "This  word   has  multiple  meanings",
        "question": "What  does   'fire'  mean  in  this  scene?",
        "options": [
            {"text": "Flames  and   heat", "correct": True},
            {"text": "To  terminate   employment", "correct": False}
        ],
        "explanation": "In  this  context,  'fire'  refers  to  flames."
    }
    expected = {
        "question_type": "MEANING_IN_CONTEXT",
        "analysis": "This word has multiple meanings",
        "question": "What does 'fire' mean in this scene?",
        "options": [
            {"text": "Flames and heat", "correct": True},
            {"text": "To terminate employment", "correct": False}
        ],
        "explanation": "In this context, 'fire' refers to flames."
    }
    assert clean_json_strings(input_data) == expected
    print("✓ Test: Real question format from LLM")


def test_clean_definition_format():
    """Test cleaning a realistic definition response from LLM"""
    input_data = {
        "word": "hello",
        "translations": ["你好", "您好"],
        "definitions": [
            {
                "part_of_speech": "interjection",
                "definition": "Used  as   a  greeting",
                "examples": [
                    "Hello,  how  are  you?",
                    "She  said   hello  to  me."
                ]
            }
        ],
        "comment": "Very  common   informal  greeting"
    }
    expected = {
        "word": "hello",
        "translations": ["你好", "您好"],
        "definitions": [
            {
                "part_of_speech": "interjection",
                "definition": "Used as a greeting",
                "examples": [
                    "Hello, how are you?",
                    "She said hello to me."
                ]
            }
        ],
        "comment": "Very common informal greeting"
    }
    assert clean_json_strings(input_data) == expected
    print("✓ Test: Real definition format from LLM")


def test_clean_deeply_nested():
    """Test cleaning deeply nested structures"""
    input_data = {
        "level1": {
            "level2": {
                "level3": {
                    "text": "a  b  c",
                    "items": ["x  y", "p  q"]
                }
            }
        }
    }
    expected = {
        "level1": {
            "level2": {
                "level3": {
                    "text": "a b c",
                    "items": ["x y", "p q"]
                }
            }
        }
    }
    assert clean_json_strings(input_data) == expected
    print("✓ Test: Deeply nested structures")


def test_clean_empty_structures():
    """Test cleaning empty dicts and lists"""
    assert clean_json_strings({}) == {}
    assert clean_json_strings([]) == []
    assert clean_json_strings({"empty": []}) == {"empty": []}
    assert clean_json_strings({"nested": {}}) == {"nested": {}}
    print("✓ Test: Empty structures")


# ============================================================================
# Run All Tests
# ============================================================================

if __name__ == '__main__':
    print("\n" + "="*70)
    print("TESTING LLM JSON STRING CLEANUP FUNCTIONS")
    print("="*70 + "\n")

    try:
        # normalize_whitespace_string() tests
        print("Testing normalize_whitespace_string():")
        print("-" * 70)
        test_normalize_multiple_spaces()
        test_normalize_tabs()
        test_normalize_newlines()
        test_normalize_leading_trailing()
        test_normalize_mixed_whitespace()
        test_normalize_already_clean()
        test_normalize_empty_and_whitespace_only()

        print()

        # clean_json_strings() tests
        print("Testing clean_json_strings():")
        print("-" * 70)
        test_clean_simple_dict()
        test_clean_nested_dict()
        test_clean_list()
        test_clean_dict_with_list()
        test_clean_preserves_non_strings()
        test_clean_real_question_format()
        test_clean_definition_format()
        test_clean_deeply_nested()
        test_clean_empty_structures()

        print("\n" + "="*70)
        print("✅ ALL TESTS PASSED!")
        print("="*70 + "\n")

    except AssertionError as e:
        print(f"\n❌ TEST FAILED!")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ UNEXPECTED ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
