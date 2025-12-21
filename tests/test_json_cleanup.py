#!/usr/bin/env python3
"""
Test JSON cleanup function for handling LLM response formatting issues.
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from services.question_generation_service import clean_json_response
import json


def test_trailing_comma_in_array():
    """Test removing trailing comma in array"""
    input_json = '''
    {
      "options": [
        {"id": "A", "text": "First"},
        {"id": "B", "text": "Second"},
      ],
      "correct": "A"
    }
    '''

    cleaned = clean_json_response(input_json)
    data = json.loads(cleaned)  # Should not raise

    assert len(data["options"]) == 2
    assert data["correct"] == "A"
    print("✓ Test 1: Trailing comma in array")


def test_trailing_comma_in_object():
    """Test removing trailing comma in object"""
    input_json = '''
    {
      "question": "What is X?",
      "answer": "Y",
    }
    '''

    cleaned = clean_json_response(input_json)
    data = json.loads(cleaned)

    assert data["question"] == "What is X?"
    assert data["answer"] == "Y"
    print("✓ Test 2: Trailing comma in object")


def test_multiple_trailing_commas():
    """Test removing multiple trailing commas"""
    input_json = '''
    {
      "options": [
        {"id": "A", "text": "First",},
        {"id": "B", "text": "Second",},
      ],
      "correct": "A",
    }
    '''

    cleaned = clean_json_response(input_json)
    data = json.loads(cleaned)

    assert len(data["options"]) == 2
    print("✓ Test 3: Multiple trailing commas")


def test_actual_error_from_log():
    """Test the exact JSON from the error log"""
    input_json = '''
{
  "question_text": "What does 'regular' mean?",
  "options": [
    {"id": "A", "text": "Happening or done at the same time each day or week."},
    {"id": "B", "text": "Something that is very strange or unusual."},
    {"id": "C", "text": "Following a very complex set of rules."},
    {"id": "D", "text": "Done in a way that is not planned or expected."},
  ],
  "correct_answer": "A"
}
    '''

    cleaned = clean_json_response(input_json)
    data = json.loads(cleaned)  # Should not raise

    assert data["question_text"] == "What does 'regular' mean?"
    assert len(data["options"]) == 4
    assert data["correct_answer"] == "A"
    print("✓ Test 4: Actual error from production log")


def test_valid_json_unchanged():
    """Test that valid JSON is not modified"""
    input_json = '''
    {
      "question": "Test",
      "options": [
        {"id": "A", "text": "First"},
        {"id": "B", "text": "Second"}
      ]
    }
    '''

    cleaned = clean_json_response(input_json)
    data = json.loads(cleaned)

    assert len(data["options"]) == 2
    print("✓ Test 5: Valid JSON unchanged")


if __name__ == '__main__':
    print("\n" + "="*60)
    print("Testing JSON Cleanup Function")
    print("="*60 + "\n")

    try:
        test_trailing_comma_in_array()
        test_trailing_comma_in_object()
        test_multiple_trailing_commas()
        test_actual_error_from_log()
        test_valid_json_unchanged()

        print("\n" + "="*60)
        print("✅ All tests passed!")
        print("="*60 + "\n")

    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
