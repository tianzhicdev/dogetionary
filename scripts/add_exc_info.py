#!/usr/bin/env python3
"""
Simple script to add exc_info=True to all logger.error() calls.
This ensures full stack traces are logged without changing message formats.
"""

import os
import re


def process_file(filepath):
    """Add exc_info=True to logger.error calls"""
    with open(filepath, 'r') as f:
        content = f.read()

    original = content

    # Pattern: logger.error(...) that doesn't already have exc_info
    # We need to handle:
    # - logger.error("message")
    # - logger.error(f"message {var}")
    # - logger.error("message", some_arg)

    # Find all logger.error calls
    pattern = r'logger\.error\(([^)]+)\)(?!\s*#.*exc_info)'

    def add_exc_info(match):
        args = match.group(1).strip()

        # Check if exc_info is already in the call
        if 'exc_info' in args:
            return match.group(0)  # Don't modify

        # Add exc_info=True
        return f'logger.error({args}, exc_info=True)'

    # Apply the transformation
    content = re.sub(pattern, add_exc_info, content)

    # Write back if changed
    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        return True

    return False


def main():
    """Process all Python files in handlers/ and services/"""
    src_dir = '/Users/biubiu/projects/dogetionary/src'
    updated = 0

    for subdir in ['handlers', 'services', 'utils']:
        dir_path = os.path.join(src_dir, subdir)
        if not os.path.exists(dir_path):
            continue

        for root, dirs, files in os.walk(dir_path):
            for filename in files:
                if filename.endswith('.py'):
                    filepath = os.path.join(root, filename)
                    try:
                        if process_file(filepath):
                            print(f"✓ Updated: {filepath}")
                            updated += 1
                    except Exception as e:
                        print(f"✗ Error: {filepath}: {e}")

    print(f"\n✓ Total files updated: {updated}")


if __name__ == '__main__':
    main()
