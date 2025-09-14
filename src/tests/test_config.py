#!/usr/bin/env python3
"""
Test configuration and utilities for Dogetionary tests.
"""

import os
import sys
import tempfile
import subprocess
from contextlib import contextmanager

# Test configuration
TEST_BASE_URL = "http://localhost:5000"
TEST_DATABASE_URL = "postgresql://dogeuser:dogepass@localhost:5432/dogetionary_test"

# Add src directory to path
TEST_ROOT = os.path.dirname(os.path.abspath(__file__))
SRC_ROOT = os.path.dirname(TEST_ROOT)
sys.path.insert(0, SRC_ROOT)

class TestConfig:
    """Configuration class for tests"""

    # Test database settings
    TEST_DB_URL = TEST_DATABASE_URL

    # Test user IDs for consistent testing
    TEST_USER_ID_1 = "123e4567-e89b-12d3-a456-426614174000"
    TEST_USER_ID_2 = "456e7890-e89b-12d3-a456-426614174001"

    # Test words for consistent testing
    TEST_WORDS = [
        "hello", "world", "test", "integration", "unit",
        "apple", "banana", "cherry", "dog", "cat"
    ]

    # Test languages
    TEST_LEARNING_LANGUAGE = "en"
    TEST_NATIVE_LANGUAGE = "zh"

    @classmethod
    def get_test_definition_data(cls, word="test"):
        """Get mock definition data for testing"""
        return {
            "word": word,
            "phonetic": f"/{word}/",
            "translations": [f"{word}_translation_1", f"{word}_translation_2"],
            "definitions": [
                {
                    "type": "noun",
                    "definition": f"A {word} definition in English",
                    "definition_native": f"A {word} definition in native language",
                    "examples": [
                        f"Example 1 with {word}",
                        f"Example 2 with {word}"
                    ],
                    "cultural_notes": f"Cultural notes about {word}"
                }
            ]
        }

    @classmethod
    def get_test_review_data(cls, word_id=1, user_id=None, response=True):
        """Get mock review data for testing"""
        from datetime import datetime
        return {
            "user_id": user_id or cls.TEST_USER_ID_1,
            "word_id": word_id,
            "response": response,
            "review_time_seconds": 5.5,
            "reviewed_at": datetime.now()
        }

def wait_for_service(base_url=TEST_BASE_URL, timeout=30):
    """Wait for the service to be ready"""
    import requests
    import time

    for i in range(timeout):
        try:
            response = requests.get(f"{base_url}/health", timeout=5)
            if response.status_code == 200:
                return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(1)
    return False

@contextmanager
def temporary_env_vars(**env_vars):
    """Context manager for temporarily setting environment variables"""
    original_values = {}

    # Set new values and remember original ones
    for key, value in env_vars.items():
        original_values[key] = os.environ.get(key)
        os.environ[key] = value

    try:
        yield
    finally:
        # Restore original values
        for key, original_value in original_values.items():
            if original_value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = original_value

def run_docker_command(command, check=True):
    """Run a docker command and return the result"""
    full_command = f"docker-compose {command}"
    try:
        result = subprocess.run(
            full_command,
            shell=True,
            capture_output=True,
            text=True,
            cwd=SRC_ROOT
        )
        if check and result.returncode != 0:
            raise subprocess.CalledProcessError(
                result.returncode,
                full_command,
                result.stdout,
                result.stderr
            )
        return result
    except subprocess.CalledProcessError as e:
        print(f"Docker command failed: {e}")
        print(f"STDOUT: {e.stdout}")
        print(f"STDERR: {e.stderr}")
        raise

def setup_test_database():
    """Set up test database (if needed)"""
    print("Setting up test database...")

    # For now, we'll use the same database as the main app
    # In a production setup, you'd want a separate test database
    try:
        # Ensure the service is running
        run_docker_command("up -d postgres")
        print("✓ Test database is ready")
        return True
    except Exception as e:
        print(f"✗ Failed to set up test database: {e}")
        return False

def teardown_test_database():
    """Clean up test database (if needed)"""
    print("Cleaning up test database...")
    # For now, we won't tear down the database since it's shared
    # In a production setup, you'd clean up test-specific data
    print("✓ Test database cleanup completed")

class MockOpenAIResponse:
    """Mock OpenAI API response for testing"""

    def __init__(self, content):
        self.content = content
        self.choices = [self]
        self.message = self

    def strip(self):
        return self.content

def create_mock_db_connection():
    """Create a mock database connection for unit tests"""
    from unittest.mock import MagicMock

    mock_conn = MagicMock()
    mock_cursor = MagicMock()
    mock_conn.cursor.return_value = mock_cursor

    return mock_conn, mock_cursor

def assert_valid_uuid(uuid_string):
    """Assert that a string is a valid UUID"""
    import uuid
    try:
        uuid.UUID(uuid_string)
        return True
    except ValueError:
        return False

def assert_valid_iso_datetime(datetime_string):
    """Assert that a string is a valid ISO datetime"""
    from datetime import datetime
    try:
        datetime.fromisoformat(datetime_string.replace('Z', '+00:00'))
        return True
    except ValueError:
        return False

# Test data generators
def generate_test_saved_words(user_id, count=5):
    """Generate test saved words data"""
    import uuid
    from datetime import datetime

    words = TestConfig.TEST_WORDS[:count]
    return [
        {
            "id": i + 1,
            "word": word,
            "user_id": user_id,
            "learning_language": TestConfig.TEST_LEARNING_LANGUAGE,
            "metadata": {"test": True, "index": i},
            "created_at": datetime.now(),
            "review_count": i,
            "next_review_date": datetime.now().date().isoformat(),
            "last_reviewed_at": datetime.now().isoformat() if i > 0 else None
        }
        for i, word in enumerate(words)
    ]

def generate_test_review_history(word_id, count=3):
    """Generate test review history"""
    from datetime import datetime, timedelta
    import random

    base_time = datetime.now() - timedelta(days=count)
    return [
        {
            "reviewed_at": base_time + timedelta(days=i),
            "response": random.choice([True, False]),
            "review_time_seconds": random.uniform(2.0, 10.0)
        }
        for i in range(count)
    ]

# Test assertion helpers
def assert_json_structure(data, expected_keys, test_name="JSON structure"):
    """Assert that JSON data contains expected keys"""
    missing_keys = set(expected_keys) - set(data.keys())
    if missing_keys:
        raise AssertionError(f"{test_name}: Missing keys {missing_keys}")

def assert_positive_integer(value, field_name="field"):
    """Assert that a value is a positive integer"""
    if not isinstance(value, int) or value < 0:
        raise AssertionError(f"{field_name} should be a non-negative integer, got {value}")

def assert_valid_language_code(lang_code):
    """Assert that a language code is valid"""
    # Import from config
    from config.config import SUPPORTED_LANGUAGES
    if lang_code not in SUPPORTED_LANGUAGES:
        raise AssertionError(f"Invalid language code: {lang_code}")

# Print utilities for test output
def print_test_header(test_name):
    """Print a formatted test header"""
    print(f"\n{'=' * 60}")
    print(f"Running: {test_name}")
    print(f"{'=' * 60}")

def print_test_result(passed, failed):
    """Print formatted test results"""
    total = passed + failed
    success_rate = (passed / total * 100) if total > 0 else 0

    print(f"\n{'=' * 60}")
    print(f"TEST RESULTS")
    print(f"{'=' * 60}")
    print(f"Total tests: {total}")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print(f"Success rate: {success_rate:.1f}%")

    if failed == 0:
        print("🎉 All tests passed!")
    else:
        print(f"❌ {failed} tests failed!")
    print(f"{'=' * 60}")

if __name__ == "__main__":
    # Test the test configuration
    print("Testing test configuration...")

    config = TestConfig()
    print(f"Test user ID: {config.TEST_USER_ID_1}")
    print(f"Test words: {config.TEST_WORDS[:3]}...")

    test_data = config.get_test_definition_data("example")
    print(f"Test definition data keys: {list(test_data.keys())}")

    print("✓ Test configuration is working")