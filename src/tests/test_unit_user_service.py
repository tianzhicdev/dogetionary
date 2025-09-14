#!/usr/bin/env python3

import unittest
import sys
import os
import json
from unittest.mock import patch, MagicMock

# Set environment variable before any imports
os.environ.setdefault('OPENAI_API_KEY', 'test-key-for-unit-tests')

# Add the src directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from services.user_service import generate_user_profile, get_user_preferences

class TestUserService(unittest.TestCase):
    """Unit tests for user service functions"""

    def setUp(self):
        """Set up test fixtures"""
        self.test_user_id = "123e4567-e89b-12d3-a456-426614174000"
        self.mock_openai_response = {
            "username": "TestLearner",
            "motto": "Every day is a learning opportunity!"
        }

    @patch('services.user_service.openai.chat.completions.create')
    def test_generate_user_profile_success(self, mock_openai):
        """Test successful user profile generation"""
        # Mock OpenAI API response
        mock_response = MagicMock()
        mock_response.choices[0].message.content.strip.return_value = json.dumps(self.mock_openai_response)
        mock_openai.return_value = mock_response

        username, motto = generate_user_profile()

        # Verify results
        self.assertEqual(username, "TestLearner")
        self.assertEqual(motto, "Every day is a learning opportunity!")

        # Verify OpenAI API was called with correct parameters
        mock_openai.assert_called_once()
        call_args = mock_openai.call_args
        self.assertIn('model', call_args[1])
        self.assertEqual(call_args[1]['model'], 'gpt-4o-mini')
        self.assertIn('messages', call_args[1])
        self.assertIn('response_format', call_args[1])

    @patch('services.user_service.openai.chat.completions.create')
    def test_generate_user_profile_long_values(self, mock_openai):
        """Test user profile generation with values that exceed length limits"""
        # Mock OpenAI response with long values
        long_response = {
            "username": "ThisIsAVeryLongUsernameThatExceedsTwentyCharacters",
            "motto": "This is a very long motto that definitely exceeds the fifty character limit set for mottos"
        }
        mock_response = MagicMock()
        mock_response.choices[0].message.content.strip.return_value = json.dumps(long_response)
        mock_openai.return_value = mock_response

        username, motto = generate_user_profile()

        # Verify length limits are enforced
        self.assertLessEqual(len(username), 20)
        self.assertLessEqual(len(motto), 50)
        self.assertEqual(username, "ThisIsAVeryLongUsern")  # Truncated to 20 chars
        self.assertEqual(motto, "This is a very long motto that definitely exceed")  # Truncated to 50 chars

    @patch('services.user_service.openai.chat.completions.create')
    def test_generate_user_profile_missing_fields(self, mock_openai):
        """Test user profile generation when OpenAI response is missing fields"""
        # Mock OpenAI response with missing fields
        incomplete_response = {"username": "TestUser"}  # Missing motto
        mock_response = MagicMock()
        mock_response.choices[0].message.content.strip.return_value = json.dumps(incomplete_response)
        mock_openai.return_value = mock_response

        username, motto = generate_user_profile()

        # Should use defaults for missing values
        self.assertEqual(username, "TestUser")
        self.assertEqual(motto, "Every word is a new adventure!")  # Default motto

    @patch('services.user_service.openai.chat.completions.create')
    def test_generate_user_profile_openai_error(self, mock_openai):
        """Test user profile generation when OpenAI API fails"""
        # Mock OpenAI API to raise an exception
        mock_openai.side_effect = Exception("OpenAI API error")

        username, motto = generate_user_profile()

        # Should return fallback values
        self.assertEqual(username, "LearningExplorer")
        self.assertEqual(motto, "Every word is a new adventure!")

    @patch('services.user_service.openai.chat.completions.create')
    def test_generate_user_profile_invalid_json(self, mock_openai):
        """Test user profile generation when OpenAI returns invalid JSON"""
        # Mock OpenAI response with invalid JSON
        mock_response = MagicMock()
        mock_response.choices[0].message.content.strip.return_value = "invalid json response"
        mock_openai.return_value = mock_response

        username, motto = generate_user_profile()

        # Should return fallback values
        self.assertEqual(username, "LearningExplorer")
        self.assertEqual(motto, "Every word is a new adventure!")

    @patch('services.user_service.get_db_connection')
    def test_get_user_preferences_existing_user(self, mock_db_connection):
        """Test getting preferences for existing user"""
        # Mock database response for existing user
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_db_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        mock_cursor.fetchone.return_value = {
            'learning_language': 'es',
            'native_language': 'en',
            'user_name': 'TestUser',
            'user_motto': 'Learning Spanish is fun!'
        }

        result = get_user_preferences(self.test_user_id)

        # Verify results
        self.assertEqual(result, ('es', 'en', 'TestUser', 'Learning Spanish is fun!'))

        # Verify database calls
        mock_db_connection.assert_called()
        mock_cursor.execute.assert_called()
        mock_cursor.close.assert_called()

    @patch('services.user_service.get_db_connection')
    @patch('services.user_service.generate_user_profile')
    def test_get_user_preferences_new_user(self, mock_generate_profile, mock_db_connection):
        """Test getting preferences for new user (creates profile)"""
        # Mock database response for non-existing user
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_db_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        # First call returns None (user not found)
        mock_cursor.fetchone.return_value = None

        # Mock user profile generation
        mock_generate_profile.return_value = ("NewUser", "Ready to learn!")

        result = get_user_preferences(self.test_user_id)

        # Verify results (should create new user with defaults)
        self.assertEqual(result, ('en', 'zh', 'NewUser', 'Ready to learn!'))

        # Verify profile generation was called
        mock_generate_profile.assert_called_once()

        # Verify database insert was called
        self.assertEqual(mock_cursor.execute.call_count, 2)  # SELECT and INSERT
        mock_conn.commit.assert_called_once()

    @patch('services.user_service.get_db_connection')
    def test_get_user_preferences_null_values(self, mock_db_connection):
        """Test getting preferences when database has null values"""
        # Mock database response with null user_name and user_motto
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_db_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        mock_cursor.fetchone.return_value = {
            'learning_language': 'fr',
            'native_language': 'en',
            'user_name': None,
            'user_motto': None
        }

        result = get_user_preferences(self.test_user_id)

        # Should convert None values to empty strings
        self.assertEqual(result, ('fr', 'en', '', ''))

    @patch('services.user_service.get_db_connection')
    def test_get_user_preferences_database_error(self, mock_db_connection):
        """Test getting preferences when database operation fails"""
        # Mock database to raise an exception
        mock_db_connection.side_effect = Exception("Database connection failed")

        result = get_user_preferences(self.test_user_id)

        # Should return fallback values
        self.assertEqual(result, ('en', 'zh', 'LearningExplorer', 'Every word is a new adventure!'))

    @patch('services.user_service.get_db_connection')
    @patch('services.user_service.generate_user_profile')
    def test_get_user_preferences_insert_conflict(self, mock_generate_profile, mock_db_connection):
        """Test handling of insert conflict (concurrent user creation)"""
        # Mock database response for new user creation with conflict handling
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_db_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        # First call returns None (user not found)
        mock_cursor.fetchone.return_value = None

        # Mock user profile generation
        mock_generate_profile.return_value = ("ConcurrentUser", "Handling conflicts!")

        result = get_user_preferences(self.test_user_id)

        # Should handle the ON CONFLICT clause gracefully
        self.assertEqual(result, ('en', 'zh', 'ConcurrentUser', 'Handling conflicts!'))

        # Verify the INSERT query uses ON CONFLICT DO NOTHING
        insert_call = None
        for call in mock_cursor.execute.call_args_list:
            if 'INSERT' in str(call):
                insert_call = call
                break

        self.assertIsNotNone(insert_call)
        self.assertIn('ON CONFLICT', str(insert_call))
        self.assertIn('DO NOTHING', str(insert_call))

    def test_user_preferences_return_type(self):
        """Test that get_user_preferences always returns a 4-tuple"""
        with patch('services.user_service.get_db_connection') as mock_db:
            mock_conn = MagicMock()
            mock_cursor = MagicMock()
            mock_db.return_value = mock_conn
            mock_conn.cursor.return_value = mock_cursor

            # Test with valid data
            mock_cursor.fetchone.return_value = {
                'learning_language': 'de',
                'native_language': 'en',
                'user_name': 'TestUser',
                'user_motto': 'Test motto'
            }

            result = get_user_preferences(self.test_user_id)

            # Should always return 4-tuple
            self.assertIsInstance(result, tuple)
            self.assertEqual(len(result), 4)
            self.assertTrue(all(isinstance(item, str) for item in result))

    @patch('services.user_service.openai.chat.completions.create')
    def test_generate_user_profile_schema_validation(self, mock_openai):
        """Test that generate_user_profile uses correct OpenAI schema"""
        mock_response = MagicMock()
        mock_response.choices[0].message.content.strip.return_value = json.dumps(self.mock_openai_response)
        mock_openai.return_value = mock_response

        generate_user_profile()

        # Verify the response format schema
        call_args = mock_openai.call_args[1]
        self.assertIn('response_format', call_args)

        response_format = call_args['response_format']
        self.assertEqual(response_format['type'], 'json_schema')
        self.assertIn('json_schema', response_format)

        schema = response_format['json_schema']
        self.assertEqual(schema['name'], 'user_profile')
        self.assertTrue(schema['strict'])

        # Check schema properties
        properties = schema['schema']['properties']
        self.assertIn('username', properties)
        self.assertIn('motto', properties)
        self.assertEqual(properties['username']['type'], 'string')
        self.assertEqual(properties['motto']['type'], 'string')

if __name__ == '__main__':
    # Run the tests
    unittest.main(verbosity=2)