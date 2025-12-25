#!/usr/bin/env python3
"""
Load test for batch forgetting curves endpoint.
Tests performance under concurrent requests with varying batch sizes.
"""

import requests
import json
import uuid
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List, Tuple

BASE_URL = "http://localhost:5001"

class BatchCurvesLoadTest:
    def __init__(self):
        self.test_user_id = str(uuid.uuid4())
        self.test_word_ids = []

    def log(self, message: str):
        print(f"[LOAD TEST] {message}")

    def setup_test_data(self):
        """Create test user with saved words"""
        self.log("Setting up test data...")

        # Create user preferences
        response = requests.post(
            f"{BASE_URL}/v3/users/{self.test_user_id}/preferences",
            json={
                "learning_language": "en",
                "native_language": "zh",
                "user_name": "Load Test User",
                "user_motto": "Testing"
            }
        )

        if response.status_code != 200:
            self.log(f"Warning: Could not create user preferences (status {response.status_code})")

        # Save some test words
        test_words = [f"word{i}" for i in range(100)]

        for word in test_words:
            try:
                response = requests.post(
                    f"{BASE_URL}/v3/words/save",
                    json={
                        "user_id": self.test_user_id,
                        "word": word,
                        "learning_language": "en",
                        "native_language": "zh"
                    }
                )

                if response.status_code == 201:
                    data = response.json()
                    self.test_word_ids.append(data["word_id"])
            except Exception as e:
                self.log(f"Error saving word {word}: {e}")

        self.log(f"Created {len(self.test_word_ids)} test words")

    def make_batch_request(self, word_ids: List[int], request_num: int) -> Tuple[int, float, bool]:
        """Make a single batch request and return (request_num, duration_ms, success)"""
        start_time = time.time()

        try:
            response = requests.post(
                f"{BASE_URL}/v3/words/batch/forgetting-curves",
                json={
                    "user_id": self.test_user_id,
                    "word_ids": word_ids
                },
                timeout=30
            )

            duration_ms = (time.time() - start_time) * 1000
            success = response.status_code == 200

            if success:
                data = response.json()
                curves_count = len(data.get("curves", []))
                not_found_count = len(data.get("not_found", []))
                return (request_num, duration_ms, True, curves_count, not_found_count)
            else:
                return (request_num, duration_ms, False, 0, 0)

        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            self.log(f"Request {request_num} failed: {e}")
            return (request_num, duration_ms, False, 0, 0)

    def test_concurrent_requests(self, num_requests: int, batch_size: int, num_threads: int):
        """Test concurrent requests with specified parameters"""
        self.log(f"\n{'='*60}")
        self.log(f"Test: {num_requests} requests, batch_size={batch_size}, threads={num_threads}")
        self.log(f"{'='*60}")

        if len(self.test_word_ids) < batch_size:
            self.log(f"Warning: Only {len(self.test_word_ids)} words available, requested batch_size={batch_size}")
            batch_size = len(self.test_word_ids)

        # Prepare word_ids batches
        word_batches = []
        for i in range(num_requests):
            # Cycle through available words
            start_idx = (i * batch_size) % len(self.test_word_ids)
            end_idx = start_idx + batch_size

            if end_idx <= len(self.test_word_ids):
                batch = self.test_word_ids[start_idx:end_idx]
            else:
                # Wrap around
                batch = self.test_word_ids[start_idx:] + self.test_word_ids[:end_idx - len(self.test_word_ids)]

            word_batches.append(batch)

        # Execute concurrent requests
        start_time = time.time()
        results = []

        with ThreadPoolExecutor(max_workers=num_threads) as executor:
            futures = []
            for i, batch in enumerate(word_batches):
                futures.append(executor.submit(self.make_batch_request, batch, i))

            for future in as_completed(futures):
                results.append(future.result())

        total_duration = time.time() - start_time

        # Analyze results
        successful = [r for r in results if r[2]]
        failed = [r for r in results if not r[2]]

        if successful:
            durations = [r[1] for r in successful]
            avg_duration = sum(durations) / len(durations)
            min_duration = min(durations)
            max_duration = max(durations)
            p95_duration = sorted(durations)[int(len(durations) * 0.95)]

            total_curves = sum(r[3] for r in successful)
            total_not_found = sum(r[4] for r in successful)

            self.log(f"\n📊 Results:")
            self.log(f"   Total time: {total_duration:.2f}s")
            self.log(f"   Successful: {len(successful)}/{num_requests}")
            self.log(f"   Failed: {len(failed)}")
            self.log(f"   Requests/sec: {num_requests/total_duration:.2f}")
            self.log(f"\n⏱️  Response times:")
            self.log(f"   Average: {avg_duration:.2f}ms")
            self.log(f"   Min: {min_duration:.2f}ms")
            self.log(f"   Max: {max_duration:.2f}ms")
            self.log(f"   P95: {p95_duration:.2f}ms")
            self.log(f"\n📈 Data:")
            self.log(f"   Total curves returned: {total_curves}")
            self.log(f"   Total not found: {total_not_found}")
            self.log(f"   Avg curves per request: {total_curves/len(successful):.1f}")
        else:
            self.log(f"\n❌ All {num_requests} requests failed!")

        return len(successful) == num_requests

    def run_all_tests(self):
        """Run all load test scenarios"""
        self.log("🚀 Starting Batch Forgetting Curves Load Test")

        self.setup_test_data()

        if len(self.test_word_ids) < 10:
            self.log(f"❌ Not enough test data created ({len(self.test_word_ids)} words)")
            return False

        # Test scenarios
        all_passed = True

        # Scenario 1: Small batches, low concurrency (typical mobile app usage)
        all_passed &= self.test_concurrent_requests(
            num_requests=20,
            batch_size=10,
            num_threads=5
        )

        # Scenario 2: Medium batches, medium concurrency
        all_passed &= self.test_concurrent_requests(
            num_requests=50,
            batch_size=25,
            num_threads=10
        )

        # Scenario 3: Large batches, high concurrency (stress test)
        all_passed &= self.test_concurrent_requests(
            num_requests=100,
            batch_size=50,
            num_threads=20
        )

        # Scenario 4: Maximum batch size (200 words per request)
        if len(self.test_word_ids) >= 100:
            all_passed &= self.test_concurrent_requests(
                num_requests=20,
                batch_size=100,
                num_threads=10
            )

        self.log(f"\n{'='*60}")
        if all_passed:
            self.log("🎉 All load tests passed!")
        else:
            self.log("❌ Some load tests had failures")
        self.log(f"{'='*60}\n")

        return all_passed

if __name__ == "__main__":
    tester = BatchCurvesLoadTest()
    success = tester.run_all_tests()
    exit(0 if success else 1)
