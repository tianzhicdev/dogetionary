#!/usr/bin/env python3
"""
Script to update all logger.error() calls to use the new log_error() helper function.
This ensures consistent error logging with full stack traces and context.
"""

import os
import re
import sys


def process_file(filepath):
    """Update error logging in a single file"""
    with open(filepath, 'r') as f:
        content = f.read()

    original_content = content
    modified = False

    # Check if file already imports log_error
    has_log_error_import = 'from middleware.logging import log_error' in content

    # Check if file has logger.error calls that need updating
    needs_update = re.search(r'logger\.error\(f?"[^"]*\{str\(e\)\}', content) or \
                   re.search(r'logger\.error\(f?"[^"]*", exc_info=True\)', content) or \
                   re.search(r'logger\.error\([^)]+\)(?!.*exc_info=True)', content)

    if not needs_update:
        return False

    # Add import if needed
    if not has_log_error_import and 'import logging' in content:
        # Find the logging import and add our import after it
        if 'from utils.database import' in content:
            # Add after database imports
            content = content.replace(
                'from utils.database import',
                'from middleware.logging import log_error\nfrom utils.database import',
                1
            )
        elif 'from services.' in content:
            # Add after service imports
            pattern = r'(from services\.[^\n]+\n)'
            match = re.search(pattern, content)
            if match:
                content = content[:match.end()] + 'from middleware.logging import log_error\n' + content[match.end():]
        elif 'from flask import' in content:
            # Add after flask imports
            pattern = r'(from flask import[^\n]+\n)'
            match = re.search(pattern, content)
            if match:
                content = content[:match.end()] + '\nfrom middleware.logging import log_error\n' + content[match.end():]

        modified = True

    # Pattern 1: logger.error(f"... {str(e)}") -> log_error(logger, "...", **context)
    # This is the most common pattern

    # Find all exception handlers
    exception_blocks = re.finditer(
        r'except Exception as e:\s*\n\s+logger\.error\(f?"([^"]+)"(?:, exc_info=True)?\)',
        content,
        re.MULTILINE
    )

    for match in exception_blocks:
        error_msg = match.group(1)

        # Extract context from the error message
        # Example: "Error saving word for user {user_id}: {str(e)}"
        # -> message="Error saving word", context=user_id

        # Clean up the message - remove {str(e)} and similar
        clean_msg = re.sub(r'\s*[:]\s*\{str\(e\)\}.*', '', error_msg)
        clean_msg = re.sub(r'\s*[:]\s*\{e\}.*', '', clean_msg)

        # Extract variables from f-string
        context_vars = re.findall(r'\{(\w+)\}', error_msg)

        # Build context kwargs
        context_parts = []
        for var in context_vars:
            if var not in ['str', 'e']:
                context_parts.append(f'{var}={var}')

        context_str = ', '.join(context_parts)
        if context_str:
            context_str = ', ' + context_str

        # Build new log_error call
        new_call = f'log_error(logger, "{clean_msg}"{context_str})'

        # Replace in content
        old_call = match.group(0).split('\n')[1].strip()
        content = content.replace(old_call, new_call)
        modified = True

    # Write back if modified
    if modified and content != original_content:
        with open(filepath, 'w') as f:
            f.write(content)
        return True

    return False


def main():
    """Process all Python files in handlers/ and services/"""
    src_dir = '/Users/biubiu/projects/dogetionary/src'

    handlers_dir = os.path.join(src_dir, 'handlers')
    services_dir = os.path.join(src_dir, 'services')

    updated_files = []

    for directory in [handlers_dir, services_dir]:
        if not os.path.exists(directory):
            continue

        for root, dirs, files in os.walk(directory):
            for filename in files:
                if filename.endswith('.py') and not filename.startswith('__'):
                    filepath = os.path.join(root, filename)
                    try:
                        if process_file(filepath):
                            updated_files.append(filepath)
                            print(f"✓ Updated: {filepath}")
                    except Exception as e:
                        print(f"✗ Error processing {filepath}: {e}", file=sys.stderr)

    print(f"\nTotal files updated: {len(updated_files)}")

    if updated_files:
        print("\nUpdated files:")
        for f in updated_files:
            print(f"  - {f}")


if __name__ == '__main__':
    main()
