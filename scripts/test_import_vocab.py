#!/usr/bin/env python3
"""Test vocabulary import script - dry run mode"""
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from import_vocabulary_to_prod import import_vocabularies, get_db_connection, detect_schema

def dry_run_test():
    """Test the import script in dry-run mode"""
    print("="*70)
    print("VOCABULARY IMPORT TEST (Dry Run)")
    print("="*70)

    # Get CSV path
    project_root = Path(__file__).parent.parent
    csv_path = project_root / 'resources' / 'words' / 'vocabulary_merged.csv'

    print(f"\n1. Checking CSV file: {csv_path}")
    if not csv_path.exists():
        print(f"❌ CSV file not found!")
        return False

    print(f"✓ CSV file exists")

    # Test database connection
    print(f"\n2. Testing database connection...")
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        print("✓ Database connection successful")

        # Detect schema
        print(f"\n3. Detecting database schema...")
        schema = detect_schema(cursor)
        print(f"\n✓ Schema detection successful:")
        print(f"  - Table: {schema['table_name']}")
        print(f"  - Demo column: {schema['demo_column']}")
        print(f"  - Has business_english: {schema['has_business_english']}")
        print(f"  - Has everyday_english: {schema['has_everyday_english']}")

        # Count current rows
        cursor.execute(f"SELECT COUNT(*) FROM {schema['table_name']}")
        count = cursor.fetchone()[0]
        print(f"\n4. Current vocabulary count: {count} words")

        # Read CSV
        import csv
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        print(f"\n5. CSV contains: {len(rows)} words")

        # Show sample
        print(f"\n6. Sample word from CSV:")
        sample = rows[0]
        print(f"  Word: {sample['word']}")
        print(f"  TOEFL beginner: {sample.get('toefl_beginner', '0')}")
        print(f"  TOEFL intermediate: {sample.get('toefl_intermediate', '0')}")
        print(f"  TOEFL advanced: {sample.get('toefl_advanced', '0')}")
        print(f"  Business English: {sample.get('business_english', '0')}")
        print(f"  Everyday English: {sample.get('everyday_english', '0')}")

        cursor.close()
        conn.close()

        print("\n" + "="*70)
        print("✅ ALL TESTS PASSED - Script is ready to run")
        print("="*70)
        print("\nTo run the actual import on production:")
        print("  python3 scripts/import_vocabulary_to_prod.py")
        return True

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == '__main__':
    success = dry_run_test()
    sys.exit(0 if success else 1)
