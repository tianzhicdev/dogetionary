#!/usr/bin/env python3
"""
Import vocabulary from vocabulary_merged.csv to production database.

PRODUCTION SAFE:
- Works with both test_vocabularies (prod) and bundle_vocabularies (dev)
- Handles missing columns (business_english, everyday_english)
- Maps is_demo -> is_tianz for backward compatibility
"""
import csv
import psycopg2
from pathlib import Path
import logging
import os
import sys

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def get_db_connection():
    """Get database connection from environment or use defaults"""
    db_url = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')
    logger.info(f"Connecting to database...")
    return psycopg2.connect(db_url)

def detect_schema(cursor):
    """Detect which table and columns exist in the database"""
    schema = {
        'table_name': None,
        'has_business_english': False,
        'has_everyday_english': False,
        'demo_column': None
    }

    # Check if bundle_vocabularies exists (post-migration)
    cursor.execute("""
        SELECT EXISTS (
            SELECT FROM information_schema.tables
            WHERE table_name = 'bundle_vocabularies'
        )
    """)
    has_bundle = cursor.fetchone()[0]

    # Check if test_vocabularies exists (pre-migration)
    cursor.execute("""
        SELECT EXISTS (
            SELECT FROM information_schema.tables
            WHERE table_name = 'test_vocabularies'
        )
    """)
    has_test = cursor.fetchone()[0]

    if has_bundle:
        schema['table_name'] = 'bundle_vocabularies'
        schema['demo_column'] = 'is_demo'
        logger.info("✓ Detected: bundle_vocabularies table (post-migration schema)")
    elif has_test:
        schema['table_name'] = 'test_vocabularies'
        schema['demo_column'] = 'is_tianz'
        logger.info("✓ Detected: test_vocabularies table (pre-migration schema)")
    else:
        raise Exception("❌ Neither bundle_vocabularies nor test_vocabularies table found!")

    # Check for business_english column
    cursor.execute(f"""
        SELECT EXISTS (
            SELECT FROM information_schema.columns
            WHERE table_name = '{schema['table_name']}'
            AND column_name = 'business_english'
        )
    """)
    schema['has_business_english'] = cursor.fetchone()[0]

    # Check for everyday_english column
    cursor.execute(f"""
        SELECT EXISTS (
            SELECT FROM information_schema.columns
            WHERE table_name = '{schema['table_name']}'
            AND column_name = 'everyday_english'
        )
    """)
    schema['has_everyday_english'] = cursor.fetchone()[0]

    logger.info(f"✓ business_english column: {'exists' if schema['has_business_english'] else 'missing (will skip)'}")
    logger.info(f"✓ everyday_english column: {'exists' if schema['has_everyday_english'] else 'missing (will skip)'}")

    return schema

def import_vocabularies(csv_path: Path, clear_existing: bool = True):
    """Import vocabularies from CSV file"""

    # Connect to database
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        # Detect schema
        schema = detect_schema(cursor)
        table_name = schema['table_name']

        # Read CSV
        logger.info(f"Reading vocabulary from {csv_path}")
        if not csv_path.exists():
            raise FileNotFoundError(f"CSV file not found: {csv_path}")

        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        logger.info(f"✓ Found {len(rows)} words in CSV")

        # Clear existing data if requested
        if clear_existing:
            logger.info(f"Clearing existing data from {table_name}...")
            cursor.execute(f"TRUNCATE TABLE {table_name} RESTART IDENTITY CASCADE")
            logger.info("✓ Table cleared")

        # Build INSERT query based on available columns
        columns = [
            'word', 'language',
            'is_toefl_beginner', 'is_toefl_intermediate', 'is_toefl_advanced',
            'is_ielts_beginner', 'is_ielts_intermediate', 'is_ielts_advanced',
            schema['demo_column']  # is_demo or is_tianz
        ]

        placeholders = ['%s'] * len(columns)
        update_sets = []

        if schema['has_business_english']:
            columns.append('business_english')
            placeholders.append('%s')
            update_sets.append('business_english = EXCLUDED.business_english')

        if schema['has_everyday_english']:
            columns.append('everyday_english')
            placeholders.append('%s')
            update_sets.append('everyday_english = EXCLUDED.everyday_english')

        # Build UPDATE clause
        base_updates = [
            'is_toefl_beginner = EXCLUDED.is_toefl_beginner',
            'is_toefl_intermediate = EXCLUDED.is_toefl_intermediate',
            'is_toefl_advanced = EXCLUDED.is_toefl_advanced',
            'is_ielts_beginner = EXCLUDED.is_ielts_beginner',
            'is_ielts_intermediate = EXCLUDED.is_ielts_intermediate',
            'is_ielts_advanced = EXCLUDED.is_ielts_advanced',
            f'{schema["demo_column"]} = EXCLUDED.{schema["demo_column"]}'
        ]
        update_sets = base_updates + update_sets

        insert_query = f"""
            INSERT INTO {table_name} ({', '.join(columns)})
            VALUES ({', '.join(placeholders)})
            ON CONFLICT (word, language) DO UPDATE SET
                {', '.join(update_sets)}
        """

        # Import each word
        logger.info(f"Importing {len(rows)} words...")
        inserted = 0
        updated = 0
        errors = 0

        for idx, row in enumerate(rows, 1):
            try:
                word = row['word'].strip().lower()

                # Build values list
                values = [
                    word, 'en',
                    row.get('toefl_beginner', '0') == '1',
                    row.get('toefl_intermediate', '0') == '1',
                    row.get('toefl_advanced', '0') == '1',
                    row.get('ielts_beginner', '0') == '1',
                    row.get('ielts_intermediate', '0') == '1',
                    row.get('ielts_advanced', '0') == '1',
                    False  # is_demo/is_tianz (not in CSV, manually curated)
                ]

                if schema['has_business_english']:
                    values.append(row.get('business_english', '0') == '1')

                if schema['has_everyday_english']:
                    values.append(row.get('everyday_english', '0') == '1')

                cursor.execute(insert_query, values)

                if clear_existing:
                    inserted += 1
                else:
                    # Check if it was an insert or update
                    if cursor.rowcount > 0:
                        inserted += 1
                    else:
                        updated += 1

                if idx % 500 == 0:
                    logger.info(f"  Progress: {idx}/{len(rows)} words processed...")

            except Exception as e:
                logger.error(f"Error importing word '{row.get('word', 'UNKNOWN')}': {e}")
                errors += 1
                continue

        conn.commit()

        # Print statistics
        logger.info("\n" + "="*70)
        logger.info("IMPORT COMPLETE")
        logger.info("="*70)
        logger.info(f"Total words processed: {len(rows)}")
        logger.info(f"Successfully imported: {inserted}")
        if not clear_existing:
            logger.info(f"Updated existing: {updated}")
        logger.info(f"Errors: {errors}")

        # Get database statistics
        cursor.execute(f"""
            SELECT
                COUNT(*) as total,
                COUNT(CASE WHEN is_toefl_beginner THEN 1 END) as toefl_beginner,
                COUNT(CASE WHEN is_toefl_intermediate THEN 1 END) as toefl_intermediate,
                COUNT(CASE WHEN is_toefl_advanced THEN 1 END) as toefl_advanced,
                COUNT(CASE WHEN is_ielts_beginner THEN 1 END) as ielts_beginner,
                COUNT(CASE WHEN is_ielts_intermediate THEN 1 END) as ielts_intermediate,
                COUNT(CASE WHEN is_ielts_advanced THEN 1 END) as ielts_advanced
                {', COUNT(CASE WHEN business_english THEN 1 END) as business_english' if schema['has_business_english'] else ''}
                {', COUNT(CASE WHEN everyday_english THEN 1 END) as everyday_english' if schema['has_everyday_english'] else ''}
            FROM {table_name}
            WHERE language = 'en'
        """)

        stats = cursor.fetchone()

        logger.info("\n" + "="*70)
        logger.info("DATABASE STATISTICS")
        logger.info("="*70)
        logger.info(f"Total unique words: {stats[0]}")
        logger.info(f"\nTOEFL:")
        logger.info(f"  Beginner:     {stats[1]:5d} words")
        logger.info(f"  Intermediate: {stats[2]:5d} words")
        logger.info(f"  Advanced:     {stats[3]:5d} words")
        logger.info(f"\nIELTS:")
        logger.info(f"  Beginner:     {stats[4]:5d} words")
        logger.info(f"  Intermediate: {stats[5]:5d} words")
        logger.info(f"  Advanced:     {stats[6]:5d} words")

        stat_idx = 7
        if schema['has_business_english']:
            logger.info(f"\nBusiness English: {stats[stat_idx]} words")
            stat_idx += 1
        if schema['has_everyday_english']:
            logger.info(f"Everyday English: {stats[stat_idx]} words")

        logger.info("="*70)
        logger.info("✅ Import completed successfully!")

    except Exception as e:
        conn.rollback()
        logger.error(f"❌ Error during import: {e}")
        raise
    finally:
        cursor.close()
        conn.close()

def main():
    # Get CSV path
    project_root = Path(__file__).parent.parent
    csv_path = project_root / 'resources' / 'words' / 'vocabulary_merged.csv'

    # Check if CSV exists
    if not csv_path.exists():
        logger.error(f"❌ CSV file not found: {csv_path}")
        sys.exit(1)

    logger.info("="*70)
    logger.info("VOCABULARY IMPORT SCRIPT (Production Safe)")
    logger.info("="*70)
    logger.info(f"CSV file: {csv_path}")
    logger.info("="*70)

    # Confirm before clearing
    response = input("\n⚠️  This will CLEAR all existing vocabulary data. Continue? (yes/no): ")
    if response.lower() != 'yes':
        logger.info("Import cancelled.")
        sys.exit(0)

    # Run import
    import_vocabularies(csv_path, clear_existing=True)

if __name__ == '__main__':
    main()
