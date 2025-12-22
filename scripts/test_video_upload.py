#!/usr/bin/env python3
"""
Integration test for video batch upload API endpoint.
Tests the fix for the race condition and idempotency of batch_upload_videos.
"""

import requests
import json
import base64
import uuid
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# Base URL for the API
BASE_URL = "http://localhost:5001"
API_PATH = "/v3/admin/videos/batch-upload"

def create_test_video_data(slug: str, duplicate: bool = False):
    """Create a test video data dictionary with base64-encoded video data."""
    # Create a minimal valid MP4 file (just a few bytes that won't play but will satisfy the upload)
    # In a real scenario, you'd use actual video bytes
    test_video_bytes = b'\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom\x00\x00\x00\x08free'

    return {
        "slug": slug,
        "name": slug,
        "format": "mp4",
        "video_data_base64": base64.b64encode(test_video_bytes).decode('utf-8'),
        "size_bytes": len(test_video_bytes),
        "transcript": "Test transcript for video",
        "audio_transcript": "Test audio transcript",
        "audio_transcript_verified": True,
        "whisper_metadata": {
            "segments": [],
            "task": "transcribe"
        },
        "metadata": {
            "duration_seconds": 5,
            "resolution": "1920x1080",
            "test_video": True
        },
        "word_mappings": [
            {
                "word": "test",
                "learning_language": "en",
                "relevance_score": 0.9,
                "transcript_source": "audio",
                "timestamp": 1.0
            }
        ]
    }

def test_basic_upload():
    """Test 1: Basic video upload"""
    print("\n=== Test 1: Basic video upload ===")

    source_id = f"test_{int(time.time())}"
    video_data = create_test_video_data(f"test-video-{uuid.uuid4().hex[:8]}")

    payload = {
        "videos": [video_data],
        "source_id": source_id
    }

    response = requests.post(f"{BASE_URL}{API_PATH}", json=payload)

    print(f"Status Code: {response.status_code}")

    if response.status_code == 200:
        data = response.json()
        print(f"✓ Basic upload succeeded")
        print(f"  Results: {json.dumps(data, indent=2)}")

        # Verify response structure
        assert data["success"] == True, "Expected success=True"
        assert data["total_videos"] == 1, "Expected 1 video"
        assert len(data["results"]) == 1, "Expected 1 result"
        assert data["results"][0]["status"] in ["created", "updated"], "Expected created or updated status"

        return data["results"][0]["video_id"]
    else:
        print(f"✗ Basic upload failed: {response.text}")
        return None

def test_idempotent_upload():
    """Test 2: Idempotent upload (same video twice)"""
    print("\n=== Test 2: Idempotent upload (same video twice) ===")

    source_id = f"test_{int(time.time())}"
    slug = f"test-idempotent-{uuid.uuid4().hex[:8]}"
    video_data = create_test_video_data(slug)

    # First upload
    payload1 = {
        "videos": [video_data],
        "source_id": source_id
    }
    response1 = requests.post(f"{BASE_URL}{API_PATH}", json=payload1)

    if response1.status_code != 200:
        print(f"✗ First upload failed: {response1.text}")
        return False

    data1 = response1.json()
    video_id_1 = data1["results"][0]["video_id"]
    status_1 = data1["results"][0]["status"]

    print(f"First upload: video_id={video_id_1}, status={status_1}")

    # Second upload (same slug and format - should update)
    time.sleep(0.5)  # Small delay
    payload2 = {
        "videos": [video_data],
        "source_id": source_id
    }
    response2 = requests.post(f"{BASE_URL}{API_PATH}", json=payload2)

    if response2.status_code != 200:
        print(f"✗ Second upload failed: {response2.text}")
        return False

    data2 = response2.json()
    video_id_2 = data2["results"][0]["video_id"]
    status_2 = data2["results"][0]["status"]

    print(f"Second upload: video_id={video_id_2}, status={status_2}")

    # Verify same video_id (updated, not created new)
    if video_id_1 == video_id_2:
        print(f"✓ Idempotent upload works correctly - same video_id returned")
        return True
    else:
        print(f"✗ Idempotent upload failed - different video_ids returned")
        return False

def test_batch_upload():
    """Test 3: Batch upload multiple videos"""
    print("\n=== Test 3: Batch upload multiple videos ===")

    source_id = f"test_batch_{int(time.time())}"
    videos = [
        create_test_video_data(f"batch-video-{i}-{uuid.uuid4().hex[:8]}")
        for i in range(3)
    ]

    payload = {
        "videos": videos,
        "source_id": source_id
    }

    response = requests.post(f"{BASE_URL}{API_PATH}", json=payload)

    print(f"Status Code: {response.status_code}")

    if response.status_code == 200:
        data = response.json()
        print(f"✓ Batch upload succeeded")
        print(f"  Total videos: {data['total_videos']}")
        print(f"  Total mappings: {data['total_mappings']}")

        assert data["total_videos"] == 3, "Expected 3 videos"
        assert len(data["results"]) == 3, "Expected 3 results"

        return True
    else:
        print(f"✗ Batch upload failed: {response.text}")
        return False

def test_concurrent_upload():
    """Test 4: Concurrent uploads (simulate race condition)"""
    print("\n=== Test 4: Concurrent uploads (race condition test) ===")

    slug = f"test-concurrent-{uuid.uuid4().hex[:8]}"
    source_id = f"test_concurrent_{int(time.time())}"

    def upload_video():
        """Upload the same video (simulates race condition)"""
        video_data = create_test_video_data(slug)
        payload = {
            "videos": [video_data],
            "source_id": source_id
        }
        response = requests.post(f"{BASE_URL}{API_PATH}", json=payload)
        return response

    # Launch 5 concurrent uploads of the same video
    with ThreadPoolExecutor(max_workers=5) as executor:
        futures = [executor.submit(upload_video) for _ in range(5)]

        results = []
        for future in as_completed(futures):
            try:
                response = future.result()
                results.append(response)
            except Exception as e:
                print(f"✗ Concurrent upload exception: {e}")
                return False

    # Verify all uploads succeeded
    success_count = sum(1 for r in results if r.status_code == 200)
    print(f"Successful uploads: {success_count}/{len(results)}")

    if success_count == len(results):
        # Get all video_ids
        video_ids = [r.json()["results"][0]["video_id"] for r in results]
        unique_ids = set(video_ids)

        print(f"Unique video IDs: {len(unique_ids)}")
        print(f"Video IDs: {video_ids}")

        if len(unique_ids) == 1:
            print(f"✓ Concurrent uploads handled correctly - all returned same video_id")
            return True
        else:
            print(f"✗ Concurrent uploads failed - multiple video_ids created")
            return False
    else:
        print(f"✗ Some concurrent uploads failed")
        return False

def wait_for_service(max_retries=30):
    """Wait for the service to be ready"""
    print("Waiting for service to be ready...")
    for i in range(max_retries):
        try:
            response = requests.get(f"{BASE_URL}/health", timeout=5)
            if response.status_code == 200:
                print("✓ Service is ready!")
                return True
        except requests.exceptions.RequestException:
            pass

        time.sleep(1)
        if i % 5 == 0:
            print(f"  Still waiting... ({i}/{max_retries})")

    print(f"✗ Service not ready after {max_retries} seconds")
    return False

def main():
    """Run all tests"""
    print("=" * 60)
    print("Video Upload Integration Tests")
    print("=" * 60)

    # Wait for service
    if not wait_for_service():
        print("\n✗ Service not available. Exiting.")
        return 1

    # Run tests
    results = []

    try:
        results.append(("Basic Upload", test_basic_upload() is not None))
    except Exception as e:
        print(f"✗ Test 1 failed with exception: {e}")
        results.append(("Basic Upload", False))

    try:
        results.append(("Idempotent Upload", test_idempotent_upload()))
    except Exception as e:
        print(f"✗ Test 2 failed with exception: {e}")
        results.append(("Idempotent Upload", False))

    try:
        results.append(("Batch Upload", test_batch_upload()))
    except Exception as e:
        print(f"✗ Test 3 failed with exception: {e}")
        results.append(("Batch Upload", False))

    try:
        results.append(("Concurrent Upload", test_concurrent_upload()))
    except Exception as e:
        print(f"✗ Test 4 failed with exception: {e}")
        results.append(("Concurrent Upload", False))

    # Print summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)

    passed = sum(1 for _, result in results if result)
    total = len(results)

    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"{status}: {name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    return 0 if passed == total else 1

if __name__ == "__main__":
    exit(main())
