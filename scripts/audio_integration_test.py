#!/usr/bin/env python3
"""
Integration tests for the new audio functionality in the dictionary API.
Tests the new /audio/<text>/<language> endpoint with text+language based audio storage.
"""

import requests
import base64
import json
import psycopg2
from psycopg2.extras import RealDictCursor
import os
import sys
import time
import urllib.parse

# Configuration
API_BASE_URL = "http://localhost:5000"
DATABASE_URL = 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary'

def get_db_connection():
    """Get database connection"""
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)

def test_audio_endpoint_basic():
    """Test basic functionality of the new audio endpoint"""
    print("🧪 Testing basic audio endpoint functionality...")
    
    text = "hello"
    language = "en"
    
    response = requests.get(f"{API_BASE_URL}/audio/{text}/{language}")
    
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    
    data = response.json()
    
    # Verify response structure
    assert "audio_data" in data, "Response missing 'audio_data' field"
    assert "content_type" in data, "Response missing 'content_type' field"
    assert "created_at" in data, "Response missing 'created_at' field"
    
    # Verify content
    assert data["content_type"] == "audio/mpeg", f"Expected audio/mpeg, got {data['content_type']}"
    assert len(data["audio_data"]) > 0, "Audio data is empty"
    
    # Verify audio data is valid base64
    try:
        audio_bytes = base64.b64decode(data["audio_data"])
        assert len(audio_bytes) > 1000, "Audio data seems too small"
        print(f"✅ Audio data decoded successfully: {len(audio_bytes)} bytes")
    except Exception as e:
        assert False, f"Failed to decode audio data: {e}"
    
    print(f"✅ Audio endpoint basic test passed for '{text}' in '{language}'")
    return data

def test_audio_caching_new_system():
    """Test that audio is cached using the new text+language primary key system"""
    print("🧪 Testing audio caching with new system...")
    
    text = "world"
    language = "en"
    
    # Clear any existing cache
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("DELETE FROM audio WHERE text_content = %s AND language = %s", (text, language))
    conn.commit()
    conn.close()
    
    # First request - should generate and cache audio
    response1 = requests.get(f"{API_BASE_URL}/audio/{text}/{language}")
    assert response1.status_code == 200
    data1 = response1.json()
    
    # Check if it was generated (indicated by 'generated' field)
    generated1 = data1.get("generated", False)
    print(f"First request - generated: {generated1}")
    assert generated1 == True, "First request should generate new audio after cache clear"
    
    audio1_data = data1["audio_data"]
    created_at1 = data1["created_at"]
    
    # Second request - should return cached audio
    time.sleep(0.1)  # Small delay to ensure different timestamps if regenerated
    response2 = requests.get(f"{API_BASE_URL}/audio/{text}/{language}")
    assert response2.status_code == 200
    data2 = response2.json()
    
    generated2 = data2.get("generated", False)
    audio2_data = data2["audio_data"]
    created_at2 = data2["created_at"]
    
    # Audio should be identical (cached)
    assert audio1_data == audio2_data, "Cached audio should be identical to original"
    
    # Parse timestamps and check they're very close (within 1 second - should be identical for cached)
    from datetime import datetime
    ts1 = datetime.fromisoformat(created_at1)
    ts2 = datetime.fromisoformat(created_at2)
    time_diff = abs((ts1 - ts2).total_seconds())
    assert time_diff < 1.0, f"Timestamps should be nearly identical for cached requests, diff: {time_diff}s"
    
    assert generated2 == False, "Second request should be from cache (generated: False)"
    
    print(f"Second request - generated: {generated2}, audio matches: {audio1_data == audio2_data}, time diff: {time_diff:.6f}s")
    
    print("✅ Audio caching working correctly with new system")

def test_database_audio_storage_new_schema():
    """Test that audio is properly stored in the new database schema"""
    print("🧪 Testing database audio storage with new schema...")
    
    text = "database_test"
    language = "en"
    
    # Make request
    response = requests.get(f"{API_BASE_URL}/audio/{text}/{language}")
    assert response.status_code == 200
    
    # Check database with new schema
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT text_content, language, audio_data, content_type, created_at
        FROM audio 
        WHERE text_content = %s AND language = %s
    """, (text, language))
    
    result = cur.fetchone()
    conn.close()
    
    assert result is not None, f"Audio for '{text}' in '{language}' not found in database"
    assert result["text_content"] == text, "Text content doesn't match"
    assert result["language"] == language, "Language doesn't match"
    assert result["audio_data"] is not None, "Audio data not stored in database"
    assert result["content_type"] == "audio/mpeg", "Incorrect audio content type"
    assert result["created_at"] is not None, "Creation timestamp not set"
    
    print(f"✅ Audio properly stored in database for '{text}' in '{language}'")

def test_url_encoding():
    """Test that text with special characters is properly handled via URL encoding"""
    print("🧪 Testing URL encoding for special characters...")
    
    # Text with spaces and special characters
    text = "hello world!"
    language = "en"
    
    # URL encode the text
    encoded_text = urllib.parse.quote(text, safe='')
    
    response = requests.get(f"{API_BASE_URL}/audio/{encoded_text}/{language}")
    assert response.status_code == 200
    
    data = response.json()
    assert "audio_data" in data
    
    # Check database to ensure original text is stored
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT text_content FROM audio WHERE text_content = %s AND language = %s", (text, language))
    result = cur.fetchone()
    conn.close()
    
    assert result is not None, "URL encoded text not found in database"
    assert result["text_content"] == text, "Original text not properly stored"
    
    print("✅ URL encoding handled correctly")

def test_different_languages():
    """Test audio generation for different languages"""
    print("🧪 Testing different language support...")
    
    test_cases = [
        ("hello", "en"),
        ("bonjour", "fr"),
        ("hola", "es"),
    ]
    
    for text, language in test_cases:
        response = requests.get(f"{API_BASE_URL}/audio/{text}/{language}")
        assert response.status_code == 200, f"Failed for {text} in {language}"
        
        data = response.json()
        assert "audio_data" in data, f"No audio data for {text} in {language}"
        
        # Verify it's stored in database with correct language
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT language FROM audio WHERE text_content = %s AND language = %s", (text, language))
        result = cur.fetchone()
        conn.close()
        
        assert result is not None, f"Audio not stored for {text} in {language}"
        assert result["language"] == language, f"Language mismatch for {text}"
        
        print(f"✅ Audio generated and stored for '{text}' in '{language}'")

def test_audio_error_handling():
    """Test error handling for the audio endpoint"""
    print("🧪 Testing audio endpoint error handling...")
    
    # Test empty text (should be handled by URL routing)
    response = requests.get(f"{API_BASE_URL}/audio//en")
    assert response.status_code == 404, "Empty text should return 404"
    
    # Test empty language
    response = requests.get(f"{API_BASE_URL}/audio/hello/")
    assert response.status_code == 404, "Empty language should return 404"
    
    print("✅ Audio error handling working correctly")

def run_all_tests():
    """Run all audio integration tests"""
    print("🚀 Starting New Audio System Integration Tests")
    print("=" * 60)
    
    try:
        # Wait for service
        print("Waiting for service to be ready...")
        for i in range(10):
            try:
                response = requests.get(f"{API_BASE_URL}/health", timeout=5)
                if response.status_code == 200:
                    print("✅ Service is ready!")
                    break
            except:
                pass
            time.sleep(2)
        else:
            raise Exception("Service not available")
        
        # Run all tests
        test_audio_endpoint_basic()
        test_audio_caching_new_system()
        test_database_audio_storage_new_schema()
        test_url_encoding()
        test_different_languages()
        test_audio_error_handling()
        
        print("=" * 60)
        print("🎉 All New Audio System Integration Tests PASSED!")
        return True
        
    except AssertionError as e:
        print(f"❌ Test FAILED: {e}")
        return False
    except Exception as e:
        print(f"💥 Unexpected error: {e}")
        return False

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)