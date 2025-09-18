#!/usr/bin/env python3
"""
Integration test for pronunciation practice feature
"""

import requests
import json
import base64
import wave
import struct
import sys

BASE_URL = "http://localhost:5000"
TEST_USER_ID = "12345678-1234-1234-1234-123456789012"

def generate_test_audio():
    """Generate a simple WAV file for testing"""
    sample_rate = 44100
    duration = 2
    frequency = 440  # A4 note

    # Generate samples
    samples = []
    for i in range(sample_rate * duration):
        sample = 32767 * 0.5 * struct.unpack('f', struct.pack('f',
            (i * frequency * 2 * 3.14159) / sample_rate))[0]
        samples.append(int(sample))

    # Create WAV file in memory
    wav_data = bytearray()

    # WAV header
    wav_data.extend(b'RIFF')
    wav_data.extend(struct.pack('<I', 36 + len(samples) * 2))
    wav_data.extend(b'WAVE')
    wav_data.extend(b'fmt ')
    wav_data.extend(struct.pack('<I', 16))
    wav_data.extend(struct.pack('<H', 1))  # PCM
    wav_data.extend(struct.pack('<H', 1))  # Mono
    wav_data.extend(struct.pack('<I', sample_rate))
    wav_data.extend(struct.pack('<I', sample_rate * 2))
    wav_data.extend(struct.pack('<H', 2))
    wav_data.extend(struct.pack('<H', 16))  # 16-bit
    wav_data.extend(b'data')
    wav_data.extend(struct.pack('<I', len(samples) * 2))

    # Add samples
    for sample in samples:
        wav_data.extend(struct.pack('<h', sample))

    return bytes(wav_data)

def test_pronunciation_practice():
    """Test pronunciation practice endpoint"""
    print("\n🎤 Testing pronunciation practice endpoint...")

    # Generate test audio
    audio_data = generate_test_audio()
    audio_base64 = base64.b64encode(audio_data).decode('utf-8')

    request_data = {
        "user_id": TEST_USER_ID,
        "original_text": "hello world",
        "audio_data": audio_base64,
        "metadata": {
            "source": "test",
            "language": "en"
        }
    }

    response = requests.post(
        f"{BASE_URL}/pronunciation/practice",
        json=request_data,
        headers={"Content-Type": "application/json"}
    )

    if response.status_code == 200:
        result = response.json()
        print(f"✅ Pronunciation practice successful:")
        print(f"   Result: {result.get('result', 'N/A')}")
        print(f"   Score: {result.get('similarity_score', 'N/A')}")
        print(f"   Recognized: {result.get('recognized_text', 'N/A')}")
        print(f"   Feedback: {result.get('feedback', 'N/A')}")
        return True
    else:
        print(f"❌ Pronunciation practice failed: {response.status_code}")
        print(f"   Response: {response.text}")
        return False

def test_pronunciation_history():
    """Test pronunciation history endpoint"""
    print("\n📊 Testing pronunciation history endpoint...")

    response = requests.get(
        f"{BASE_URL}/pronunciation/history",
        params={"user_id": TEST_USER_ID, "limit": 10}
    )

    if response.status_code == 200:
        data = response.json()
        print(f"✅ History retrieved: {data['count']} records")
        if data['history']:
            record = data['history'][0]
            print(f"   Latest: {record['original_text']} - Result: {record['result']}")
        return True
    else:
        print(f"❌ Failed to get history: {response.status_code}")
        return False

def test_pronunciation_stats():
    """Test pronunciation statistics endpoint"""
    print("\n📈 Testing pronunciation stats endpoint...")

    response = requests.get(
        f"{BASE_URL}/pronunciation/stats",
        params={"user_id": TEST_USER_ID}
    )

    if response.status_code == 200:
        data = response.json()
        stats = data['stats']
        print(f"✅ Statistics retrieved:")
        print(f"   Total attempts: {stats['total_attempts']}")
        print(f"   Successful: {stats['successful_attempts']}")
        print(f"   Success rate: {stats['success_rate']:.2%}")
        print(f"   Average similarity: {stats['average_similarity']:.2f}")
        return True
    else:
        print(f"❌ Failed to get stats: {response.status_code}")
        return False

def main():
    """Run all pronunciation tests"""
    print("🚀 Starting pronunciation feature integration tests...")

    tests = [
        test_pronunciation_practice,
        test_pronunciation_history,
        test_pronunciation_stats
    ]

    results = []
    for test in tests:
        try:
            results.append(test())
        except Exception as e:
            print(f"❌ Test failed with error: {e}")
            results.append(False)

    # Summary
    print("\n" + "="*50)
    passed = sum(results)
    total = len(results)

    if passed == total:
        print(f"✅ All {total} tests passed!")
        return 0
    else:
        print(f"⚠️  {passed}/{total} tests passed")
        return 1

if __name__ == "__main__":
    sys.exit(main())