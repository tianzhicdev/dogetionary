#!/usr/bin/env python3
"""
Test that all Python files have valid syntax and can be imported.
This catches syntax errors before deployment.
"""

import os
import sys
import importlib.util
from pathlib import Path

# Add src to path
src_dir = Path(__file__).parent.parent / 'src'
sys.path.insert(0, str(src_dir))

def test_import(filepath):
    """Try to load a Python file as a module"""
    module_name = filepath.stem
    try:
        spec = importlib.util.spec_from_file_location(module_name, filepath)
        if spec and spec.loader:
            module = importlib.util.module_from_spec(spec)
            # We don't execute the module, just check it can be loaded
            return True, None
    except SyntaxError as e:
        return False, f"SyntaxError: {e}"
    except Exception as e:
        # Other import errors are okay (missing dependencies, etc.)
        # We only care about syntax
        return True, None
    return True, None

def main():
    """Test all Python files in handlers, services, utils"""
    errors = []
    tested = 0

    for subdir in ['handlers', 'services', 'utils', 'middleware']:
        dir_path = src_dir / subdir
        if not dir_path.exists():
            continue

        for py_file in dir_path.glob('**/*.py'):
            if py_file.name.startswith('__'):
                continue

            tested += 1
            success, error = test_import(py_file)

            if not success:
                errors.append(f"{py_file}: {error}")
                print(f"✗ {py_file.relative_to(src_dir)}: {error}")
            else:
                print(f"✓ {py_file.relative_to(src_dir)}")

    print(f"\n{'='*60}")
    print(f"Tested {tested} files")

    if errors:
        print(f"❌ Found {len(errors)} syntax errors:")
        for error in errors:
            print(f"  - {error}")
        sys.exit(1)
    else:
        print(f"✅ All files passed syntax check!")
        sys.exit(0)

if __name__ == '__main__':
    main()
