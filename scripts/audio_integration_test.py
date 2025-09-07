#!/usr/bin/env python3
"""
Integration tests for audio functionality in the dictionary API.
Tests TTS generation, caching, and response format.
"""

import requests
import base64
import json
import psycopg2
from psycopg2.extras import RealDictCursor
import os
from dotenv import load_dotenv
import sys

# Load environment variables
load_dotenv('.env.secrets')

# Configuration
API_BASE_URL = "http://localhost:5000"
DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')

def get_db_connection():
    """Get database connection"""
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)

def test_word_with_audio():
    """Test that /word endpoint returns audio data for a word"""
    print("🧪 Testing /word endpoint with audio generation...")
    
    test_word = "hello"
    response = requests.get(f"{API_BASE_URL}/word", params={"w": test_word})
    
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    
    data = response.json()
    
    # Verify basic response structure
    assert "word" in data, "Response missing 'word' field"
    assert "phonetic" in data, "Response missing 'phonetic' field"
    assert "definitions" in data, "Response missing 'definitions' field"
    assert "_cache_info" in data, "Response missing '_cache_info' field"
    
    # Verify audio data is present
    assert "audio" in data, "Response missing 'audio' field"
    audio = data["audio"]
    
    assert "data" in audio, "Audio missing 'data' field"
    assert "content_type" in audio, "Audio missing 'content_type' field"
    assert "generated_at" in audio, "Audio missing 'generated_at' field"
    
    # Verify audio content
    assert audio["content_type"] == "audio/mpeg", f"Expected audio/mpeg, got {audio['content_type']}"
    assert len(audio["data"]) > 0, "Audio data is empty"
    
    # Verify audio data is valid base64
    try:
        audio_bytes = base64.b64decode(audio["data"])
        assert len(audio_bytes) > 1000, "Audio data seems too small"
        print(f"✅ Audio data decoded successfully: {len(audio_bytes)} bytes")
    except Exception as e:
        assert False, f"Failed to decode audio data: {e}"
    
    print(f"✅ Word '{test_word}' returned with audio data")
    return data

def test_audio_caching():
    """Test that audio is cached in database and subsequent requests return cached audio"""
    print("🧪 Testing audio caching...")
    
    test_word = "world"
    
    # Clear cache if exists
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("DELETE FROM words WHERE word_lower = %s", (test_word.lower(),))
    conn.commit()
    conn.close()
    
    # First request - should generate audio
    response1 = requests.get(f"{API_BASE_URL}/word", params={"w": test_word})
    assert response1.status_code == 200
    data1 = response1.json()
    
    assert data1["_cache_info"]["cached"] == False, "First request should not be cached"
    assert "audio" in data1, "First request should have audio"
    audio1_data = data1["audio"]["data"]
    
    # Second request - should return cached audio
    response2 = requests.get(f"{API_BASE_URL}/word", params={"w": test_word})
    assert response2.status_code == 200
    data2 = response2.json()
    
    assert data2["_cache_info"]["cached"] == True, "Second request should be cached"
    assert "audio" in data2, "Second request should have cached audio"
    audio2_data = data2["audio"]["data"]
    
    # Audio should be identical
    assert audio1_data == audio2_data, "Cached audio should be identical to original"
    
    print("✅ Audio caching working correctly")

def test_database_audio_storage():
    """Test that audio is properly stored in database"""
    print("🧪 Testing database audio storage...")
    
    test_word = "database"
    
    # Make request
    response = requests.get(f"{API_BASE_URL}/word", params={"w": test_word})
    assert response.status_code == 200
    
    # Check database
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
        SELECT word, audio_data, audio_content_type, audio_generated_at 
        FROM words 
        WHERE word_lower = %s
    """, (test_word.lower(),))
    
    result = cur.fetchone()
    conn.close()
    
    assert result is not None, f"Word '{test_word}' not found in database"
    assert result["audio_data"] is not None, "Audio data not stored in database"
    assert result["audio_content_type"] == "audio/mpeg", "Incorrect audio content type"
    assert result["audio_generated_at"] is not None, "Audio generation timestamp not set"
    
    print(f"✅ Audio properly stored in database for word '{test_word}'")

def test_missing_word_audio():
    """Test behavior when requesting audio for a non-existent word"""
    print("🧪 Testing audio for non-existent word...")
    
    fake_word = "asdfqwerty123nonexistent"
    response = requests.get(f"{API_BASE_URL}/word", params={"w": fake_word})
    
    # API should still return 200 but with generated definition and audio
    assert response.status_code == 200, f"Expected 200, got {response.status_code}"
    
    data = response.json()
    # Should still have audio even for generated definitions
    assert "audio" in data, "Response should have audio even for generated definitions"
    
    print("✅ Non-existent word handled correctly with audio")

def test_audio_error_handling():
    """Test behavior when audio generation fails"""
    print("🧪 Testing audio error handling...")
    
    # Test with empty word (should fail validation)
    response = requests.get(f"{API_BASE_URL}/word", params={"w": ""})
    assert response.status_code == 400, "Empty word should return 400"
    
    print("✅ Audio error handling working correctly")

def run_all_tests():
    """Run all audio integration tests"""
    print("🚀 Starting Audio Integration Tests")
    print("=" * 50)
    
    try:
        # Test basic functionality
        test_word_with_audio()
        
        # Test caching
        test_audio_caching()
        
        # Test database storage
        test_database_audio_storage()
        
        # Test edge cases
        test_missing_word_audio()
        test_audio_error_handling()
        
        print("=" * 50)
        print("🎉 All Audio Integration Tests PASSED!")
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