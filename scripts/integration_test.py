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
            response = requests.get(f"{BASE_URL}/word", params={"w": "hello"})
            self.assert_status_code(response, 200, "/word endpoint with valid word")
            
            data = response.json()
            self.assert_json_contains(data, "word", "/word response contains word")
            self.assert_json_contains(data, "phonetic", "/word response contains phonetic")
            self.assert_json_contains(data, "definitions", "/word response contains definitions")
            self.assert_json_contains(data, "_cache_info", "/word response contains cache info")
            
            # Check cache info (don't assume first request is cache miss since DB persists)
            cache_info = data.get("_cache_info", {})
            if "cached" in cache_info:
                self.log(f"✓ Cache info present - cached: {cache_info.get('cached')}, access_count: {cache_info.get('access_count')}")
                self.passed += 1
            else:
                self.log("✗ Cache info missing")
                self.failed += 1
            
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
                "metadata": {"source": "test", "category": "greeting"}
            }
            
            response = requests.post(f"{BASE_URL}/save", json=payload)
            self.assert_status_code(response, 201, "/save endpoint with valid data")
            
            data = response.json()
            self.assert_json_contains(data, "message", "/save response contains message")
            self.assert_json_contains(data, "id", "/save response contains id")
            self.assert_json_contains(data, "word", "/save response contains word")
            self.assert_json_contains(data, "user_id", "/save response contains user_id")
            self.assert_json_contains(data, "created_at", "/save response contains created_at")
            
        except Exception as e:
            self.log(f"✗ /save endpoint failed with error: {e}")
            self.failed += 1
            
        # Test missing word parameter
        try:
            payload = {"user_id": self.test_user_id}
            response = requests.post(f"{BASE_URL}/save", json=payload)
            self.assert_status_code(response, 400, "/save endpoint without word")
            
        except Exception as e:
            self.log(f"✗ /save endpoint error test failed: {e}")
            self.failed += 1
            
        # Test missing user_id parameter
        try:
            payload = {"word": "test"}
            response = requests.post(f"{BASE_URL}/save", json=payload)
            self.assert_status_code(response, 400, "/save endpoint without user_id")
            
        except Exception as e:
            self.log(f"✗ /save endpoint error test failed: {e}")
            self.failed += 1
            
        # Test invalid user_id format
        try:
            payload = {"word": "test", "user_id": "invalid-uuid"}
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
                "metadata": {"version": 1}
            }
            
            response1 = requests.post(f"{BASE_URL}/save", json=payload1)
            self.assert_status_code(response1, 201, "First save of duplicate word")
            
            # Save the same word again with different metadata
            payload2 = {
                "word": "duplicate_test",
                "user_id": self.test_user_id,
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

    def test_cache_behavior(self):
        """Test caching behavior for word definitions"""
        self.log("Testing cache behavior...")
        
        test_word = "cache_test_word"
        
        try:
            # First request - should be cache miss
            response1 = requests.get(f"{BASE_URL}/word", params={"w": test_word})
            self.assert_status_code(response1, 200, "First request for cache test")
            
            data1 = response1.json()
            cache_info1 = data1.get("_cache_info", {})
            
            if cache_info1.get("cached") == False and cache_info1.get("access_count") == 1:
                self.log("✓ First request is cache miss with access_count=1")
                self.passed += 1
            elif cache_info1.get("cached") == True and cache_info1.get("access_count") > 1:
                self.log(f"✓ Word was already cached (access_count: {cache_info1.get('access_count')})")
                self.passed += 1
            else:
                self.log(f"✗ Unexpected cache state: cached={cache_info1.get('cached')}, access_count={cache_info1.get('access_count')}")
                self.failed += 1
            
            # Second request - should be cache hit
            response2 = requests.get(f"{BASE_URL}/word", params={"w": test_word})
            self.assert_status_code(response2, 200, "Second request for cache test")
            
            data2 = response2.json()
            cache_info2 = data2.get("_cache_info", {})
            
            expected_count = cache_info1.get("access_count", 0) + 1
            if cache_info2.get("cached") == True and cache_info2.get("access_count") == expected_count:
                self.log(f"✓ Second request is cache hit with access_count={expected_count}")
                self.passed += 1
            else:
                self.log(f"✗ Second request cache hit failed: cached={cache_info2.get('cached')}, access_count={cache_info2.get('access_count')}, expected={expected_count}")
                self.failed += 1
                
            # Test case-insensitive caching
            response3 = requests.get(f"{BASE_URL}/word", params={"w": test_word.upper()})
            self.assert_status_code(response3, 200, "Case-insensitive cache test")
            
            data3 = response3.json()
            cache_info3 = data3.get("_cache_info", {})
            
            expected_count_3 = cache_info2.get("access_count", 0) + 1
            if cache_info3.get("cached") == True and cache_info3.get("access_count") == expected_count_3:
                self.log(f"✓ Case-insensitive caching works with access_count={expected_count_3}")
                self.passed += 1
            else:
                self.log(f"✗ Case-insensitive caching failed: cached={cache_info3.get('cached')}, access_count={cache_info3.get('access_count')}, expected={expected_count_3}")
                self.failed += 1
                
        except Exception as e:
            self.log(f"✗ Cache behavior test failed with error: {e}")
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
        self.test_cache_behavior()
        
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