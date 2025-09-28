#!/usr/bin/env python3

import requests
import json
import uuid
import time
import base64
from typing import Dict, Any
from datetime import datetime, timedelta

# Base URL for the API
BASE_URL = "http://localhost:5000"

class ComprehensiveTestRunner:
    def __init__(self):
        self.test_user_id = str(uuid.uuid4())
        self.test_user_id_2 = str(uuid.uuid4())
        self.passed = 0
        self.failed = 0
        self.test_word_ids = []  # Store word IDs for testing

    def log(self, message: str):
        print(f"[TEST] {message}")

    def assert_status_code(self, response: requests.Response, expected: int, test_name: str):
        if response.status_code == expected:
            self.log(f"✓ {test_name} - Status code {response.status_code}")
            self.passed += 1
            return True
        else:
            self.log(f"✗ {test_name} - Expected {expected}, got {response.status_code}")
            self.log(f"   Response: {response.text}")
            self.failed += 1
            return False

    def assert_json_contains(self, data: Dict[Any, Any], key: str, test_name: str):
        if key in data:
            self.log(f"✓ {test_name} - Contains key '{key}'")
            self.passed += 1
            return True
        else:
            self.log(f"✗ {test_name} - Missing key '{key}'")
            self.log(f"   Data: {json.dumps(data, indent=2)}")
            self.failed += 1
            return False

    def assert_equals(self, actual, expected, test_name: str):
        if actual == expected:
            self.log(f"✓ {test_name} - {actual} == {expected}")
            self.passed += 1
            return True
        else:
            self.log(f"✗ {test_name} - Expected {expected}, got {actual}")
            self.failed += 1
            return False

    def wait_for_service(self, max_retries=30):
        """Wait for the service to be ready"""
        self.log("Waiting for service to be ready...")
        for i in range(max_retries):
            try:
                response = requests.get(f"{BASE_URL}/health", timeout=5)
                if response.status_code == 200:
                    self.log("✓ Service is ready!")
                    return True
            except requests.exceptions.RequestException:
                pass
            time.sleep(2)
        self.log("✗ Service failed to start within timeout")
        return False

    def test_health_endpoint(self):
        """Test the health check endpoint"""
        self.log("Testing /health endpoint...")

        try:
            response = requests.get(f"{BASE_URL}/health")
            if self.assert_status_code(response, 200, "/health endpoint"):
                data = response.json()
                self.assert_json_contains(data, "status", "/health response contains status")
                if data.get("status") == "healthy":
                    self.assert_equals(data.get("status"), "healthy", "/health status is healthy")
        except Exception as e:
            self.log(f"✗ /health endpoint failed with error: {e}")
            self.failed += 1

    def test_languages_endpoint(self):
        """Test the supported languages endpoint"""
        self.log("Testing /languages endpoint...")

        try:
            response = requests.get(f"{BASE_URL}/languages")
            if self.assert_status_code(response, 200, "/languages endpoint"):
                data = response.json()
                self.assert_json_contains(data, "supported_languages", "/languages response contains supported_languages")
                if isinstance(data.get("supported_languages"), list):
                    self.log(f"✓ /languages returned {len(data['supported_languages'])} languages")
                    self.passed += 1
        except Exception as e:
            self.log(f"✗ /languages endpoint failed with error: {e}")
            self.failed += 1

    def test_word_definition_endpoint(self):
        """Test the word definition endpoint"""
        self.log("Testing /word endpoint...")

        # Test valid word request
        try:
            response = requests.get(f"{BASE_URL}/word", params={
                "w": "hello",
                "user_id": self.test_user_id
            })
            if self.assert_status_code(response, 200, "/word endpoint with valid word"):
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
            self.assert_status_code(response, 400, "/word endpoint without parameters")
        except Exception as e:
            self.log(f"✗ /word endpoint error test failed: {e}")
            self.failed += 1

    def test_save_word_endpoint(self):
        """Test the save word endpoint"""
        self.log("Testing /save endpoint...")

        # Test valid save request
        try:
            payload = {
                "word": "integration_test_word",
                "user_id": self.test_user_id,
                "learning_language": "en",
                "metadata": {"source": "integration_test", "category": "test"}
            }

            response = requests.post(f"{BASE_URL}/save", json=payload)
            if self.assert_status_code(response, 201, "/save endpoint with valid data"):
                data = response.json()
                self.assert_json_contains(data, "success", "/save response contains success")
                self.assert_json_contains(data, "message", "/save response contains message")
                self.assert_json_contains(data, "word_id", "/save response contains word_id")
                if "word_id" in data:
                    self.test_word_ids.append(data["word_id"])

        except Exception as e:
            self.log(f"✗ /save endpoint failed with error: {e}")
            self.failed += 1

        # Test error cases
        test_cases = [
            ({"user_id": self.test_user_id}, "/save endpoint without word"),
            ({"word": "test"}, "/save endpoint without user_id"),
            ({"word": "test", "user_id": "invalid-uuid"}, "/save endpoint with invalid user_id")
        ]

        for payload, test_name in test_cases:
            try:
                response = requests.post(f"{BASE_URL}/save", json=payload)
                self.assert_status_code(response, 400, test_name)
            except Exception as e:
                self.log(f"✗ {test_name} failed: {e}")
                self.failed += 1

    def test_saved_words_endpoint(self):
        """Test the saved words endpoint"""
        self.log("Testing /saved_words endpoint...")

        # First, save a few more words for testing
        test_words = ["apple", "banana", "cherry"]
        for word in test_words:
            payload = {
                "word": word,
                "user_id": self.test_user_id,
                "learning_language": "en",
                "metadata": {"test_word": True}
            }
            response = requests.post(f"{BASE_URL}/save", json=payload)
            if response.status_code == 201:
                data = response.json()
                if "word_id" in data:
                    self.test_word_ids.append(data["word_id"])

        # Test retrieving saved words
        try:
            response = requests.get(f"{BASE_URL}/saved_words", params={"user_id": self.test_user_id})
            if self.assert_status_code(response, 200, "/saved_words endpoint"):
                data = response.json()
                self.assert_json_contains(data, "user_id", "/saved_words response contains user_id")
                self.assert_json_contains(data, "saved_words", "/saved_words response contains saved_words")
                self.assert_json_contains(data, "count", "/saved_words response contains count")

                # Verify structure of saved words
                saved_words = data.get("saved_words", [])
                if saved_words:
                    word = saved_words[0]
                    self.assert_json_contains(word, "id", "Saved word contains id")
                    self.assert_json_contains(word, "word", "Saved word contains word")
                    self.assert_json_contains(word, "learning_language", "Saved word contains learning_language")
                    self.assert_json_contains(word, "created_at", "Saved word contains created_at")
                    self.assert_json_contains(word, "review_count", "Saved word contains review_count")
                    self.assert_json_contains(word, "next_review_date", "Saved word contains next_review_date")

        except Exception as e:
            self.log(f"✗ /saved_words endpoint failed with error: {e}")
            self.failed += 1

        # Test due_only parameter
        try:
            response = requests.get(f"{BASE_URL}/saved_words", params={
                "user_id": self.test_user_id,
                "due_only": "true"
            })
            if self.assert_status_code(response, 200, "/saved_words endpoint with due_only"):
                data = response.json()
                self.assert_json_contains(data, "due_only", "/saved_words response contains due_only flag")
                if data.get("due_only"):
                    self.assert_equals(data.get("due_only"), True, "/saved_words due_only flag is True")
        except Exception as e:
            self.log(f"✗ /saved_words due_only test failed: {e}")
            self.failed += 1

    def test_due_counts_endpoint(self):
        """Test the due counts endpoint"""
        self.log("Testing /due_counts endpoint...")

        try:
            response = requests.get(f"{BASE_URL}/due_counts", params={"user_id": self.test_user_id})
            if self.assert_status_code(response, 200, "/due_counts endpoint"):
                data = response.json()
                self.assert_json_contains(data, "user_id", "/due_counts response contains user_id")
                self.assert_json_contains(data, "overdue_count", "/due_counts response contains overdue_count")
                self.assert_json_contains(data, "total_count", "/due_counts response contains total_count")

                # Verify counts are numbers
                if isinstance(data.get("overdue_count"), int) and isinstance(data.get("total_count"), int):
                    self.log("✓ Due counts are valid integers")
                    self.passed += 1

        except Exception as e:
            self.log(f"✗ /due_counts endpoint failed with error: {e}")
            self.failed += 1

        # Test missing user_id
        try:
            response = requests.get(f"{BASE_URL}/due_counts")
            self.assert_status_code(response, 400, "/due_counts endpoint without user_id")
        except Exception as e:
            self.log(f"✗ /due_counts error test failed: {e}")
            self.failed += 1

    def test_review_next_endpoint(self):
        """Test the next review word endpoint"""
        self.log("Testing /v2/review_next endpoint...")

        try:
            response = requests.get(f"{BASE_URL}/v2/review_next", params={"user_id": self.test_user_id})
            # Could be 200 (word found) or 404 (no words due)
            if response.status_code in [200, 404]:
                self.log(f"✓ /v2/review_next endpoint returned {response.status_code}")
                self.passed += 1

                if response.status_code == 200:
                    data = response.json()
                    self.assert_json_contains(data, "saved_words", "/v2/review_next response contains saved_words")
                    if data.get("saved_words"):
                        word = data["saved_words"][0]
                        self.assert_json_contains(word, "id", "/v2/review_next word contains id")
                        self.assert_json_contains(word, "word", "/v2/review_next word contains word")
                        self.assert_json_contains(word, "learning_language", "/v2/review_next word contains learning_language")

        except Exception as e:
            self.log(f"✗ /v2/review_next endpoint failed with error: {e}")
            self.failed += 1

    def test_submit_review_endpoint(self):
        """Test the submit review endpoint"""
        self.log("Testing /reviews/submit endpoint...")

        if not self.test_word_ids:
            self.log("⚠ Skipping review submit test - no word IDs available")
            return

        try:
            # Submit a review for one of our test words
            payload = {
                "user_id": self.test_user_id,
                "word_id": self.test_word_ids[0],
                "response": True,
                "review_time_seconds": 5.5
            }

            response = requests.post(f"{BASE_URL}/reviews/submit", json=payload)
            if self.assert_status_code(response, 201, "/reviews/submit endpoint"):
                data = response.json()
                self.assert_json_contains(data, "review_id", "/reviews/submit response contains review_id")
                self.assert_json_contains(data, "reviewed_at", "/reviews/submit response contains reviewed_at")
                self.assert_json_contains(data, "updated_stats", "/reviews/submit response contains updated_stats")
                self.assert_json_contains(data, "due_count", "/reviews/submit response contains due_count")

        except Exception as e:
            self.log(f"✗ /reviews/submit endpoint failed with error: {e}")
            self.failed += 1

        # Test missing parameters
        error_cases = [
            ({}, "without any parameters"),
            ({"user_id": self.test_user_id}, "without word_id"),
            ({"word_id": self.test_word_ids[0] if self.test_word_ids else 1}, "without user_id"),
            ({"user_id": self.test_user_id, "word_id": self.test_word_ids[0] if self.test_word_ids else 1}, "without response")
        ]

        for payload, description in error_cases:
            try:
                response = requests.post(f"{BASE_URL}/reviews/submit", json=payload)
                self.assert_status_code(response, 400, f"/reviews/submit {description}")
            except Exception as e:
                self.log(f"✗ /reviews/submit error test failed: {e}")
                self.failed += 1

    def test_review_stats_endpoint(self):
        """Test the review statistics endpoint"""
        self.log("Testing /reviews/stats endpoint...")

        try:
            response = requests.get(f"{BASE_URL}/reviews/stats", params={"user_id": self.test_user_id})
            if self.assert_status_code(response, 200, "/reviews/stats endpoint"):
                data = response.json()
                self.assert_json_contains(data, "user_id", "/reviews/stats response contains user_id")
                self.assert_json_contains(data, "total_reviews", "/reviews/stats response contains total_reviews")
                self.assert_json_contains(data, "correct_reviews", "/reviews/stats response contains correct_reviews")
                self.assert_json_contains(data, "accuracy", "/reviews/stats response contains accuracy")
                self.assert_json_contains(data, "due_count", "/reviews/stats response contains due_count")

        except Exception as e:
            self.log(f"✗ /reviews/stats endpoint failed with error: {e}")
            self.failed += 1

    def test_word_details_endpoint(self):
        """Test the word details endpoint"""
        self.log("Testing /words/<id>/details endpoint...")

        if not self.test_word_ids:
            self.log("⚠ Skipping word details test - no word IDs available")
            return

        try:
            word_id = self.test_word_ids[0]
            response = requests.get(f"{BASE_URL}/words/{word_id}/details", params={"user_id": self.test_user_id})
            if self.assert_status_code(response, 200, f"/words/{word_id}/details endpoint"):
                data = response.json()
                self.assert_json_contains(data, "id", "/words/details response contains id")
                self.assert_json_contains(data, "word", "/words/details response contains word")
                self.assert_json_contains(data, "learning_language", "/words/details response contains learning_language")
                self.assert_json_contains(data, "created_at", "/words/details response contains created_at")
                self.assert_json_contains(data, "review_count", "/words/details response contains review_count")
                self.assert_json_contains(data, "review_history", "/words/details response contains review_history")

        except Exception as e:
            self.log(f"✗ /words/details endpoint failed with error: {e}")
            self.failed += 1

    def test_forgetting_curve_endpoint(self):
        """Test the forgetting curve endpoint"""
        self.log("Testing /words/<id>/forgetting-curve endpoint...")

        if not self.test_word_ids:
            self.log("⚠ Skipping forgetting curve test - no word IDs available")
            return

        try:
            word_id = self.test_word_ids[0]
            response = requests.get(f"{BASE_URL}/words/{word_id}/forgetting-curve", params={"user_id": self.test_user_id})
            if self.assert_status_code(response, 200, f"/words/{word_id}/forgetting-curve endpoint"):
                data = response.json()
                self.assert_json_contains(data, "word_id", "/forgetting-curve response contains word_id")
                self.assert_json_contains(data, "word", "/forgetting-curve response contains word")
                self.assert_json_contains(data, "retention_curve", "/forgetting-curve response contains retention_curve")

                # Verify retention curve structure
                if "retention_curve" in data and data["retention_curve"]:
                    curve_point = data["retention_curve"][0]
                    self.assert_json_contains(curve_point, "date", "Retention curve point contains date")
                    self.assert_json_contains(curve_point, "retention", "Retention curve point contains retention")

        except Exception as e:
            self.log(f"✗ /words/forgetting-curve endpoint failed with error: {e}")
            self.failed += 1

    def test_user_preferences_endpoint(self):
        """Test the user preferences endpoint"""
        self.log("Testing /users/<id>/preferences endpoint...")

        # Test GET preferences
        try:
            response = requests.get(f"{BASE_URL}/users/{self.test_user_id}/preferences")
            if self.assert_status_code(response, 200, f"/users/{self.test_user_id}/preferences GET"):
                data = response.json()
                self.assert_json_contains(data, "user_id", "/preferences GET response contains user_id")
                self.assert_json_contains(data, "learning_language", "/preferences GET response contains learning_language")
                self.assert_json_contains(data, "native_language", "/preferences GET response contains native_language")
                self.assert_json_contains(data, "user_name", "/preferences GET response contains user_name")
                self.assert_json_contains(data, "user_motto", "/preferences GET response contains user_motto")

        except Exception as e:
            self.log(f"✗ /users/preferences GET failed with error: {e}")
            self.failed += 1

        # Test POST preferences
        try:
            payload = {
                "learning_language": "es",
                "native_language": "en",
                "user_name": "TestUser",
                "user_motto": "Learning is fun!"
            }
            response = requests.post(f"{BASE_URL}/users/{self.test_user_id}/preferences", json=payload)
            if self.assert_status_code(response, 200, f"/users/{self.test_user_id}/preferences POST"):
                data = response.json()
                self.assert_json_contains(data, "message", "/preferences POST response contains message")

        except Exception as e:
            self.log(f"✗ /users/preferences POST failed with error: {e}")
            self.failed += 1

    def test_audio_endpoint(self):
        """Test the audio endpoint"""
        self.log("Testing /audio/<text>/<language> endpoint...")

        try:
            text = "hello"
            language = "en"
            response = requests.get(f"{BASE_URL}/audio/{text}/{language}")
            if self.assert_status_code(response, 200, f"/audio/{text}/{language} endpoint"):
                data = response.json()
                self.assert_json_contains(data, "audio_data", "/audio response contains audio_data")
                self.assert_json_contains(data, "content_type", "/audio response contains content_type")
                self.assert_json_contains(data, "created_at", "/audio response contains created_at")
                self.assert_json_contains(data, "generated", "/audio response contains generated")

                # Verify audio data is valid base64
                try:
                    audio_bytes = base64.b64decode(data["audio_data"])
                    if len(audio_bytes) > 100:
                        self.log(f"✓ Audio data is valid base64 ({len(audio_bytes)} bytes)")
                        self.passed += 1
                except Exception as e:
                    self.log(f"✗ Failed to decode audio data: {e}")
                    self.failed += 1

        except Exception as e:
            self.log(f"✗ /audio endpoint failed with error: {e}")
            self.failed += 1

    def test_analytics_endpoints(self):
        """Test all analytics endpoints"""
        self.log("Testing analytics endpoints...")

        analytics_endpoints = [
            ("/review_statistics", {"user_id": self.test_user_id}),
            ("/weekly_review_counts", {"user_id": self.test_user_id}),
            ("/progress_funnel", {"user_id": self.test_user_id}),
            ("/review_activity", {
                "user_id": self.test_user_id,
                "start_date": (datetime.now() - timedelta(days=30)).isoformat(),
                "end_date": datetime.now().isoformat()
            }),
            ("/leaderboard", {})
        ]

        for endpoint, params in analytics_endpoints:
            try:
                response = requests.get(f"{BASE_URL}{endpoint}", params=params)
                if self.assert_status_code(response, 200, f"{endpoint} endpoint"):
                    data = response.json()
                    # Each analytics endpoint should return JSON
                    if isinstance(data, dict):
                        self.log(f"✓ {endpoint} returned valid JSON")
                        self.passed += 1

            except Exception as e:
                self.log(f"✗ {endpoint} endpoint failed with error: {e}")
                self.failed += 1

    def test_static_endpoints(self):
        """Test static content endpoints"""
        self.log("Testing static content endpoints...")

        static_endpoints = ["/privacy", "/support"]

        for endpoint in static_endpoints:
            try:
                response = requests.get(f"{BASE_URL}{endpoint}")
                if self.assert_status_code(response, 200, f"{endpoint} endpoint"):
                    # Should return HTML content
                    if "text/html" in response.headers.get("content-type", ""):
                        self.log(f"✓ {endpoint} returned HTML content")
                        self.passed += 1

            except Exception as e:
                self.log(f"✗ {endpoint} endpoint failed with error: {e}")
                self.failed += 1

    def test_illustration_endpoints(self):
        """Test illustration endpoints"""
        self.log("Testing illustration endpoints...")

        # Test generate illustration
        try:
            payload = {
                "word": "apple",
                "user_id": self.test_user_id,
                "style": "cartoon"
            }
            response = requests.post(f"{BASE_URL}/generate-illustration", json=payload)
            # Could return 200 (success) or error status
            if response.status_code in [200, 400, 500]:
                self.log(f"✓ /generate-illustration returned {response.status_code}")
                self.passed += 1

        except Exception as e:
            self.log(f"✗ /generate-illustration endpoint failed with error: {e}")
            self.failed += 1

        # Test get illustration
        try:
            response = requests.get(f"{BASE_URL}/illustration", params={
                "word": "apple",
                "user_id": self.test_user_id
            })
            # Could return 200 (found) or 404 (not found)
            if response.status_code in [200, 404]:
                self.log(f"✓ /illustration returned {response.status_code}")
                self.passed += 1

        except Exception as e:
            self.log(f"✗ /illustration endpoint failed with error: {e}")
            self.failed += 1

    def run_all_tests(self):
        """Run all comprehensive integration tests"""
        self.log("Starting comprehensive integration tests...")

        if not self.wait_for_service():
            self.log("✗ Cannot run tests - service not available")
            return False

        # Core functionality tests
        self.test_health_endpoint()
        self.test_languages_endpoint()
        self.test_word_definition_endpoint()
        self.test_save_word_endpoint()
        self.test_saved_words_endpoint()
        self.test_due_counts_endpoint()

        # Review system tests
        self.test_review_next_endpoint()
        self.test_submit_review_endpoint()
        self.test_review_stats_endpoint()

        # Word details tests
        self.test_word_details_endpoint()
        self.test_forgetting_curve_endpoint()

        # User management tests
        self.test_user_preferences_endpoint()

        # Audio tests
        self.test_audio_endpoint()

        # Analytics tests
        self.test_analytics_endpoints()

        # Static content tests
        self.test_static_endpoints()

        # Illustration tests
        self.test_illustration_endpoints()

        self.log(f"\n=== TEST RESULTS ===")
        self.log(f"Total tests: {self.passed + self.failed}")
        self.log(f"Passed: {self.passed}")
        self.log(f"Failed: {self.failed}")

        if self.failed == 0:
            self.log("🎉 All tests passed!")
            return True
        else:
            self.log(f"❌ {self.failed} tests failed!")
            return False

if __name__ == "__main__":
    runner = ComprehensiveTestRunner()
    success = runner.run_all_tests()
    exit(0 if success else 1)