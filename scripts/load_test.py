#!/usr/bin/env python3
"""
Load Testing Script for Dogetionary Practice Mode API
======================================================

Tests the following critical practice mode endpoints:
- /v3/practice-status (GET) - Practice status
- /v3/next-review-words-batch (GET) - Review questions batch
- /v3/reviews/submit (POST) - Submit review
- /v3/videos/<id> (GET) - Video download
- /v3/due_counts (GET) - Due counts

Usage:
    # Install dependencies first
    pip install locust requests

    # Run with Locust (web UI)
    locust -f load_test.py --host=https://kwafy.com

    # Run headless (command line)
    locust -f load_test.py --host=https://kwafy.com --headless -u 10 -r 2 -t 60s

    # Run simple benchmark
    python load_test.py --simple --users 10 --duration 30

Arguments:
    -u, --users: Number of concurrent users (default: 10)
    -r, --spawn-rate: Users spawned per second (default: 2)
    -t, --run-time: Test duration (e.g., 60s, 5m, 1h)
"""

import time
import random
import statistics
import json
from datetime import datetime
from typing import Dict, List
from locust import HttpUser, task, between, events
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class PracticeModeUser(HttpUser):
    """
    Simulates a user practicing with the Dogetionary app.

    User flow:
    1. Check practice status
    2. Get review batch (questions)
    3. Submit answers
    4. Download videos (if video questions)
    5. Check due counts
    """

    # Wait time between tasks (simulates user thinking/reading time)
    wait_time = between(1, 5)

    # Test user credentials (use real user_id from your system)
    # You should replace these with valid test users
    test_users = [
        {"user_id": "C5AC37AC-DC1A-4947-96DC-BE9DAC7CA8AD", "learning_language": "en", "native_language": "zh"},
        {"user_id": "C5AC37AC-DC1A-4947-96DC-BE9DAC7CA8AD", "learning_language": "en", "native_language": "zh"},
        {"user_id": "C5AC37AC-DC1A-4947-96DC-BE9DAC7CA8AD", "learning_language": "en", "native_language": "zh"},
    ]

    def on_start(self):
        """Called when a user starts - setup user context"""
        self.user_data = random.choice(self.test_users)
        self.user_id = self.user_data["user_id"]
        self.learning_language = self.user_data["learning_language"]
        self.native_language = self.user_data["native_language"]
        self.current_questions = []
        logger.info(f"User {self.user_id} started practice session")

    @task(3)
    def get_practice_status(self):
        """
        Task: Get practice status
        Weight: 3 (executed more frequently)
        Endpoint: GET /api/v3/practice-status
        """
        with self.client.get(
            "/api/v3/practice-status",
            params={
                "user_id": self.user_id,
                "learning_language": self.learning_language,
                "native_language": self.native_language
            },
            catch_response=True,
            name="/api/v3/practice-status"
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Status code: {response.status_code}")

    @task(5)
    def get_review_batch(self):
        """
        Task: Get next review words batch
        Weight: 5 (most critical endpoint)
        Endpoint: GET /api/v3/next-review-words-batch
        """
        with self.client.get(
            "/api/v3/next-review-words-batch",
            params={
                "user_id": self.user_id,
                "count": 1,  # Fetch one-by-one as per current implementation
                "learning_language": self.learning_language,
                "native_language": self.native_language
            },
            catch_response=True,
            name="/api/v3/next-review-words-batch"
        ) as response:
            if response.status_code == 200:
                try:
                    data = response.json()
                    if data.get("questions"):
                        self.current_questions = data["questions"]
                        # If video question, fetch video
                        for q in self.current_questions:
                            if q.get("question", {}).get("video_id"):
                                self.get_video(q["question"]["video_id"])
                    response.success()
                except Exception as e:
                    response.failure(f"Failed to parse response: {e}")
            else:
                response.failure(f"Status code: {response.status_code}")

    @task(4)
    def submit_review(self):
        """
        Task: Submit review answer
        Weight: 4 (critical for practice flow)
        Endpoint: POST /api/v3/reviews/submit
        """
        if not self.current_questions:
            # Skip if no questions fetched yet
            return

        # Simulate answering a question
        question = random.choice(self.current_questions)
        word = question.get("word", "test")

        # Randomly correct or incorrect
        is_correct = random.choice([True, False])

        payload = {
            "user_id": self.user_id,
            "word": word,
            "learning_language": self.learning_language,
            "native_language": self.native_language,
            "correct": is_correct,
            "question_type": question.get("question", {}).get("question_type", "mc_definition")
        }

        with self.client.post(
            "/api/v3/reviews/submit",
            json=payload,
            catch_response=True,
            name="/api/v3/reviews/submit"
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Status code: {response.status_code}")

    def get_video(self, video_id: int):
        """
        Fetch video for video questions
        Endpoint: GET /api/v3/videos/<video_id>
        """
        with self.client.get(
            f"/api/v3/videos/{video_id}",
            catch_response=True,
            name="/api/v3/videos/<id>"
        ) as response:
            if response.status_code == 200:
                # Simulate partial download (don't download entire video)
                response.success()
            else:
                response.failure(f"Video {video_id} - Status: {response.status_code}")

    @task(2)
    def get_due_counts(self):
        """
        Task: Get due counts
        Weight: 2 (less frequent)
        Endpoint: GET /api/v3/due_counts
        """
        with self.client.get(
            "/api/v3/due_counts",
            params={
                "user_id": self.user_id,
                "learning_language": self.learning_language,
                "native_language": self.native_language
            },
            catch_response=True,
            name="/api/v3/due_counts"
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Status code: {response.status_code}")


# ============================================================================
# METRICS COLLECTION
# ============================================================================

class MetricsCollector:
    """Collects and aggregates performance metrics"""

    def __init__(self):
        self.request_data: Dict[str, List[float]] = {}
        self.failure_count = 0
        self.success_count = 0

    def record_request(self, name: str, response_time: float, success: bool):
        """Record a request's performance"""
        if name not in self.request_data:
            self.request_data[name] = []

        self.request_data[name].append(response_time)

        if success:
            self.success_count += 1
        else:
            self.failure_count += 1

    def generate_report(self) -> str:
        """Generate performance report"""
        report = []
        report.append("\n" + "=" * 80)
        report.append("LOAD TEST PERFORMANCE REPORT")
        report.append("=" * 80)
        report.append(f"Timestamp: {datetime.now().isoformat()}")
        report.append(f"Total Requests: {self.success_count + self.failure_count}")
        report.append(f"Successful: {self.success_count}")
        report.append(f"Failed: {self.failure_count}")

        if self.success_count + self.failure_count > 0:
            success_rate = (self.success_count / (self.success_count + self.failure_count)) * 100
            report.append(f"Success Rate: {success_rate:.2f}%")

        report.append("\n" + "-" * 80)
        report.append("ENDPOINT PERFORMANCE")
        report.append("-" * 80)
        report.append(f"{'Endpoint':<40} {'Count':>8} {'Min':>8} {'Avg':>8} {'P50':>8} {'P95':>8} {'P99':>8} {'Max':>8}")
        report.append("-" * 80)

        for endpoint, times in sorted(self.request_data.items()):
            if not times:
                continue

            times_sorted = sorted(times)
            count = len(times)
            min_time = min(times)
            max_time = max(times)
            avg_time = statistics.mean(times)

            p50 = times_sorted[int(count * 0.50)]
            p95 = times_sorted[int(count * 0.95)]
            p99 = times_sorted[int(count * 0.99)] if count > 1 else max_time

            report.append(
                f"{endpoint[:40]:<40} {count:>8} "
                f"{min_time:>7.0f}ms {avg_time:>7.0f}ms {p50:>7.0f}ms "
                f"{p95:>7.0f}ms {p99:>7.0f}ms {max_time:>7.0f}ms"
            )

        report.append("=" * 80)
        return "\n".join(report)


# Global metrics collector
metrics_collector = MetricsCollector()


@events.request.add_listener
def on_request(request_type, name, response_time, response_length, exception, **kwargs):
    """Record each request for metrics"""
    success = exception is None
    metrics_collector.record_request(name, response_time, success)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Print report when test stops"""
    report = metrics_collector.generate_report()
    print(report)

    # Save to file
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"load_test_report_{timestamp}.txt"
    with open(filename, 'w') as f:
        f.write(report)
    print(f"\n📊 Report saved to: {filename}")


# ============================================================================
# SIMPLE BENCHMARK MODE (without Locust UI)
# ============================================================================

def simple_benchmark(host: str, users: int = 10, duration: int = 30):
    """
    Run a simple benchmark without Locust UI

    Args:
        host: API host URL (e.g., https://kwafy.com)
        users: Number of concurrent users
        duration: Test duration in seconds
    """
    import requests
    from concurrent.futures import ThreadPoolExecutor, as_completed

    print(f"\n{'=' * 80}")
    print(f"SIMPLE BENCHMARK MODE")
    print(f"{'=' * 80}")
    print(f"Host: {host}")
    print(f"Users: {users}")
    print(f"Duration: {duration}s")
    print(f"{'=' * 80}\n")

    test_user = {
        "user_id": "C5AC37AC-DC1A-4947-96DC-BE9DAC7CA8AD",
        "learning_language": "en",
        "native_language": "zh"
    }

    endpoints = [
        {"name": "practice-status", "method": "GET", "path": "/api/v3/practice-status"},
        {"name": "review-batch", "method": "GET", "path": "/api/v3/next-review-words-batch"},
        {"name": "due-counts", "method": "GET", "path": "/api/v3/due_counts"},
    ]

    results = {ep["name"]: [] for ep in endpoints}

    def make_request(endpoint):
        """Make a single request"""
        url = f"{host}{endpoint['path']}"
        params = {**test_user, "count": 1}

        start = time.time()
        try:
            if endpoint["method"] == "GET":
                response = requests.get(url, params=params, timeout=10)
            else:
                response = requests.post(url, json=params, timeout=10)

            elapsed = (time.time() - start) * 1000  # Convert to ms
            success = response.status_code == 200
            return endpoint["name"], elapsed, success
        except Exception as e:
            elapsed = (time.time() - start) * 1000
            return endpoint["name"], elapsed, False

    # Run test
    start_time = time.time()
    with ThreadPoolExecutor(max_workers=users) as executor:
        futures = []

        while time.time() - start_time < duration:
            # Each user makes random requests
            for _ in range(users):
                endpoint = random.choice(endpoints)
                futures.append(executor.submit(make_request, endpoint))

            time.sleep(0.1)  # Small delay between batches

        # Collect results
        for future in as_completed(futures):
            name, elapsed, success = future.result()
            results[name].append({"time": elapsed, "success": success})

    # Print results
    print(f"\n{'=' * 80}")
    print("BENCHMARK RESULTS")
    print(f"{'=' * 80}")

    for name, data in results.items():
        if not data:
            continue

        times = [d["time"] for d in data]
        successes = sum(1 for d in data if d["success"])
        failures = len(data) - successes

        print(f"\nEndpoint: {name}")
        print(f"  Requests: {len(data)}")
        print(f"  Success: {successes} ({(successes/len(data)*100):.1f}%)")
        print(f"  Failures: {failures}")
        print(f"  Avg Response: {statistics.mean(times):.0f}ms")
        print(f"  Min/Max: {min(times):.0f}ms / {max(times):.0f}ms")

    print(f"\n{'=' * 80}\n")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Load test Dogetionary API")
    parser.add_argument("--simple", action="store_true", help="Run simple benchmark without Locust")
    parser.add_argument("--host", default="https://kwafy.com", help="API host URL")
    parser.add_argument("--users", type=int, default=10, help="Number of concurrent users")
    parser.add_argument("--duration", type=int, default=30, help="Test duration in seconds")

    args = parser.parse_args()

    if args.simple:
        simple_benchmark(args.host, args.users, args.duration)
    else:
        print("\n" + "=" * 80)
        print("To run with Locust web UI:")
        print(f"  locust -f {__file__} --host={args.host}")
        print("\nTo run headless:")
        print(f"  locust -f {__file__} --host={args.host} --headless -u {args.users} -t {args.duration}s")
        print("=" * 80 + "\n")
