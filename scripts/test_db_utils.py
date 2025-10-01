#!/usr/bin/env python3
"""
Integration test for database utility functions
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

import json
import requests
import uuid
from datetime import datetime
import time

BASE_URL = "http://localhost:5000"

def test_save_word():
    """Test saving a word using the new db utilities"""
    test_user_id = str(uuid.uuid4())
    
    # Save a word
    response = requests.post(
        f"{BASE_URL}/save",
        json={
            "user_id": test_user_id,
            "word": "test_word_" + str(int(time.time())),
            "learning_language": "en",
            "native_language": "zh"
        }
    )
    
    if response.status_code == 201:
        print("✅ Save word test passed")
        return test_user_id, response.json()["word_id"]
    else:
        print(f"❌ Save word test failed: {response.status_code} - {response.text}")
        return None, None

def test_delete_word(user_id, word_id):
    """Test deleting a word using the new db utilities"""
    if not user_id or not word_id:
        print("⚠️ Skipping delete test - no word to delete")
        return
    
    response = requests.post(
        f"{BASE_URL}/v2/unsave",
        json={
            "user_id": user_id,
            "word_id": word_id
        }
    )
    
    if response.status_code == 200:
        print("✅ Delete word test passed")
    else:
        print(f"❌ Delete word test failed: {response.status_code} - {response.text}")

def test_get_next_review_word():
    """Test getting next review word using new db utilities"""
    test_user_id = str(uuid.uuid4())
    
    # First save a word
    word_name = "review_test_" + str(int(time.time()))
    save_response = requests.post(
        f"{BASE_URL}/save",
        json={
            "user_id": test_user_id,
            "word": word_name,
            "learning_language": "en",
            "native_language": "zh"
        }
    )
    
    if save_response.status_code != 201:
        print(f"❌ Could not save word for review test: {save_response.text}")
        return
    
    # Get next review word
    response = requests.get(
        f"{BASE_URL}/v2/review_next",
        params={"user_id": test_user_id}
    )
    
    if response.status_code == 200:
        data = response.json()
        if data["count"] > 0 and data["saved_words"][0]["word"] == word_name:
            print("✅ Get next review word test passed")
        else:
            print(f"❌ Get next review word test failed: unexpected response {data}")
    else:
        print(f"❌ Get next review word test failed: {response.status_code} - {response.text}")

def test_submit_review():
    """Test submitting a review using new db utilities"""
    test_user_id = str(uuid.uuid4())
    
    # First save a word
    word_name = "submit_review_test_" + str(int(time.time()))
    save_response = requests.post(
        f"{BASE_URL}/save",
        json={
            "user_id": test_user_id,
            "word": word_name,
            "learning_language": "en",
            "native_language": "zh"
        }
    )
    
    if save_response.status_code != 201:
        print(f"❌ Could not save word for submit review test: {save_response.text}")
        return
    
    word_id = save_response.json()["word_id"]
    
    # Submit a review
    response = requests.post(
        f"{BASE_URL}/reviews/submit",
        json={
            "user_id": test_user_id,
            "word_id": word_id,
            "response": True  # Correct response (boolean)
        }
    )
    
    if response.status_code == 200:
        print("✅ Submit review test passed")
    else:
        print(f"❌ Submit review test failed: {response.status_code} - {response.text}")

def test_submit_feedback():
    """Test submitting feedback using new db utilities"""
    test_user_id = str(uuid.uuid4())
    
    response = requests.post(
        f"{BASE_URL}/feedback",
        json={
            "user_id": test_user_id,
            "feedback": "Test feedback from integration test"
        }
    )
    
    if response.status_code == 201:
        print("✅ Submit feedback test passed")
    else:
        print(f"❌ Submit feedback test failed: {response.status_code} - {response.text}")

def main():
    print("\n🧪 Testing Database Utility Functions\n")
    print("=" * 40)
    
    # Run tests
    user_id, word_id = test_save_word()
    test_delete_word(user_id, word_id)
    test_get_next_review_word()
    test_submit_review()
    test_submit_feedback()
    
    print("\n" + "=" * 40)
    print("✨ Database utility integration tests complete!\n")

if __name__ == "__main__":
    main()