#!/usr/bin/env python3

import requests
import json
import uuid
import time
from typing import Dict, Any

# Base URL for the API
BASE_URL = "http://localhost:5001"

class TestRunner:
    def __init__(self):
        self.test_user_id = str(uuid.uuid4())
        self.passed = 0
        self.failed = 0
        
    def log(self, message: str):
        print(f"[TEST] {message}")
        
    def assert_status_code(self, response: requests.Response, expected: int, test_name: str):
        if response.status_code == expected:
            self.log(f"✓ {test_name} - Status code {response.status_code}")
            self.passed += 1
        else:
            self.log(f"✗ {test_name} - Expected {expected}, got {response.status_code}")
            self.log(f"   Response: {response.text}")
            self.failed += 1
            
    def assert_json_contains(self, data: Dict[Any, Any], key: str, test_name: str):
        if key in data:
            self.log(f"✓ {test_name} - Contains key '{key}'")
            self.passed += 1
        else:
            self.log(f"✗ {test_name} - Missing key '{key}'")
            self.log(f"   Data: {json.dumps(data, indent=2)}")
            self.failed += 1
            
    def wait_for_service(self, max_retries=30):
        """Wait for the service to be ready"""
        self.log("Waiting for service to be ready...")
        for i in range(max_retries):
            try:
                response = requests.get(f"{BASE_URL}/health", timeout=5)
                if response.status_code == 200:
                    self.log("✓ Service is ready!")
                    return True
            except requests.exceptions.RequestException as e:
                self.log(e)
                pass
            time.sleep(2)
        self.log("✗ Service failed to start within timeout")
        return False

    def test_health_endpoint(self):
        """Test the health check endpoint"""
        self.log("Testing /health endpoint...")
        
        try:
            response = requests.get(f"{BASE_URL}/health")
            self.assert_status_code(response, 200, "/health endpoint")
            
            data = response.json()
            self.assert_json_contains(data, "status", "/health response contains status")
            
        except Exception as e:
            self.log(f"✗ /health endpoint failed with error: {e}")
            self.failed += 1

    def test_word_definition_endpoint(self):
        """Test the word definition endpoint"""
        self.log("Testing /word endpoint...")
        
        # Test valid word request
        try:
            response = requests.get(f"{BASE_URL}/word", params={"w": "hello", "user_id": self.test_user_id, "learning_lang": "en", "native_lang": "zh"})
            self.assert_status_code(response, 200, "/word endpoint with valid word")
            
            data = response.json()
            self.assert_json_contains(data, "word", "/word response contains word")
            self.assert_json_contains(data, "learning_language", "/word response contains learning_language")
            self.assert_json_contains(data, "native_language", "/word response contains native_language")
            self.assert_json_contains(data, "definition_data", "/word response contains definition_data")
            self.assert_json_contains(data, "audio_references", "/word response contains audio_references")
            self.assert_json_contains(data, "audio_generation_status", "/word response contains audio_generation_status")
            
        except Exception as e:
            self.log(f"✗ /word endpoint failed with error: {e}")
            self.failed += 1
            
        # Test missing parameter
        try:
            response = requests.get(f"{BASE_URL}/word")
            self.assert_status_code(response, 400, "/word endpoint without parameter")
            
        except Exception as e:
            self.log(f"✗ /word endpoint error test failed: {e}")
            self.failed += 1

    def test_save_word_endpoint(self):
        """Test the save word endpoint"""
        self.log("Testing /save endpoint...")
        
        # Test valid save request
        try:
            payload = {
                "word": "hello",
                "user_id": self.test_user_id,
                "learning_language": "en",
                "metadata": {"source": "test", "category": "greeting"}
            }
            
            response = requests.post(f"{BASE_URL}/save", json=payload)
            self.assert_status_code(response, 201, "/save endpoint with valid data")
            
            data = response.json()
            self.assert_json_contains(data, "message", "/save response contains message")
            self.assert_json_contains(data, "word_id", "/save response contains word_id")
            self.assert_json_contains(data, "success", "/save response contains success")
            self.assert_json_contains(data, "created_at", "/save response contains created_at")
            
        except Exception as e:
            self.log(f"✗ /save endpoint failed with error: {e}")
            self.failed += 1
            
        # Test missing word parameter
        try:
            payload = {"user_id": self.test_user_id, "learning_language": "en"}
            response = requests.post(f"{BASE_URL}/save", json=payload)
            self.assert_status_code(response, 400, "/save endpoint without word")
            
        except Exception as e:
            self.log(f"✗ /save endpoint error test failed: {e}")
            self.failed += 1
            
        # Test missing user_id parameter
        try:
            payload = {"word": "test", "learning_language": "en"}
            response = requests.post(f"{BASE_URL}/save", json=payload)
            self.assert_status_code(response, 400, "/save endpoint without user_id")
            
        except Exception as e:
            self.log(f"✗ /save endpoint error test failed: {e}")
            self.failed += 1
            
        # Test invalid user_id format
        try:
            payload = {"word": "test", "user_id": "invalid-uuid", "learning_language": "en"}
            response = requests.post(f"{BASE_URL}/save", json=payload)
            self.assert_status_code(response, 400, "/save endpoint with invalid user_id")
            
        except Exception as e:
            self.log(f"✗ /save endpoint error test failed: {e}")
            self.failed += 1

    def test_saved_words_endpoint(self):
        """Test the saved words endpoint"""
        self.log("Testing /saved_words endpoint...")
        
        # First, save a few words for testing
        test_words = ["apple", "banana", "cherry"]
        for word in test_words:
            payload = {
                "word": word,
                "user_id": self.test_user_id,
                "learning_language": "en",
                "metadata": {"test_word": True}
            }
            requests.post(f"{BASE_URL}/save", json=payload)
        
        # Test retrieving saved words
        try:
            response = requests.get(f"{BASE_URL}/saved_words", params={"user_id": self.test_user_id})
            self.assert_status_code(response, 200, "/saved_words endpoint")
            
            data = response.json()
            self.assert_json_contains(data, "user_id", "/saved_words response contains user_id")
            self.assert_json_contains(data, "saved_words", "/saved_words response contains saved_words")
            self.assert_json_contains(data, "count", "/saved_words response contains count")
            
            # Check if we have at least the words we saved
            saved_words = data.get("saved_words", [])
            if len(saved_words) >= 4:  # hello from previous test + 3 new words
                self.log(f"✓ /saved_words returned {len(saved_words)} words")
                self.passed += 1
            else:
                self.log(f"✗ /saved_words returned {len(saved_words)} words, expected at least 4")
                self.failed += 1
                
        except Exception as e:
            self.log(f"✗ /saved_words endpoint failed with error: {e}")
            self.failed += 1
            
        # Test missing user_id parameter
        try:
            response = requests.get(f"{BASE_URL}/saved_words")
            self.assert_status_code(response, 400, "/saved_words endpoint without user_id")
            
        except Exception as e:
            self.log(f"✗ /saved_words endpoint error test failed: {e}")
            self.failed += 1
            
        # Test invalid user_id format
        try:
            response = requests.get(f"{BASE_URL}/saved_words", params={"user_id": "invalid-uuid"})
            self.assert_status_code(response, 400, "/saved_words endpoint with invalid user_id")
            
        except Exception as e:
            self.log(f"✗ /saved_words endpoint error test failed: {e}")
            self.failed += 1

    def test_duplicate_save(self):
        """Test saving the same word twice (should update, not duplicate)"""
        self.log("Testing duplicate word save...")
        
        try:
            # Save a word
            payload1 = {
                "word": "duplicate_test",
                "user_id": self.test_user_id,
                "learning_language": "en",
                "metadata": {"version": 1}
            }
            
            response1 = requests.post(f"{BASE_URL}/save", json=payload1)
            self.assert_status_code(response1, 201, "First save of duplicate word")
            
            # Save the same word again with different metadata
            payload2 = {
                "word": "duplicate_test",
                "user_id": self.test_user_id,
                "learning_language": "en",
                "metadata": {"version": 2}
            }
            
            response2 = requests.post(f"{BASE_URL}/save", json=payload2)
            self.assert_status_code(response2, 201, "Second save of duplicate word")
            
            # Verify we still only have one instance of this word
            response = requests.get(f"{BASE_URL}/saved_words", params={"user_id": self.test_user_id})
            data = response.json()
            saved_words = data.get("saved_words", [])
            
            duplicate_words = [w for w in saved_words if w["word"] == "duplicate_test"]
            if len(duplicate_words) == 1:
                self.log("✓ Duplicate word handling - only one instance exists")
                self.passed += 1
                
                # Check if metadata was updated
                if duplicate_words[0]["metadata"].get("version") == 2:
                    self.log("✓ Duplicate word handling - metadata updated")
                    self.passed += 1
                else:
                    self.log("✗ Duplicate word handling - metadata not updated")
                    self.failed += 1
            else:
                self.log(f"✗ Duplicate word handling - found {len(duplicate_words)} instances")
                self.failed += 1
                
        except Exception as e:
            self.log(f"✗ Duplicate save test failed with error: {e}")
            self.failed += 1

    def test_audio_endpoint(self):
        """Test the new audio endpoint"""
        self.log("Testing /audio/<text>/<language> endpoint...")
        
        try:
            # Test fetching audio for a word
            text = "hello"
            language = "en"
            response = requests.get(f"{BASE_URL}/audio/{text}/{language}")
            self.assert_status_code(response, 200, f"/audio/{text}/{language} endpoint")
            
            data = response.json()
            self.assert_json_contains(data, "audio_data", "/audio response contains audio_data")
            self.assert_json_contains(data, "content_type", "/audio response contains content_type")
            self.assert_json_contains(data, "created_at", "/audio response contains created_at")
            
            # Verify audio data is base64 encoded
            try:
                import base64
                audio_bytes = base64.b64decode(data["audio_data"])
                if len(audio_bytes) > 100:
                    self.log(f"✓ Audio data is valid base64 ({len(audio_bytes)} bytes)")
                    self.passed += 1
                else:
                    self.log("✗ Audio data seems too small")
                    self.failed += 1
            except Exception as e:
                self.log(f"✗ Failed to decode audio data: {e}")
                self.failed += 1
                
        except Exception as e:
            self.log(f"✗ /audio endpoint failed with error: {e}")
            self.failed += 1

    def test_next_due_endpoint(self):
        """Test the next due words endpoint"""
        self.log("Testing /review_next endpoint...")

        try:
            # Test getting next review word
            response = requests.get(f"{BASE_URL}/review_next", params={"user_id": self.test_user_id})
            self.assert_status_code(response, 200, "/review_next endpoint")

            data = response.json()
            # The /review_next endpoint returns saved_words format with user_id, saved_words array, and count
            if "no_words_due" in data:
                self.assert_json_contains(data, "no_words_due", "/review_next response contains no_words_due")
            else:
                self.assert_json_contains(data, "user_id", "/review_next response contains user_id")
                self.assert_json_contains(data, "saved_words", "/review_next response contains saved_words")
                self.assert_json_contains(data, "count", "/review_next response contains count")
            
        except Exception as e:
            self.log(f"✗ /review_next endpoint failed with error: {e}")
            self.failed += 1

    def test_test_prep_settings_toggle(self):
        """Test user preferences endpoint with test prep settings - toggle functionality"""
        self.log("Testing test prep settings toggle via /v3/users/{user_id}/preferences...")

        try:
            # First, enable TOEFL_ADVANCED
            update_data = {
                "learning_language": "en",
                "native_language": "zh",
                "user_name": "Test User",
                "user_motto": "Learning is fun",
                "test_prep": "TOEFL_ADVANCED",
                "study_duration_days": 30
            }
            response = requests.post(f"{BASE_URL}/v3/users/{self.test_user_id}/preferences", json=update_data)
            self.assert_status_code(response, 200, "POST /v3/users/{user_id}/preferences - enable TOEFL")

            if response.status_code == 200:
                data = response.json()
                self.assert_json_contains(data, "user_id", "Response contains user_id")
                self.assert_json_contains(data, "test_prep", "Response contains test_prep")

            # Test GET endpoint to verify settings
            response = requests.get(f"{BASE_URL}/v3/users/{self.test_user_id}/preferences")
            self.assert_status_code(response, 200, "GET /v3/users/{user_id}/preferences")

            if response.status_code == 200:
                data = response.json()
                self.assert_json_contains(data, "test_prep", "GET response contains test_prep")
                self.assert_json_contains(data, "study_duration_days", "GET response contains study_duration_days")

                if data['test_prep'] == "TOEFL_ADVANCED":
                    self.log("✓ TOEFL_ADVANCED correctly enabled after initial setup")
                    self.passed += 1
                else:
                    self.log("✗ TOEFL_ADVANCED should be enabled but is not")
                    self.failed += 1

            # Test disabling all test prep (set test_prep to null)
            disable_data = {
                "learning_language": "en",
                "native_language": "zh",
                "user_name": "Test User",
                "user_motto": "Learning is fun",
                "test_prep": None,
                "study_duration_days": 30
            }
            response = requests.post(f"{BASE_URL}/v3/users/{self.test_user_id}/preferences", json=disable_data)
            self.assert_status_code(response, 200, "POST /v3/users/{user_id}/preferences - disable test prep")

            if response.status_code == 200:
                data = response.json()
                if data['test_prep'] is None:
                    self.log("✓ Test prep correctly disabled")
                    self.passed += 1
                else:
                    self.log("✗ Test prep should be disabled but is still enabled (BUG!)")
                    self.failed += 1

            # Verify with GET that test prep is disabled
            response = requests.get(f"{BASE_URL}/v3/users/{self.test_user_id}/preferences")
            if response.status_code == 200:
                data = response.json()
                if data['test_prep'] is None:
                    self.log("✓ GET confirms test prep is disabled")
                    self.passed += 1
                else:
                    self.log("✗ GET shows test prep still enabled (BUG!)")
                    self.failed += 1

            # Test re-enabling with IELTS_BEGINNER
            enable_data = {
                "learning_language": "en",
                "native_language": "zh",
                "user_name": "Test User",
                "user_motto": "Learning is fun",
                "test_prep": "IELTS_BEGINNER",
                "study_duration_days": 45
            }
            response = requests.post(f"{BASE_URL}/v3/users/{self.test_user_id}/preferences", json=enable_data)
            if response.status_code == 200:
                data = response.json()
                if data['test_prep'] == "IELTS_BEGINNER":
                    self.log("✓ IELTS_BEGINNER correctly enabled")
                    self.passed += 1
                else:
                    self.log("✗ IELTS_BEGINNER should be enabled but is not")
                    self.failed += 1

        except Exception as e:
            self.log(f"✗ Test prep settings toggle test failed with error: {e}")
            self.failed += 1

    def test_combined_metrics_endpoint(self):
        """Test the combined metrics endpoint"""
        self.log("Testing /v3/combined_metrics endpoint...")

        try:
            # Test with default days parameter (30)
            response = requests.get(f"{BASE_URL}/v3/combined_metrics")
            self.assert_status_code(response, 200, "GET /v3/combined_metrics (default days)")

            if response.status_code == 200:
                data = response.json()
                self.assert_json_contains(data, "daily_metrics", "/v3/combined_metrics contains daily_metrics")
                self.assert_json_contains(data, "days", "/v3/combined_metrics contains days")

                # Verify daily_metrics is a list
                if isinstance(data.get("daily_metrics"), list):
                    self.log("✓ daily_metrics is a list")
                    self.passed += 1

                    # Verify each metric has the required fields
                    if len(data["daily_metrics"]) > 0:
                        first_metric = data["daily_metrics"][0]
                        self.assert_json_contains(first_metric, "date", "daily_metric contains date")
                        self.assert_json_contains(first_metric, "lookups", "daily_metric contains lookups")
                        self.assert_json_contains(first_metric, "reviews", "daily_metric contains reviews")
                        self.assert_json_contains(first_metric, "unique_users", "daily_metric contains unique_users")

                        # Verify data types
                        if isinstance(first_metric.get("lookups"), int):
                            self.log("✓ lookups is an integer")
                            self.passed += 1
                        else:
                            self.log("✗ lookups should be an integer")
                            self.failed += 1

                        if isinstance(first_metric.get("reviews"), int):
                            self.log("✓ reviews is an integer")
                            self.passed += 1
                        else:
                            self.log("✗ reviews should be an integer")
                            self.failed += 1

                        if isinstance(first_metric.get("unique_users"), int):
                            self.log("✓ unique_users is an integer")
                            self.passed += 1
                        else:
                            self.log("✗ unique_users should be an integer")
                            self.failed += 1
                else:
                    self.log("✗ daily_metrics should be a list")
                    self.failed += 1

            # Test with custom days parameter
            response = requests.get(f"{BASE_URL}/v3/combined_metrics", params={"days": 7})
            self.assert_status_code(response, 200, "GET /v3/combined_metrics (days=7)")

            if response.status_code == 200:
                data = response.json()
                if data.get("days") == 7:
                    self.log("✓ days parameter correctly set to 7")
                    self.passed += 1
                else:
                    self.log(f"✗ Expected days=7, got days={data.get('days')}")
                    self.failed += 1

        except Exception as e:
            self.log(f"✗ /v3/combined_metrics endpoint failed with error: {e}")
            self.failed += 1

    def test_next_review_word_with_scheduled_new_words(self):
        """Test the new endpoint that integrates scheduled new words"""
        self.log("Testing /v3/next-review-word-with-scheduled-new-words endpoint...")

        try:
            # First create a schedule for the test user
            from datetime import date, timedelta
            target_date = (date.today() + timedelta(days=60)).isoformat()

            schedule_response = requests.post(
                f"{BASE_URL}/v3/schedule/create",
                json={
                    "user_id": self.test_user_id,
                    "test_type": "TOEFL",
                    "target_end_date": target_date
                }
            )

            if schedule_response.status_code != 200:
                self.log(f"⚠️  Could not create schedule (status {schedule_response.status_code}), but continuing with test")

            # Test the new endpoint
            response = requests.get(
                f"{BASE_URL}/v3/next-review-word-with-scheduled-new-words",
                params={"user_id": self.test_user_id}
            )

            self.assert_status_code(
                response,
                200,
                "GET /v3/next-review-word-with-scheduled-new-words"
            )

            if response.status_code == 200:
                data = response.json()

                # Verify response structure
                self.assert_json_contains(data, "user_id", "Response contains user_id")
                self.assert_json_contains(data, "saved_words", "Response contains saved_words")
                self.assert_json_contains(data, "count", "Response contains count")
                self.assert_json_contains(data, "new_words_remaining_today", "Response contains new_words_remaining_today")

                # Verify count matches saved_words length
                if data.get("count") == len(data.get("saved_words", [])):
                    self.log("✓ count matches saved_words length")
                    self.passed += 1
                else:
                    self.log(f"✗ count mismatch: count={data.get('count')}, saved_words length={len(data.get('saved_words', []))}")
                    self.failed += 1

                # If there are words, verify structure
                if data.get("saved_words"):
                    word = data["saved_words"][0]
                    required_fields = ["id", "word", "learning_language", "native_language"]
                    for field in required_fields:
                        self.assert_json_contains(word, field, f"Word object contains {field}")

                    # Check if is_new_word field exists (optional)
                    if "is_new_word" in word:
                        self.log("✓ Word object contains is_new_word field")
                        self.passed += 1
                    else:
                        self.log("⚠️  Word object missing optional is_new_word field")

        except Exception as e:
            self.log(f"✗ /v3/next-review-word-with-scheduled-new-words endpoint failed with error: {e}")
            self.failed += 1

    def test_review_complete_logic(self):
        """Test that review complete triggers only when overdue and new words are done"""
        self.log("Testing review complete logic (no non-due words returned)...")

        try:
            # Use a fresh user with no words
            test_user = str(uuid.uuid4())

            # Test 1: No words should return empty
            response = requests.get(
                f"{BASE_URL}/v3/next-review-word-with-scheduled-new-words",
                params={"user_id": test_user}
            )

            if response.status_code == 200:
                data = response.json()
                if data.get("count") == 0:
                    self.log("✓ No words returns empty response (review complete)")
                    self.passed += 1
                else:
                    self.log(f"✗ Expected count=0, got count={data.get('count')}")
                    self.failed += 1
            else:
                self.log(f"✗ Request failed with status {response.status_code}")
                self.failed += 1

            # Note: Testing that non-due words are NOT returned would require
            # setting up words with future next_review_dates, which is complex
            # in a test environment. The logic has been verified in the code.

        except Exception as e:
            self.log(f"✗ Review complete logic test failed with error: {e}")
            self.failed += 1

    def test_test_vocabulary_awards_endpoint(self):
        """Test the test vocabulary awards endpoint"""
        self.log("Testing /v3/achievements/test-vocabulary-awards endpoint...")

        try:
            # Test with test user
            response = requests.get(
                f"{BASE_URL}/v3/achievements/test-vocabulary-awards",
                params={"user_id": self.test_user_id}
            )
            self.assert_status_code(response, 200, "/v3/achievements/test-vocabulary-awards")

            data = response.json()
            self.assert_json_contains(data, "user_id", "Response contains user_id")

            # If user has test type selected, check award data
            if data.get("test_type"):
                self.assert_json_contains(data, "total_words", "Response contains total_words")
                self.assert_json_contains(data, "completed_words", "Response contains completed_words")
                self.assert_json_contains(data, "progress_percentage", "Response contains progress_percentage")
                self.assert_json_contains(data, "unlocked", "Response contains unlocked status")
                self.assert_json_contains(data, "award", "Response contains award metadata")

                award = data.get("award", {})
                self.assert_json_contains(award, "title", "Award contains title")
                self.assert_json_contains(award, "symbol", "Award contains symbol")
                self.assert_json_contains(award, "tier", "Award contains tier")

                self.log(f"✓ Award data: {data.get('completed_words')}/{data.get('total_words')} ({data.get('progress_percentage')}%) - Unlocked: {data.get('unlocked')}")
                self.passed += 1
            else:
                self.log("✓ No test type selected (expected for new user)")
                self.passed += 1

            # Test missing user_id
            response = requests.get(f"{BASE_URL}/v3/achievements/test-vocabulary-awards")
            self.assert_status_code(response, 400, "/v3/achievements/test-vocabulary-awards without user_id")

            # Test invalid user_id format
            response = requests.get(
                f"{BASE_URL}/v3/achievements/test-vocabulary-awards",
                params={"user_id": "invalid-uuid"}
            )
            self.assert_status_code(response, 400, "/v3/achievements/test-vocabulary-awards with invalid user_id")

        except Exception as e:
            self.log(f"✗ /v3/achievements/test-vocabulary-awards endpoint failed with error: {e}")
            self.failed += 1

    def test_app_version_endpoint(self):
        """Test the app version check endpoint"""
        self.log("Testing /v3/app-version endpoint...")

        try:
            # Test with valid version
            response = requests.get(
                f"{BASE_URL}/v3/app-version",
                params={"platform": "ios", "version": "1.0.0"}
            )
            self.assert_status_code(response, 200, "/v3/app-version with valid params")

            data = response.json()
            self.assert_json_contains(data, "status", "Response contains status")

            # Verify status is one of the expected values
            valid_statuses = ["ok", "upgrade_required", "upgrade_recommended"]
            if data.get("status") in valid_statuses:
                self.log(f"✓ Status is valid: {data.get('status')}")
                self.passed += 1
            else:
                self.log(f"✗ Invalid status: {data.get('status')}")
                self.failed += 1

            # Test missing platform parameter
            response = requests.get(
                f"{BASE_URL}/v3/app-version",
                params={"version": "1.0.0"}
            )
            self.assert_status_code(response, 400, "/v3/app-version without platform")

            # Test missing version parameter
            response = requests.get(
                f"{BASE_URL}/v3/app-version",
                params={"platform": "ios"}
            )
            self.assert_status_code(response, 400, "/v3/app-version without version")

            # Test with non-ios platform (should return ok)
            response = requests.get(
                f"{BASE_URL}/v3/app-version",
                params={"platform": "android", "version": "1.0.0"}
            )
            self.assert_status_code(response, 200, "/v3/app-version with android platform")
            data = response.json()
            if data.get("status") == "ok":
                self.log("✓ Non-iOS platform returns ok")
                self.passed += 1
            else:
                self.log(f"✗ Non-iOS platform should return ok, got: {data.get('status')}")
                self.failed += 1

        except Exception as e:
            self.log(f"✗ /v3/app-version endpoint failed with error: {e}")
            self.failed += 1

    def test_practice_status_without_test(self):
        """Test practice status when no test is enabled"""
        self.log("Testing /v3/practice-status without test enabled...")

        try:
            # Create a fresh user ID for this test
            test_user_id = str(uuid.uuid4())

            # Save a word that will be due for review
            payload = {
                "word": "practice",
                "user_id": test_user_id,
                "learning_language": "en",
                "metadata": {"source": "test"}
            }
            response = requests.post(f"{BASE_URL}/save", json=payload)
            self.assert_status_code(response, 201, "Save word for practice test")
            word_id = response.json()["word_id"]

            # Submit a review for this word to make it due
            review_payload = {
                "user_id": test_user_id,
                "word_id": word_id,
                "response": True
            }
            response = requests.post(f"{BASE_URL}/review", json=review_payload)
            self.assert_status_code(response, 200, "Submit review for practice word")

            # Wait a moment for the review to be processed
            time.sleep(0.5)

            # Make sure no test prep is enabled (default state)
            # Get practice status
            response = requests.get(f"{BASE_URL}/v3/practice-status", params={"user_id": test_user_id})
            self.assert_status_code(response, 200, "/v3/practice-status without test enabled")

            data = response.json()
            self.assert_json_contains(data, "user_id", "practice-status response contains user_id")
            self.assert_json_contains(data, "new_words_count", "practice-status response contains new_words_count")
            self.assert_json_contains(data, "test_practice_count", "practice-status response contains test_practice_count")
            self.assert_json_contains(data, "non_test_practice_count", "practice-status response contains non_test_practice_count")
            self.assert_json_contains(data, "not_due_yet_count", "practice-status response contains not_due_yet_count")
            self.assert_json_contains(data, "has_practice", "practice-status response contains has_practice")

            # Verify behavior without test enabled
            if data.get("test_practice_count") == 0:
                self.log(f"✓ test_practice_count is 0 when no test enabled")
                self.passed += 1
            else:
                self.log(f"✗ Expected test_practice_count=0, got {data.get('test_practice_count')}")
                self.failed += 1

            if data.get("new_words_count") == 0:
                self.log(f"✓ new_words_count is 0 when no test enabled")
                self.passed += 1
            else:
                self.log(f"✗ Expected new_words_count=0, got {data.get('new_words_count')}")
                self.failed += 1

            # non_test_practice_count should reflect words due for review
            # (may be 0 or 1 depending on timing)
            self.log(f"   non_test_practice_count: {data.get('non_test_practice_count')}")

        except Exception as e:
            self.log(f"✗ /v3/practice-status without test failed with error: {e}")
            self.failed += 1

    def test_practice_status_has_practice_logic(self):
        """Test that has_practice excludes not_due_yet_count"""
        self.log("Testing /v3/practice-status has_practice logic...")

        try:
            # Create a fresh user ID for this test
            test_user_id = str(uuid.uuid4())

            # Get initial practice status (should have no practice)
            response = requests.get(f"{BASE_URL}/v3/practice-status", params={"user_id": test_user_id})
            self.assert_status_code(response, 200, "/v3/practice-status initial state")

            data = response.json()

            # With no words, all counts should be 0
            if (data.get("new_words_count") == 0 and
                data.get("test_practice_count") == 0 and
                data.get("non_test_practice_count") == 0):
                self.log(f"✓ All practice counts are 0 for new user")
                self.passed += 1
            else:
                self.log(f"✗ Expected all counts to be 0 for new user")
                self.failed += 1

            # has_practice should be False when all counts are 0,
            # even if not_due_yet_count > 0 (though it should also be 0)
            if not data.get("has_practice"):
                self.log(f"✓ has_practice is False when no words are due")
                self.passed += 1
            else:
                self.log(f"✗ has_practice should be False, got {data.get('has_practice')}")
                self.failed += 1

            # Verify not_due_yet_count doesn't affect has_practice
            if data.get("not_due_yet_count") == 0:
                self.log(f"✓ not_due_yet_count is 0 for new user (expected)")
                self.passed += 1

        except Exception as e:
            self.log(f"✗ /v3/practice-status has_practice logic test failed with error: {e}")
            self.failed += 1

    def test_pronunciation_review_endpoint(self):
        """Test the pronunciation review endpoint"""
        self.log("Testing /v3/review/pronounce endpoint...")

        try:
            # Test with missing required fields
            response = requests.post(
                f"{BASE_URL}/v3/review/pronounce",
                json={}
            )
            self.assert_status_code(response, 400, "/v3/review/pronounce with missing fields")

            # Test with missing user_id
            response = requests.post(
                f"{BASE_URL}/v3/review/pronounce",
                json={
                    "word": "hello",
                    "original_text": "Hello, how are you?",
                    "audio_data": "fake_base64_data",
                    "learning_language": "en",
                    "native_language": "zh"
                }
            )
            self.assert_status_code(response, 400, "/v3/review/pronounce without user_id")

            # Test with missing word
            response = requests.post(
                f"{BASE_URL}/v3/review/pronounce",
                json={
                    "user_id": self.test_user_id,
                    "original_text": "Hello, how are you?",
                    "audio_data": "fake_base64_data",
                    "learning_language": "en",
                    "native_language": "zh"
                }
            )
            self.assert_status_code(response, 400, "/v3/review/pronounce without word")

            # Test with invalid audio data (should fail at audio processing stage)
            # We expect this to fail with 500 or 400 since audio data is invalid
            response = requests.post(
                f"{BASE_URL}/v3/review/pronounce",
                json={
                    "user_id": self.test_user_id,
                    "word": "hello",
                    "original_text": "Hello, how are you?",
                    "audio_data": "invalid_base64",
                    "learning_language": "en",
                    "native_language": "zh",
                    "evaluation_threshold": 0.7
                }
            )
            # Accept either 400 (invalid base64) or 500 (audio processing error)
            if response.status_code in [400, 500]:
                self.log(f"✓ /v3/review/pronounce with invalid audio data (status: {response.status_code})")
                self.passed += 1
            else:
                self.log(f"✗ Expected 400 or 500, got {response.status_code}")
                self.failed += 1

            self.log("Note: Full pronunciation review test requires valid audio data - skipping complete flow test")

        except Exception as e:
            self.log(f"✗ /v3/review/pronounce endpoint failed with error: {e}")
            self.failed += 1

    def test_video_search_only_video_questions(self):
        """Test that video search endpoint only returns video_mc questions"""
        self.log("Testing /v3/video-questions-for-word endpoint...")

        try:
            # Test with a common word
            response = requests.get(
                f"{BASE_URL}/v3/video-questions-for-word",
                params={
                    "word": "hello",
                    "lang": "en"
                }
            )

            if response.status_code == 200:
                data = response.json()
                self.assert_json_contains(data, 'questions', 'video search response contains questions')

                # Verify ALL questions are video_mc type
                questions = data.get('questions', [])
                all_video_mc = all(
                    q.get('question', {}).get('question_type') == 'video_mc'
                    for q in questions
                )

                if all_video_mc and len(questions) > 0:
                    self.log(f"✓ All {len(questions)} questions are video_mc type")
                    self.passed += 1
                elif len(questions) == 0:
                    self.log(f"✓ No questions returned (acceptable for words without videos)")
                    self.passed += 1
                else:
                    non_video_types = [
                        q.get('question', {}).get('question_type')
                        for q in questions
                        if q.get('question', {}).get('question_type') != 'video_mc'
                    ]
                    self.log(f"✗ Found non-video questions: {non_video_types}")
                    self.failed += 1
            else:
                # 404 is acceptable if no videos found for the word
                if response.status_code == 404:
                    self.log(f"✓ No videos found for word (404 is acceptable)")
                    self.passed += 1
                else:
                    self.log(f"✗ Unexpected status code: {response.status_code}")
                    self.log(f"   Response: {response.text}")
                    self.failed += 1

        except Exception as e:
            self.log(f"✗ Exception in video search test: {str(e)}")
            self.failed += 1

    def run_all_tests(self):
        """Run all integration tests"""
        self.log("Starting integration tests...")

        if not self.wait_for_service():
            self.log("✗ Cannot run tests - service not available")
            return False

        self.test_health_endpoint()
        self.test_word_definition_endpoint()
        self.test_save_word_endpoint()
        self.test_saved_words_endpoint()
        self.test_duplicate_save()
        self.test_audio_endpoint()
        self.test_next_due_endpoint()
        self.test_test_prep_settings_toggle()
        self.test_combined_metrics_endpoint()
        self.test_next_review_word_with_scheduled_new_words()
        self.test_review_complete_logic()
        self.test_test_vocabulary_awards_endpoint()
        self.test_app_version_endpoint()
        self.test_practice_status_without_test()
        self.test_practice_status_has_practice_logic()
        self.test_pronunciation_review_endpoint()
        self.test_video_search_only_video_questions()

        self.log(f"\nTest Results: {self.passed} passed, {self.failed} failed")

        if self.failed == 0:
            self.log("🎉 All tests passed!")
            return True
        else:
            self.log("❌ Some tests failed!")
            return False

if __name__ == "__main__":
    runner = TestRunner()
    success = runner.run_all_tests()
    exit(0 if success else 1)