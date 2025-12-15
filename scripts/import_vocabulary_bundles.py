"""
Import vocabulary bundles from merged CSV file.
Imports 4,042 words with 8 bundle flags.
"""
import csv
import psycopg2
from pathlib import Path
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def import_bundles():
    # Database connection
    conn = psycopg2.connect(
        host="localhost",
        port=5432,
        database="dogetionary",
        user="dogeuser",
        password="dogepass"
    )
    cursor = conn.cursor()

    # Read CSV
    csv_path = Path(__file__).parent.parent / 'resources' / 'words' / 'vocabulary_merged.csv'
    logger.info(f"Reading vocabulary from {csv_path}")

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    logger.info(f"Found {len(rows)} words in CSV")

    # Import each word
    inserted = 0
    updated = 0

    for row in rows:
        word = row['word'].strip().lower()

        # Convert CSV flags (0/1 strings) to boolean
        flags = {
            'is_toefl_beginner': row.get('toefl_beginner', '0') == '1',
            'is_toefl_intermediate': row.get('toefl_intermediate', '0') == '1',
            'is_toefl_advanced': row.get('toefl_advanced', '0') == '1',
            'is_ielts_beginner': row.get('ielts_beginner', '0') == '1',
            'is_ielts_intermediate': row.get('ielts_intermediate', '0') == '1',
            'is_ielts_advanced': row.get('ielts_advanced', '0') == '1',
            'is_demo': False,  # DEMO bundle is manually curated, not in CSV
            'business_english': row.get('business_english', '0') == '1',
            'everyday_english': row.get('everyday_english', '0') == '1',
        }

        # Upsert word
        cursor.execute("""
            INSERT INTO bundle_vocabularies (
                word, language,
                is_toefl_beginner, is_toefl_intermediate, is_toefl_advanced,
                is_ielts_beginner, is_ielts_intermediate, is_ielts_advanced,
                is_demo, business_english, everyday_english
            ) VALUES (
                %s, 'en',
                %s, %s, %s,
                %s, %s, %s,
                %s, %s, %s
            )
            ON CONFLICT (word, language) DO UPDATE SET
                is_toefl_beginner = EXCLUDED.is_toefl_beginner,
                is_toefl_intermediate = EXCLUDED.is_toefl_intermediate,
                is_toefl_advanced = EXCLUDED.is_toefl_advanced,
                is_ielts_beginner = EXCLUDED.is_ielts_beginner,
                is_ielts_intermediate = EXCLUDED.is_ielts_intermediate,
                is_ielts_advanced = EXCLUDED.is_ielts_advanced,
                business_english = EXCLUDED.business_english,
                everyday_english = EXCLUDED.everyday_english
            RETURNING (xmax = 0) as inserted
        """, [
            word,
            flags['is_toefl_beginner'], flags['is_toefl_intermediate'], flags['is_toefl_advanced'],
            flags['is_ielts_beginner'], flags['is_ielts_intermediate'], flags['is_ielts_advanced'],
            flags['is_demo'], flags['business_english'], flags['everyday_english']
        ])

        result = cursor.fetchone()
        if result and result[0]:
            inserted += 1
        else:
            updated += 1

    conn.commit()
    cursor.close()
    conn.close()

    logger.info(f"Import complete: {inserted} inserted, {updated} updated")

    # Print statistics
    print("\n=== IMPORT STATISTICS ===")
    print(f"Total words processed: {len(rows)}")
    print(f"New words inserted: {inserted}")
    print(f"Existing words updated: {updated}")

if __name__ == '__main__':
    import_bundles()
