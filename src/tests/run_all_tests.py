#!/usr/bin/env python3
"""
Test runner script for all Dogetionary tests.
Runs both unit tests and integration tests.
"""

import sys
import os
import subprocess
import unittest
import importlib.util
from test_config import (
    TestConfig, setup_test_database, teardown_test_database,
    wait_for_service, print_test_header, print_test_result,
    run_docker_command, TEST_BASE_URL
)

class TestRunner:
    """Main test runner class"""

    def __init__(self):
        self.unit_test_results = {"passed": 0, "failed": 0}
        self.integration_test_results = {"passed": 0, "failed": 0}
        self.total_passed = 0
        self.total_failed = 0

    def run_unit_tests(self):
        """Run all unit tests"""
        print_test_header("UNIT TESTS")

        unit_test_files = [
            'test_unit_spaced_repetition.py',
            'test_unit_user_service.py',
            'test_unit_dictionary_service.py'
        ]

        total_tests = 0
        total_failures = 0

        for test_file in unit_test_files:
            print(f"\nRunning {test_file}...")

            try:
                # Load and run the test module
                test_path = os.path.join(os.path.dirname(__file__), test_file)
                if not os.path.exists(test_path):
                    print(f"⚠ Test file {test_file} not found, skipping...")
                    continue

                # Run the test file as a subprocess to capture results
                result = subprocess.run([
                    sys.executable, test_path
                ], capture_output=True, text=True)

                # Parse the output to count tests
                output = result.stdout + result.stderr
                print(output)

                # Simple parsing of unittest output
                if "OK" in output:
                    # Count tests run
                    lines = output.split('\n')
                    for line in lines:
                        if "Ran" in line and "test" in line:
                            try:
                                count = int(line.split()[1])
                                total_tests += count
                                print(f"✓ {count} tests passed in {test_file}")
                            except (IndexError, ValueError):
                                pass

                elif "FAILED" in output or result.returncode != 0:
                    # Count failures
                    lines = output.split('\n')
                    for line in lines:
                        if "FAILED" in line or "ERROR" in line:
                            total_failures += 1

                    print(f"✗ Some tests failed in {test_file}")

            except Exception as e:
                print(f"✗ Error running {test_file}: {e}")
                total_failures += 1

        self.unit_test_results["passed"] = total_tests - total_failures
        self.unit_test_results["failed"] = total_failures

        print(f"\nUnit Tests Summary:")
        print(f"Passed: {self.unit_test_results['passed']}")
        print(f"Failed: {self.unit_test_results['failed']}")

        return total_failures == 0

    def run_integration_tests(self):
        """Run integration tests"""
        print_test_header("INTEGRATION TESTS")

        # Ensure service is running
        print("Checking if service is running...")
        if not wait_for_service(TEST_BASE_URL):
            print("✗ Service is not running. Starting service...")
            try:
                run_docker_command("up -d app")
                if not wait_for_service(TEST_BASE_URL, timeout=60):
                    print("✗ Failed to start service")
                    return False
            except Exception as e:
                print(f"✗ Failed to start service: {e}")
                return False

        print("✓ Service is running")

        # Run comprehensive integration tests
        integration_test_files = [
            'test_integration_comprehensive.py'
        ]

        total_passed = 0
        total_failed = 0

        for test_file in integration_test_files:
            print(f"\nRunning {test_file}...")

            try:
                test_path = os.path.join(os.path.dirname(__file__), test_file)
                if not os.path.exists(test_path):
                    print(f"⚠ Test file {test_file} not found, skipping...")
                    continue

                # Run the integration test
                result = subprocess.run([
                    sys.executable, test_path
                ], capture_output=True, text=True)

                output = result.stdout
                print(output)

                # Parse output to get test results
                lines = output.split('\n')
                for line in lines:
                    if "Passed:" in line:
                        try:
                            passed = int(line.split("Passed:")[1].strip())
                            total_passed += passed
                        except (IndexError, ValueError):
                            pass
                    elif "Failed:" in line:
                        try:
                            failed = int(line.split("Failed:")[1].strip())
                            total_failed += failed
                        except (IndexError, ValueError):
                            pass

                if result.returncode == 0:
                    print(f"✓ Integration tests completed successfully")
                else:
                    print(f"✗ Some integration tests failed")

            except Exception as e:
                print(f"✗ Error running {test_file}: {e}")
                total_failed += 1

        self.integration_test_results["passed"] = total_passed
        self.integration_test_results["failed"] = total_failed

        print(f"\nIntegration Tests Summary:")
        print(f"Passed: {self.integration_test_results['passed']}")
        print(f"Failed: {self.integration_test_results['failed']}")

        return total_failed == 0

    def run_legacy_integration_test(self):
        """Run the existing integration test for comparison"""
        print_test_header("LEGACY INTEGRATION TEST")

        try:
            # Find the existing integration test
            legacy_test_path = os.path.join(
                os.path.dirname(__file__), '..', '..', 'scripts', 'integration_test.py'
            )

            if os.path.exists(legacy_test_path):
                print("Running legacy integration test...")

                result = subprocess.run([
                    sys.executable, legacy_test_path
                ], capture_output=True, text=True)

                output = result.stdout
                print(output)

                if result.returncode == 0:
                    print("✓ Legacy integration test passed")
                    return True
                else:
                    print("✗ Legacy integration test failed")
                    return False

            else:
                print("⚠ Legacy integration test not found")
                return True

        except Exception as e:
            print(f"✗ Error running legacy integration test: {e}")
            return False

    def run_all_tests(self):
        """Run all tests"""
        print_test_header("DOGETIONARY TEST SUITE")

        # Setup
        print("Setting up test environment...")
        if not setup_test_database():
            print("✗ Failed to set up test database")
            return False

        try:
            # Run unit tests
            unit_success = self.run_unit_tests()

            # Run integration tests
            integration_success = self.run_integration_tests()

            # Run legacy test for comparison
            legacy_success = self.run_legacy_integration_test()

            # Calculate totals
            self.total_passed = (
                self.unit_test_results["passed"] +
                self.integration_test_results["passed"]
            )
            self.total_failed = (
                self.unit_test_results["failed"] +
                self.integration_test_results["failed"]
            )

            # Print final results
            print_test_header("FINAL RESULTS")
            print(f"Unit Tests: {self.unit_test_results['passed']} passed, {self.unit_test_results['failed']} failed")
            print(f"Integration Tests: {self.integration_test_results['passed']} passed, {self.integration_test_results['failed']} failed")
            print(f"Legacy Test: {'PASSED' if legacy_success else 'FAILED'}")

            print_test_result(self.total_passed, self.total_failed)

            # Return overall success
            return self.total_failed == 0 and unit_success and integration_success

        finally:
            # Cleanup
            teardown_test_database()

def main():
    """Main function"""
    runner = TestRunner()

    # Parse command line arguments
    if len(sys.argv) > 1:
        test_type = sys.argv[1].lower()

        if test_type == "unit":
            success = runner.run_unit_tests()
        elif test_type == "integration":
            success = runner.run_integration_tests()
        elif test_type == "legacy":
            success = runner.run_legacy_integration_test()
        else:
            print(f"Unknown test type: {test_type}")
            print("Usage: python run_all_tests.py [unit|integration|legacy]")
            return 1
    else:
        # Run all tests
        success = runner.run_all_tests()

    return 0 if success else 1

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)