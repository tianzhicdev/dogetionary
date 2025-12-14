#!/usr/bin/env python3
"""
Fix syntax errors where exc_info=True was incorrectly added inside f-strings.
"""

import os
import re


def fix_file(filepath):
    """Fix exc_info syntax errors in a file"""
    with open(filepath, 'r') as f:
        content = f.read()

    original = content

    # Pattern 1: str(e, exc_info=True) -> str(e) with exc_info outside
    # Example: logger.error(f"Error: {str(e, exc_info=True)}")
    # Should be: logger.error(f"Error: {str(e)}", exc_info=True)
    pattern1 = r'logger\.error\(f"([^"]*)\{str\(e, exc_info=True\)\}([^"]*)"\)'
    def fix1(match):
        before = match.group(1)
        after = match.group(2)
        return f'logger.error(f"{before}{{str(e)}}{after}", exc_info=True)'

    content = re.sub(pattern1, fix1, content)

    # Pattern 2: {var, exc_info=True} -> {var} with exc_info outside
    # For other cases where exc_info got added inside curly braces
    pattern2 = r'logger\.error\(f"([^"]*)\{([^}]+), exc_info=True\}([^"]*)"\)'
    def fix2(match):
        before = match.group(1)
        var = match.group(2)
        after = match.group(3)
        return f'logger.error(f"{before}{{{var}}}{after}", exc_info=True)'

    content = re.sub(pattern2, fix2, content)

    # Pattern 3: Double exc_info=True
    # logger.error(..., exc_info=True), exc_info=True
    pattern3 = r'logger\.error\(([^)]+)\), exc_info=True\)'
    content = re.sub(pattern3, r'logger.error(\1)', content)

    # Write back if changed
    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        return True

    return False


def main():
    """Fix all files in handlers, services, and utils"""
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
                        if fix_file(filepath):
                            print(f"✓ Fixed: {filepath}")
                            updated += 1
                    except Exception as e:
                        print(f"✗ Error: {filepath}: {e}")

    print(f"\n✓ Total files fixed: {updated}")


if __name__ == '__main__':
    main()
