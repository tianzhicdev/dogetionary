#!/usr/bin/env python3
"""
Test script to verify all log levels are indexed by Loki.

This script writes test logs at different levels with unique identifiers
so you can verify they appear in Loki/Grafana.

Usage:
    python scripts/test_loki_logging.py

After running, check Grafana/Loki for logs with:
    {app="dogetionary"} |= "LOKI_TEST_"
"""

import sys
import os
import time
import uuid
import logging

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Import Flask app to use its logging configuration
from app import create_app

def test_all_log_levels():
    """Test logging at all levels with unique identifiers."""
    app = create_app()

    # Generate unique test ID
    test_id = str(uuid.uuid4())[:8]
    print(f"\n{'='*70}")
    print(f"LOKI LOGGING TEST - ID: {test_id}")
    print(f"{'='*70}\n")

    with app.app_context():
        # Test 1: App logger at all levels
        print("Test 1: App logger at all levels")
        print("-" * 70)

        app.logger.debug(f"LOKI_TEST_{test_id}_DEBUG: This is a DEBUG level log")
        print("✓ DEBUG log written")

        app.logger.info(f"LOKI_TEST_{test_id}_INFO: This is an INFO level log")
        print("✓ INFO log written")

        app.logger.warning(f"LOKI_TEST_{test_id}_WARNING: This is a WARNING level log")
        print("✓ WARNING log written")

        app.logger.error(f"LOKI_TEST_{test_id}_ERROR: This is an ERROR level log")
        print("✓ ERROR log written")

        app.logger.critical(f"LOKI_TEST_{test_id}_CRITICAL: This is a CRITICAL level log")
        print("✓ CRITICAL log written")

        # Test 2: Child loggers (handlers.*)
        print(f"\n{'='*70}")
        print("Test 2: Child loggers (handlers.*)")
        print("-" * 70)

        test_logger = logging.getLogger('handlers.test')
        test_logger.info(f"LOKI_TEST_{test_id}_CHILD_INFO: Child logger INFO")
        print("✓ Child logger INFO written")

        test_logger.error(f"LOKI_TEST_{test_id}_CHILD_ERROR: Child logger ERROR")
        print("✓ Child logger ERROR written")

        # Test 3: Logger with exception traceback
        print(f"\n{'='*70}")
        print("Test 3: ERROR with traceback")
        print("-" * 70)

        try:
            # Intentionally raise an exception
            raise ValueError(f"LOKI_TEST_{test_id}_EXCEPTION: Test exception for traceback")
        except Exception as e:
            app.logger.error(
                f"LOKI_TEST_{test_id}_ERROR_WITH_TRACEBACK: Caught exception",
                exc_info=True
            )
            print("✓ ERROR with traceback written")

        # Test 4: Different child logger names
        print(f"\n{'='*70}")
        print("Test 4: Multiple child logger names")
        print("-" * 70)

        for logger_name in ['handlers.reads', 'handlers.actions', 'utils.database']:
            logger = logging.getLogger(logger_name)
            logger.info(f"LOKI_TEST_{test_id}_LOGGER_{logger_name.replace('.', '_')}")
            print(f"✓ {logger_name} INFO written")

    # Summary
    print(f"\n{'='*70}")
    print("TEST COMPLETE")
    print(f"{'='*70}\n")
    print("To verify logs in Loki/Grafana, use the following queries:")
    print(f"\n1. All test logs:")
    print(f'   {{app="dogetionary"}} |= "LOKI_TEST_{test_id}"')
    print(f"\n2. Only ERROR logs:")
    print(f'   {{app="dogetionary", level="ERROR"}} |= "LOKI_TEST_{test_id}"')
    print(f"\n3. Only child logger logs:")
    print(f'   {{app="dogetionary", logger=~"handlers.*"}} |= "LOKI_TEST_{test_id}"')
    print(f"\n4. Logs with tracebacks:")
    print(f'   {{app="dogetionary"}} |= "LOKI_TEST_{test_id}_ERROR_WITH_TRACEBACK"')
    print(f"\nExpected log count: 11 logs")
    print(f"  - 5 app.logger logs (DEBUG, INFO, WARNING, ERROR, CRITICAL)")
    print(f"  - 2 child logger logs (INFO, ERROR)")
    print(f"  - 1 ERROR with traceback")
    print(f"  - 3 different child logger names")
    print(f"\nTest ID: {test_id}")
    print("\nWait 10-30 seconds for logs to be indexed by Loki, then check Grafana.\n")


def test_with_request_context():
    """Test logging within a Flask request context."""
    app = create_app()

    test_id = str(uuid.uuid4())[:8]
    print(f"\n{'='*70}")
    print(f"LOKI REQUEST CONTEXT TEST - ID: {test_id}")
    print(f"{'='*70}\n")

    with app.test_request_context('/test-loki-logging', method='GET'):
        from flask import g
        g.request_id = f"test-{test_id}"
        g.user_id = "00000000-0000-0000-0000-000000000000"

        app.logger.info(f"LOKI_TEST_{test_id}_REQUEST_CONTEXT_INFO: Log with request context")
        app.logger.error(f"LOKI_TEST_{test_id}_REQUEST_CONTEXT_ERROR: Error with request context")

        print("✓ Logs with request context written")
        print(f"\nThese logs should include:")
        print(f"  - request_id: test-{test_id}")
        print(f"  - user_id: 00000000-0000-0000-0000-000000000000")
        print(f"  - endpoint, method, path fields")
        print(f"\nQuery in Loki:")
        print(f'  {{app="dogetionary"}} |= "LOKI_TEST_{test_id}_REQUEST_CONTEXT"')


def test_structured_logging():
    """Test that JSON fields are properly structured in Loki."""
    app = create_app()

    test_id = str(uuid.uuid4())[:8]
    print(f"\n{'='*70}")
    print(f"LOKI STRUCTURED LOGGING TEST - ID: {test_id}")
    print(f"{'='*70}\n")

    with app.app_context():
        # Test structured fields
        app.logger.info(
            f"LOKI_TEST_{test_id}_STRUCTURED: Testing JSON structure",
            extra={
                'test_field_1': 'value1',
                'test_field_2': 123,
                'test_field_3': True
            }
        )

        print("✓ Structured log written")
        print(f"\nThis log should include extra fields:")
        print(f"  - test_field_1: 'value1'")
        print(f"  - test_field_2: 123")
        print(f"  - test_field_3: True")
        print(f"\nQuery in Loki:")
        print(f'  {{app="dogetionary"}} |= "LOKI_TEST_{test_id}_STRUCTURED"')


if __name__ == "__main__":
    print("\n" + "="*70)
    print("LOKI LOGGING VERIFICATION TEST SUITE")
    print("="*70)

    # Run all tests
    test_all_log_levels()
    time.sleep(1)
    test_with_request_context()
    time.sleep(1)
    test_structured_logging()

    print("\n" + "="*70)
    print("ALL TESTS COMPLETE")
    print("="*70)
    print("\nNext steps:")
    print("1. Wait 10-30 seconds for logs to be indexed by Loki")
    print("2. Go to your Grafana Explore page")
    print("3. Use the queries shown above to verify logs")
    print("4. Verify all expected fields are present in the JSON output")
    print("\nExpected fields in each log:")
    print("  - asctime, name, levelname, pathname, lineno, message")
    print("  - app, service, level, logger, file, line")
    print("  - (if request context) request_id, user_id, endpoint, method, path")
    print("  - (if exception) exc_info with full traceback")
    print()
