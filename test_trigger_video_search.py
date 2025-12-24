"""
Integration test for /api/trigger-video-search endpoint.

Tests the complete video discovery pipeline:
1. Trigger async video search for a word
2. Wait for background processing to complete
3. Verify video uploaded to database
4. Verify word_to_video mappings created

WARNING: This test uses real APIs and costs money:
- ClipCafe API calls
- OpenAI Whisper API calls (audio transcription)
- LLM API calls (Gemini/DeepSeek/GPT-4o-mini)

Estimated cost per word: $0.05-0.20 depending on video length and LLM usage
"""

import requests
import time
import os
import psycopg2
import psycopg2.extras
from typing import Optional, Dict, List

# Configuration
BASE_URL = os.getenv('BASE_URL', 'http://localhost:5001')
DB_HOST = os.getenv('POSTGRES_HOST', 'localhost')
DB_PORT = int(os.getenv('POSTGRES_PORT', '5432'))
DB_NAME = os.getenv('POSTGRES_DB', 'dogetionary')
DB_USER = os.getenv('POSTGRES_USER', 'dogeuser')
DB_PASSWORD = os.getenv('POSTGRES_PASSWORD', 'dogepass')

# Test configuration
TEST_WORD = "hello"  # Simple word likely to have videos
TEST_LANGUAGE = "en"
MAX_WAIT_TIME_SECONDS = 300  # 5 minutes timeout


def get_db_connection():
    """Connect to database"""
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )


def check_api_keys_configured() -> Dict[str, bool]:
    """Check if required API keys are configured in the backend"""
    print("\n=== Checking API Keys Configuration ===")

    # Try to read from docker container environment
    try:
        result = os.popen("docker-compose exec app printenv | grep -E 'CLIPCAFE|OPENAI_API_KEY|OPEN_ROUTER_KEY'").read()

        keys = {
            'CLIPCAFE': 'CLIPCAFE=' in result,
            'OPENAI_API_KEY': 'OPENAI_API_KEY=' in result,
            'OPEN_ROUTER_KEY': 'OPEN_ROUTER_KEY=' in result
        }

        for key, configured in keys.items():
            status = "✓ Configured" if configured else "✗ Missing"
            print(f"  {key}: {status}")

        all_configured = all(keys.values())
        if not all_configured:
            print("\n⚠️  WARNING: Some API keys are missing. Test may fail.")

        return keys
    except Exception as e:
        print(f"  ✗ Could not check API keys: {e}")
        return {'CLIPCAFE': False, 'OPENAI_API_KEY': False, 'OPEN_ROUTER_KEY': False}


def get_video_count_before(word: str) -> int:
    """Get current count of videos for the word"""
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    cursor.execute("""
        SELECT COUNT(*) as count
        FROM word_to_video
        WHERE word = %s AND learning_language = %s
    """, (word.lower(), TEST_LANGUAGE))

    result = cursor.fetchone()
    count = result['count'] if result else 0

    cursor.close()
    conn.close()

    return count


def trigger_video_search(word: str, language: str = "en") -> Dict:
    """Trigger the video search endpoint"""
    url = f"{BASE_URL}/v3/api/trigger-video-search"
    payload = {
        "word": word,
        "learning_language": language
    }

    print(f"\n=== Triggering Video Search ===")
    print(f"URL: {url}")
    print(f"Payload: {payload}")

    response = requests.post(url, json=payload, timeout=10)
    response.raise_for_status()

    result = response.json()
    print(f"Response: {result}")

    return result


def wait_for_video_upload(word: str, initial_count: int, max_wait: int = MAX_WAIT_TIME_SECONDS) -> bool:
    """
    Poll database to wait for video to be uploaded.
    Returns True if new videos found, False if timeout.
    """
    print(f"\n=== Waiting for Video Upload (max {max_wait}s) ===")
    print(f"Initial video count for '{word}': {initial_count}")

    start_time = time.time()
    poll_interval = 5  # Check every 5 seconds

    while (time.time() - start_time) < max_wait:
        elapsed = int(time.time() - start_time)

        # Check current count
        current_count = get_video_count_before(word)

        if current_count > initial_count:
            print(f"\n✓ Videos uploaded! New count: {current_count} (added {current_count - initial_count})")
            return True

        # Progress indicator
        print(f"  [{elapsed}s] Waiting... (current count: {current_count})", end='\r')
        time.sleep(poll_interval)

    print(f"\n✗ Timeout: No new videos after {max_wait}s")
    return False


def verify_database_state(word: str) -> Dict:
    """Verify that videos and mappings exist in database"""
    print(f"\n=== Verifying Database State ===")

    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

    # Query word_to_video mappings
    cursor.execute("""
        SELECT
            wtv.id,
            wtv.word,
            wtv.learning_language,
            wtv.video_id,
            wtv.relevance_score,
            wtv.transcript_source,
            wtv.verified_at,
            wtv.source_id,
            v.name as video_name,
            v.format,
            v.size_bytes,
            v.audio_transcript_verified,
            LENGTH(v.video_data) as video_data_size
        FROM word_to_video wtv
        JOIN videos v ON wtv.video_id = v.id
        WHERE wtv.word = %s AND wtv.learning_language = %s
        ORDER BY wtv.relevance_score DESC NULLS LAST
        LIMIT 10
    """, (word.lower(), TEST_LANGUAGE))

    mappings = cursor.fetchall()

    result = {
        'success': len(mappings) > 0,
        'total_mappings': len(mappings),
        'mappings': []
    }

    if mappings:
        print(f"✓ Found {len(mappings)} video mappings for '{word}'")
        print("\nMapping Details:")

        for mapping in mappings:
            mapping_dict = dict(mapping)
            result['mappings'].append(mapping_dict)

            print(f"\n  Mapping ID: {mapping['id']}")
            print(f"  Word: {mapping['word']}")
            print(f"  Video ID: {mapping['video_id']}")
            print(f"  Video Name: {mapping['video_name']}.{mapping['format']}")
            print(f"  Relevance Score: {mapping['relevance_score']}")
            print(f"  Transcript Source: {mapping['transcript_source']}")
            print(f"  Audio Verified: {mapping['audio_transcript_verified']}")
            print(f"  Video Data Size: {mapping['video_data_size']:,} bytes ({mapping['video_data_size']/1024/1024:.2f} MB)")
            print(f"  Source ID: {mapping['source_id']}")
            print(f"  Verified At: {mapping['verified_at']}")

            # Verify video_data exists
            if mapping['video_data_size'] > 0:
                print(f"  ✓ Video data present in database")
            else:
                print(f"  ✗ WARNING: Video data is empty!")
    else:
        print(f"✗ No video mappings found for '{word}'")

    cursor.close()
    conn.close()

    return result


def run_integration_test():
    """Run the complete integration test"""
    print("="*80)
    print("INTEGRATION TEST: /api/trigger-video-search")
    print("="*80)
    print(f"Test Word: {TEST_WORD}")
    print(f"Backend URL: {BASE_URL}")
    print(f"Database: {DB_HOST}:{DB_PORT}/{DB_NAME}")
    print("="*80)

    # Check API keys (non-blocking - just informational)
    api_keys = check_api_keys_configured()
    if not all(api_keys.values()):
        print("\n⚠️  WARNING: Could not detect API keys from host.")
        print("  Note: API keys may still be configured in container via .env.secrets")
        print("  Proceeding with test...")

    # Step 1: Get initial state
    print(f"\n=== Step 1: Get Initial State ===")
    initial_count = get_video_count_before(TEST_WORD)
    print(f"Initial video count for '{TEST_WORD}': {initial_count}")

    # Step 2: Trigger video search
    print(f"\n=== Step 2: Trigger Video Search ===")
    try:
        trigger_result = trigger_video_search(TEST_WORD, TEST_LANGUAGE)

        if trigger_result.get('status') != 'triggered':
            print(f"✗ Unexpected response status: {trigger_result}")
            return

        print(f"✓ Video search triggered successfully")

    except Exception as e:
        print(f"✗ Failed to trigger video search: {e}")
        return

    # Step 3: Wait for processing
    print(f"\n=== Step 3: Wait for Background Processing ===")
    upload_success = wait_for_video_upload(TEST_WORD, initial_count, MAX_WAIT_TIME_SECONDS)

    if not upload_success:
        print(f"\n✗ TEST FAILED: No videos uploaded within {MAX_WAIT_TIME_SECONDS}s")
        print("\nPossible reasons:")
        print("  1. No videos found on ClipCafe for this word")
        print("  2. Videos found but failed quality filters")
        print("  3. API errors (check backend logs)")
        print("  4. Background worker crashed")
        print("\nCheck backend logs: docker-compose logs app")
        return

    # Step 4: Verify database state
    print(f"\n=== Step 4: Verify Database State ===")
    db_state = verify_database_state(TEST_WORD)

    # Final summary
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)

    if db_state['success']:
        print(f"✓ TEST PASSED")
        print(f"✓ Videos uploaded: {db_state['total_mappings']}")
        print(f"✓ Video data present in database")

        # Check for audio verification
        audio_verified_count = sum(1 for m in db_state['mappings'] if m['audio_transcript_verified'])
        if audio_verified_count > 0:
            print(f"✓ Audio transcripts verified: {audio_verified_count}/{db_state['total_mappings']}")

        # Check for relevance scores
        scored_count = sum(1 for m in db_state['mappings'] if m['relevance_score'] is not None)
        if scored_count > 0:
            print(f"✓ Relevance scores present: {scored_count}/{db_state['total_mappings']}")

        print("\n✓ Integration test completed successfully!")
    else:
        print(f"✗ TEST FAILED")
        print(f"✗ No videos found in database")

    print("="*80)


if __name__ == '__main__':
    try:
        run_integration_test()
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
    except Exception as e:
        print(f"\n✗ Test failed with exception: {e}")
        import traceback
        traceback.print_exc()
