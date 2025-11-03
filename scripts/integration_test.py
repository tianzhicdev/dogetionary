#!/usr/bin/env python3

import requests
import json
import uuid
import time
from typing import Dict, Any

# Base URL for the API
BASE_URL = "http://localhost:5000"

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
        """Test GET /v3/api/test-prep/settings and PUT /v3/api/test-prep/settings endpoints - especially toggle functionality"""
        self.log("Testing test prep settings toggle...")

        try:
            # First, update settings to ensure user exists in user_preferences
            update_data = {
                "user_id": self.test_user_id,
                "toefl_enabled": True,
                "ielts_enabled": False,
                "toefl_target_days": 30,
                "ielts_target_days": 60
            }
            response = requests.put(f"{BASE_URL}/v3/api/test-prep/settings", json=update_data)
            self.assert_status_code(response, 200, "PUT /v3/api/test-prep/settings - initial setup")

            if response.status_code == 200:
                data = response.json()
                self.assert_json_contains(data, "success", "Update response contains success")
                self.assert_json_contains(data, "settings", "Update response contains settings")

            # Test GET endpoint
            response = requests.get(f"{BASE_URL}/v3/api/test-prep/settings", params={"user_id": self.test_user_id})
            self.assert_status_code(response, 200, "GET /v3/api/test-prep/settings")

            if response.status_code == 200:
                data = response.json()
                self.assert_json_contains(data, "settings", "GET response contains settings")
                self.assert_json_contains(data, "progress", "GET response contains progress")

                if data['settings']['toefl_enabled'] == True:
                    self.log("✓ TOEFL correctly enabled after initial setup")
                    self.passed += 1
                else:
                    self.log("✗ TOEFL should be enabled but is not")
                    self.failed += 1

            # Test disabling TOEFL (the bug scenario)
            disable_data = {
                "user_id": self.test_user_id,
                "toefl_enabled": False
            }
            response = requests.put(f"{BASE_URL}/v3/api/test-prep/settings", json=disable_data)
            self.assert_status_code(response, 200, "PUT /v3/api/test-prep/settings - disable TOEFL")

            if response.status_code == 200:
                data = response.json()
                if data['settings']['toefl_enabled'] == False:
                    self.log("✓ TOEFL correctly disabled")
                    self.passed += 1
                else:
                    self.log("✗ TOEFL should be disabled but is still enabled (BUG!)")
                    self.failed += 1

            # Verify with GET that TOEFL is disabled
            response = requests.get(f"{BASE_URL}/v3/api/test-prep/settings", params={"user_id": self.test_user_id})
            if response.status_code == 200:
                data = response.json()
                if data['settings']['toefl_enabled'] == False:
                    self.log("✓ GET confirms TOEFL is disabled")
                    self.passed += 1
                else:
                    self.log("✗ GET shows TOEFL still enabled (BUG!)")
                    self.failed += 1

            # Test re-enabling
            enable_data = {
                "user_id": self.test_user_id,
                "toefl_enabled": True
            }
            response = requests.put(f"{BASE_URL}/v3/api/test-prep/settings", json=enable_data)
            if response.status_code == 200:
                data = response.json()
                if data['settings']['toefl_enabled'] == True:
                    self.log("✓ TOEFL correctly re-enabled")
                    self.passed += 1
                else:
                    self.log("✗ TOEFL should be enabled but is not")
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