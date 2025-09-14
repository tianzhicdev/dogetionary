#!/usr/bin/env python3

import unittest
import sys
import os
import json
from unittest.mock import patch, MagicMock

# Add the src directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Set environment variable before importing app
os.environ.setdefault('OPENAI_API_KEY', 'test-key-for-unit-tests')

# Import functions from the original app since they haven't been moved yet
from app import (
    get_cached_definition, build_definition_prompt,
    collect_audio_references, queue_missing_audio,
    audio_exists, store_audio, generate_audio_for_text
)

class TestDictionaryService(unittest.TestCase):
    """Unit tests for dictionary service functions"""

    def setUp(self):
        """Set up test fixtures"""
        self.test_word = "hello"
        self.learning_lang = "en"
        self.native_lang = "zh"

        self.mock_definition_data = {
            "word": "hello",
            "phonetic": "həˈloʊ",
            "translations": ["你好", "哈喽", "您好"],
            "definitions": [
                {
                    "type": "interjection",
                    "definition": "A greeting used to express a friendly attitude",
                    "definition_native": "一种问候，用于表达友好的态度",
                    "examples": [
                        "Hello! How are you today?",
                        "When she walked into the room, everyone said hello."
                    ],
                    "cultural_notes": "Standard greeting in English-speaking cultures"
                }
            ]
        }

    @patch('app.get_db_connection')
    def test_get_cached_definition_found(self, mock_db_connection):
        """Test getting cached definition when it exists"""
        # Mock database response
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_db_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        mock_cursor.fetchone.return_value = {
            'definition_data': self.mock_definition_data
        }

        result = get_cached_definition(self.test_word, self.learning_lang, self.native_lang)

        # Verify results
        self.assertIsNotNone(result)
        self.assertEqual(result['cache_type'], 'exact')
        self.assertEqual(result['definition_data'], self.mock_definition_data)

        # Verify database calls
        mock_db_connection.assert_called_once()
        mock_cursor.execute.assert_called_once()
        mock_conn.close.assert_called_once()

    @patch('app.get_db_connection')
    def test_get_cached_definition_not_found(self, mock_db_connection):
        """Test getting cached definition when it doesn't exist"""
        # Mock database response (no results)
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_db_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        mock_cursor.fetchone.return_value = None

        result = get_cached_definition(self.test_word, self.learning_lang, self.native_lang)

        # Should return None when not found
        self.assertIsNone(result)

    @patch('app.get_db_connection')
    def test_get_cached_definition_database_error(self, mock_db_connection):
        """Test getting cached definition when database fails"""
        # Mock database to raise exception
        mock_db_connection.side_effect = Exception("Database error")

        result = get_cached_definition(self.test_word, self.learning_lang, self.native_lang)

        # Should return None on error
        self.assertIsNone(result)

    def test_build_definition_prompt_different_languages(self):
        """Test building definition prompt for different languages"""
        prompt = build_definition_prompt("hello", "en", "zh")

        # Verify prompt contains expected elements
        self.assertIn("hello", prompt)
        self.assertIn("English", prompt)
        self.assertIn("Chinese", prompt)
        self.assertIn("translations", prompt)
        self.assertIn("definitions", prompt)
        self.assertIn("examples", prompt)
        self.assertIn("cultural context", prompt)

    def test_build_definition_prompt_same_languages(self):
        """Test building definition prompt when languages are the same (should raise error)"""
        with self.assertRaises(ValueError) as context:
            build_definition_prompt("hello", "en", "en")

        self.assertIn("cannot be the same", str(context.exception))

    def test_build_definition_prompt_language_mapping(self):
        """Test that language codes are correctly mapped to full names"""
        prompt = build_definition_prompt("bonjour", "fr", "es")

        # Should contain full language names
        self.assertIn("French", prompt)
        self.assertIn("Spanish", prompt)

    def test_build_definition_prompt_unknown_language(self):
        """Test building prompt with unknown language code"""
        prompt = build_definition_prompt("hello", "xx", "yy")

        # Should fall back to using the code itself
        self.assertIn("xx", prompt)
        self.assertIn("yy", prompt)

    def test_collect_audio_references_with_examples(self):
        """Test collecting audio references from definition data"""
        audio_refs = collect_audio_references(self.mock_definition_data, self.learning_lang)

        # Verify structure
        self.assertIn("example_audio", audio_refs)
        self.assertIn("word_audio", audio_refs)
        self.assertIsInstance(audio_refs["example_audio"], dict)

        # Note: The actual presence of audio depends on audio_exists() calls

    def test_collect_audio_references_empty_definition(self):
        """Test collecting audio references from empty definition"""
        empty_definition = {"definitions": []}

        audio_refs = collect_audio_references(empty_definition, self.learning_lang)

        # Should still return proper structure
        self.assertIn("example_audio", audio_refs)
        self.assertIn("word_audio", audio_refs)
        self.assertEqual(len(audio_refs["example_audio"]), 0)

    @patch('app.audio_exists')
    def test_collect_audio_references_with_existing_audio(self, mock_audio_exists):
        """Test collecting audio references when audio exists"""
        # Mock audio_exists to return True for some examples
        mock_audio_exists.side_effect = lambda text, lang: text == "Hello! How are you today?"

        audio_refs = collect_audio_references(self.mock_definition_data, self.learning_lang)

        # Should mark existing audio
        self.assertIn("Hello! How are you today?", audio_refs["example_audio"])
        self.assertTrue(audio_refs["example_audio"]["Hello! How are you today?"])

    @patch('app.audio_exists')
    @patch('app.audio_generation_queue')
    @patch('app.audio_generation_status')
    def test_queue_missing_audio_all_missing(self, mock_status, mock_queue, mock_audio_exists):
        """Test queueing audio when all audio is missing"""
        # Mock all audio as missing
        mock_audio_exists.return_value = False
        mock_queue.put = MagicMock()
        mock_status.__setitem__ = MagicMock()

        existing_audio_refs = {"example_audio": {}, "word_audio": None}

        result = queue_missing_audio(
            self.test_word,
            self.mock_definition_data,
            self.learning_lang,
            existing_audio_refs
        )

        # Should queue audio generation
        self.assertEqual(result, "queued")

        # Verify items were queued
        expected_calls = 3  # word + 2 examples
        self.assertEqual(mock_queue.put.call_count, expected_calls)

    @patch('app.audio_exists')
    def test_queue_missing_audio_all_present(self, mock_audio_exists):
        """Test queueing audio when all audio already exists"""
        # Mock all audio as existing
        mock_audio_exists.return_value = True

        existing_audio_refs = {
            "example_audio": {
                "Hello! How are you today?": True,
                "When she walked into the room, everyone said hello.": True
            },
            "word_audio": True
        }

        result = queue_missing_audio(
            self.test_word,
            self.mock_definition_data,
            self.learning_lang,
            existing_audio_refs
        )

        # Should return complete
        self.assertEqual(result, "complete")

class TestAudioService(unittest.TestCase):
    """Unit tests for audio service functions"""

    def setUp(self):
        """Set up test fixtures"""
        self.test_text = "hello"
        self.test_language = "en"
        self.mock_audio_data = b"fake_audio_data_for_testing"

    @patch('app.get_db_connection')
    def test_audio_exists_true(self, mock_db_connection):
        """Test audio_exists when audio is found"""
        # Mock database response
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_db_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        mock_cursor.fetchone.return_value = {"id": 1}  # Some result

        result = audio_exists(self.test_text, self.test_language)

        self.assertTrue(result)
        mock_cursor.execute.assert_called_once()
        mock_conn.close.assert_called_once()

    @patch('app.get_db_connection')
    def test_audio_exists_false(self, mock_db_connection):
        """Test audio_exists when audio is not found"""
        # Mock database response (no results)
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_db_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        mock_cursor.fetchone.return_value = None

        result = audio_exists(self.test_text, self.test_language)

        self.assertFalse(result)

    @patch('app.get_db_connection')
    def test_audio_exists_database_error(self, mock_db_connection):
        """Test audio_exists when database fails"""
        # Mock database to raise exception
        mock_db_connection.side_effect = Exception("Database error")

        result = audio_exists(self.test_text, self.test_language)

        # Should return False on error
        self.assertFalse(result)

    @patch('app.get_db_connection')
    def test_store_audio_success(self, mock_db_connection):
        """Test storing audio successfully"""
        # Mock database response
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_db_connection.return_value = mock_conn
        mock_conn.cursor.return_value = mock_cursor

        from datetime import datetime
        mock_created_at = datetime(2024, 1, 1, 12, 0, 0)
        mock_cursor.fetchone.return_value = {"created_at": mock_created_at}

        result = store_audio(self.test_text, self.test_language, self.mock_audio_data)

        # Should return ISO format timestamp
        self.assertEqual(result, mock_created_at.isoformat())

        # Verify database calls
        self.assertEqual(mock_cursor.execute.call_count, 2)  # INSERT and SELECT
        mock_conn.commit.assert_called_once()
        mock_conn.close.assert_called_once()

    @patch('app.get_db_connection')
    def test_store_audio_database_error(self, mock_db_connection):
        """Test storing audio when database fails"""
        # Mock database to raise exception
        mock_db_connection.side_effect = Exception("Database error")

        with self.assertRaises(Exception):
            store_audio(self.test_text, self.test_language, self.mock_audio_data)

    @patch('app.client.audio.speech.create')
    def test_generate_audio_for_text_success(self, mock_tts):
        """Test successful audio generation"""
        # Mock OpenAI TTS response
        mock_response = MagicMock()
        mock_response.content = self.mock_audio_data
        mock_tts.return_value = mock_response

        result = generate_audio_for_text(self.test_text)

        self.assertEqual(result, self.mock_audio_data)

        # Verify TTS API was called correctly
        mock_tts.assert_called_once_with(
            model="tts-1",
            voice="alloy",
            input=self.test_text,
            response_format="mp3"
        )

    @patch('app.client.audio.speech.create')
    def test_generate_audio_for_text_error(self, mock_tts):
        """Test audio generation when TTS API fails"""
        # Mock TTS API to raise exception
        mock_tts.side_effect = Exception("TTS API error")

        with self.assertRaises(Exception):
            generate_audio_for_text(self.test_text)

    def test_audio_upsert_behavior(self):
        """Test that store_audio uses upsert behavior (ON CONFLICT)"""
        with patch('app.get_db_connection') as mock_db:
            mock_conn = MagicMock()
            mock_cursor = MagicMock()
            mock_db.return_value = mock_conn
            mock_conn.cursor.return_value = mock_cursor

            from datetime import datetime
            mock_created_at = datetime(2024, 1, 1, 12, 0, 0)
            mock_cursor.fetchone.return_value = {"created_at": mock_created_at}

            store_audio(self.test_text, self.test_language, self.mock_audio_data)

            # Check that the INSERT query includes ON CONFLICT clause
            insert_call = mock_cursor.execute.call_args_list[0]
            query = insert_call[0][0]

            self.assertIn("ON CONFLICT", query)
            self.assertIn("DO UPDATE SET", query)

if __name__ == '__main__':
    # Run the tests
    unittest.main(verbosity=2)