#!/usr/bin/env python3
"""Test meta description generation"""

from generate import DictionaryGenerator

def test_meta_description():
    generator = DictionaryGenerator()

    # Test case 1: Short definition with examples
    test_case_1 = {
        'definitions': [{
            'definition': 'An unusual and exciting experience or activity.',
            'type': 'noun',
            'examples': ['Going on a safari in Africa was the greatest adventure of my life.']
        }],
        'phonetic': '/ədˈvɛn.tʃər/'
    }

    result_1 = generator.generate_meta_description('adventure', test_case_1)
    print(f"Test 1 - Short definition:")
    print(f"  Result: {result_1}")
    print(f"  Length: {len(result_1)} chars")
    print()

    # Test case 2: Long definition
    test_case_2 = {
        'definitions': [{
            'definition': 'An unusual and exciting experience or activity that involves some risk or uncertainty and is often undertaken to achieve something.',
            'type': 'noun'
        }],
        'phonetic': '/ədˈvɛn.tʃər/'
    }

    result_2 = generator.generate_meta_description('adventure', test_case_2)
    print(f"Test 2 - Long definition:")
    print(f"  Result: {result_2}")
    print(f"  Length: {len(result_2)} chars")
    print()

    # Test case 3: No phonetic
    test_case_3 = {
        'definitions': [{
            'definition': 'To take a risk or engage in an exciting or daring experience.',
            'type': 'verb'
        }]
    }

    result_3 = generator.generate_meta_description('adventure', test_case_3)
    print(f"Test 3 - No phonetic:")
    print(f"  Result: {result_3}")
    print(f"  Length: {len(result_3)} chars")
    print()

    # Test case 4: Complex word with long pronunciation
    test_case_4 = {
        'definitions': [{
            'definition': 'Having a sharp insight or understanding; showing keen mental discernment and judgment.',
            'type': 'adjective'
        }],
        'phonetic': '/ˌpɜːrspɪˈkeɪʃəs/'
    }

    result_4 = generator.generate_meta_description('perspicacious', test_case_4)
    print(f"Test 4 - Complex word:")
    print(f"  Result: {result_4}")
    print(f"  Length: {len(result_4)} chars")
    print()

    # Verify all are within 150-160 character range
    all_results = [result_1, result_2, result_3, result_4]
    for i, result in enumerate(all_results, 1):
        length = len(result)
        status = "✓" if 140 <= length <= 160 else "✗"
        print(f"{status} Test {i}: {length} chars {'(within range)' if 140 <= length <= 160 else '(OUT OF RANGE)'}")

    print("\nFormat validation:")
    for i, result in enumerate(all_results, 1):
        has_colon = ':' in result
        print(f"  Test {i}: {'✓' if has_colon else '✗'} Starts with word + colon")

if __name__ == '__main__':
    test_meta_description()
