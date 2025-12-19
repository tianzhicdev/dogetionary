#!/usr/bin/env python3
"""
Test script to verify enhanced LLM logging works correctly.
Tests both successful and failed JSON parsing scenarios.
"""

import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'src'))

from app import create_app
import logging

# Create Flask app context
app = create_app()

def test_question_generation():
    """Test question generation to verify logging"""
    with app.app_context():
        from services.question_generation_service import generate_question_with_llm

        print("\n=== Testing LLM Question Generation Logging ===\n")

        # Test with a simple word
        word = "test"
        definition = {
            "word": "test",
            "definition": "A procedure for critical evaluation; a means of determining the presence, quality, or truth of something.",
            "part_of_speech": "noun",
            "examples": [
                "The teacher gave us a test on vocabulary.",
                "This is a test of the new system."
            ]
        }
        learning_lang = "en"
        native_lang = "zh"
        question_type = "mc_definition"

        try:
            print(f"Generating question for word: '{word}'")
            print(f"Question type: {question_type}")
            print(f"Languages: {learning_lang} → {native_lang}\n")

            question = generate_question_with_llm(
                word=word,
                definition=definition,
                learning_lang=learning_lang,
                native_lang=native_lang,
                question_type=question_type
            )

            print("\n✅ SUCCESS: Question generated successfully")
            print(f"Question: {question.get('question', 'N/A')}")
            print(f"Correct answer: {question.get('correct_answer', 'N/A')}")
            print(f"Number of options: {len(question.get('options', []))}")

            return True

        except Exception as e:
            print(f"\n❌ FAILED: {type(e).__name__}: {e}")
            import traceback
            traceback.print_exc()
            return False


def check_logging_configuration():
    """Verify logging configuration"""
    with app.app_context():
        print("\n=== Checking Logging Configuration ===\n")

        # Check utils.llm logger
        llm_logger = logging.getLogger('utils.llm')
        print(f"utils.llm logger:")
        print(f"  Level: {logging.getLevelName(llm_logger.getEffectiveLevel())}")
        print(f"  Handlers: {len(llm_logger.handlers)}")

        # Check question generation logger
        qg_logger = logging.getLogger('services.question_generation_service')
        print(f"\nservices.question_generation_service logger:")
        print(f"  Level: {logging.getLevelName(qg_logger.getEffectiveLevel())}")
        print(f"  Handlers: {len(qg_logger.handlers)}")

        # Test a log message
        print("\nTesting log message...")
        llm_logger.info("TEST: LLM logger is working")
        qg_logger.info("TEST: Question generation logger is working")
        print("✓ Log messages sent (check console/file output)")


if __name__ == "__main__":
    print("\n" + "="*60)
    print("LLM LOGGING TEST")
    print("="*60)

    # Check environment variables
    print("\nChecking environment variables...")
    has_openrouter = bool(os.getenv("OPEN_ROUTER_KEY"))
    has_openai = bool(os.getenv("OPENAI_API_KEY"))

    print(f"  OPEN_ROUTER_KEY: {'✓ Set' if has_openrouter else '✗ Not set'}")
    print(f"  OPENAI_API_KEY: {'✓ Set' if has_openai else '✗ Not set'}")

    if not has_openrouter and not has_openai:
        print("\n⚠️  Warning: No API keys found. LLM calls will fail.")
        print("   Set OPEN_ROUTER_KEY or OPENAI_API_KEY to test actual LLM calls.")

    # Check logging configuration
    check_logging_configuration()

    # Run test
    success = test_question_generation()

    # Summary
    print("\n" + "="*60)
    print("TEST SUMMARY")
    print("="*60)
    print(f"Result: {'✅ PASSED' if success else '❌ FAILED'}")

    # Instructions for checking logs
    print("\n" + "="*60)
    print("HOW TO VERIFY LOGGING")
    print("="*60)
    print("\n1. Check console output above for:")
    print("   - 'Starting fallback chain for use_case=question'")
    print("   - 'Attempting model X/Y: [model_name]'")
    print("   - 'LLM response received: provider=...'")
    print("   - 'LLM returned content for question generation'")
    print("\n2. Check /app/logs/app.log for JSON-formatted logs")
    print("\n3. Query Grafana/Loki with:")
    print('   {app="dogetionary", logger="utils.llm"} |= "question"')
    print('   {app="dogetionary", logger="services.question_generation_service"}')

    sys.exit(0 if success else 1)
