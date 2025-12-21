#!/usr/bin/env python3
"""
Standalone test for JSON cleanup function.
No dependencies on other modules.
"""

import json
import re


def clean_json_response(json_str: str) -> str:
    """
    Clean up common JSON formatting issues from LLM responses.

    Fixes:
    - Trailing commas in arrays/objects (e.g., [1, 2, 3,])
    - Leading/trailing whitespace
    """
    # Remove trailing commas before closing brackets/braces
    json_str = re.sub(r',\s*([}\]])', r'\1', json_str)
    return json_str.strip()


def test_actual_error_from_log():
    """Test the exact JSON from the production error"""
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

    print("Original JSON:")
    print(input_json)
    print("\n" + "="*60 + "\n")

    cleaned = clean_json_response(input_json)
    print("Cleaned JSON:")
    print(cleaned)
    print("\n" + "="*60 + "\n")

    # This should not raise JSONDecodeError
    data = json.loads(cleaned)

    assert data["question_text"] == "What does 'regular' mean?"
    assert len(data["options"]) == 4
    assert data["correct_answer"] == "A"
    assert data["options"][3]["id"] == "D"

    print("✅ Successfully parsed! No JSONDecodeError")
    print(f"   Question: {data['question_text']}")
    print(f"   Options: {len(data['options'])}")
    print(f"   Correct: {data['correct_answer']}")


if __name__ == '__main__':
    print("\n" + "="*60)
    print("Testing JSON Cleanup for Production Error")
    print("="*60 + "\n")

    try:
        test_actual_error_from_log()
        print("\n" + "="*60)
        print("✅ Test passed! Fix will work in production.")
        print("="*60 + "\n")
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
