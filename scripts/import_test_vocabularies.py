#!/usr/bin/env python3
"""
Import TOEFL and IELTS vocabulary words into test_vocabularies table.
Reads from the CSV files and populates the database.
"""

import csv
import psycopg2
from psycopg2.extras import execute_batch
import os
from pathlib import Path

def get_db_connection():
    """Get database connection from environment or use defaults"""
    db_url = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')
    return psycopg2.connect(db_url)

def read_csv_words(file_path):
    """Read words from CSV file"""
    words = set()
    with open(file_path, 'r', encoding='utf-8') as f:
        # Check if file has headers
        first_line = f.readline().strip()
        f.seek(0)  # Reset to beginning

        # If first line looks like a header (contains 'word'), use DictReader
        if first_line.lower() == 'word' or ',' in first_line:
            reader = csv.DictReader(f)
            for row in reader:
                word = row.get('word', '').strip().lower()
                if word:
                    words.add(word)
        else:
            # No headers, just read each line as a word
            for line in f:
                word = line.strip().lower()
                if word:
                    words.add(word)
    return words

def import_test_vocabularies(conn):
    """Import TOEFL, IELTS, and TIANZ words into database"""
    cur = conn.cursor()

    # Get the project root directory
    project_root = Path(__file__).parent.parent

    # Read TOEFL, IELTS, and TIANZ words
    toefl_file = project_root / 'resources' / 'toefl-4889.csv'
    ielts_file = project_root / 'resources' / 'ielts-4323.csv'
    tianz_file = project_root / 'resources' / 'tianz.csv'

    print(f"Reading TOEFL words from {toefl_file}")
    toefl_words = read_csv_words(toefl_file) if toefl_file.exists() else set()
    print(f"Found {len(toefl_words)} TOEFL words")

    print(f"Reading IELTS words from {ielts_file}")
    ielts_words = read_csv_words(ielts_file) if ielts_file.exists() else set()
    print(f"Found {len(ielts_words)} IELTS words")

    print(f"Reading TIANZ words from {tianz_file}")
    tianz_words = read_csv_words(tianz_file) if tianz_file.exists() else set()
    print(f"Found {len(tianz_words)} TIANZ words")

    # Get all unique words
    all_words = toefl_words | ielts_words | tianz_words

    print(f"\nTotal unique words: {len(all_words)}")
    print(f"TOEFL words: {len(toefl_words)}")
    print(f"IELTS words: {len(ielts_words)}")
    print(f"TIANZ words: {len(tianz_words)}")

    # Prepare data for insertion - each word with its test memberships
    data = []
    for word in all_words:
        is_toefl = word in toefl_words
        is_ielts = word in ielts_words
        is_tianz = word in tianz_words
        data.append((word, 'en', is_toefl, is_ielts, is_tianz))

    # Insert into database
    try:
        # Clear existing data (optional - comment out if you want to append)
        print("Clearing existing test vocabularies...")
        cur.execute("TRUNCATE TABLE test_vocabularies")

        print(f"Inserting {len(data)} vocabulary entries...")
        execute_batch(cur,
            """
            INSERT INTO test_vocabularies (word, language, is_toefl, is_ielts, is_tianz)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (word, language) DO UPDATE SET
                is_toefl = EXCLUDED.is_toefl,
                is_ielts = EXCLUDED.is_ielts,
                is_tianz = EXCLUDED.is_tianz
            """,
            data,
            page_size=100
        )

        conn.commit()

        # Get statistics
        cur.execute("""
            SELECT
                COUNT(*) as total,
                COUNT(CASE WHEN is_toefl THEN 1 END) as toefl_count,
                COUNT(CASE WHEN is_ielts THEN 1 END) as ielts_count,
                COUNT(CASE WHEN is_tianz THEN 1 END) as tianz_count
            FROM test_vocabularies
            WHERE language = 'en'
        """)

        stats = cur.fetchone()
        print("\nDatabase statistics:")
        print(f"  Total words: {stats[0]}")
        print(f"  TOEFL words: {stats[1]}")
        print(f"  IELTS words: {stats[2]}")
        print(f"  TIANZ words: {stats[3]}")

        print("\n✅ Import completed successfully!")

    except Exception as e:
        conn.rollback()
        print(f"❌ Error during import: {e}")
        raise
    finally:
        cur.close()

def verify_import(conn):
    """Verify the import by showing sample words"""
    cur = conn.cursor()

    print("\nSample TOEFL-only words:")
    cur.execute("""
        SELECT word FROM test_vocabularies
        WHERE language = 'en' AND is_toefl = TRUE AND is_ielts = FALSE AND is_tianz = FALSE
        ORDER BY RANDOM() LIMIT 5
    """)
    for row in cur.fetchall():
        print(f"  - {row[0]}")

    print("\nSample IELTS-only words:")
    cur.execute("""
        SELECT word FROM test_vocabularies
        WHERE language = 'en' AND is_ielts = TRUE AND is_toefl = FALSE AND is_tianz = FALSE
        ORDER BY RANDOM() LIMIT 5
    """)
    for row in cur.fetchall():
        print(f"  - {row[0]}")

    print("\nSample TIANZ words:")
    cur.execute("""
        SELECT word FROM test_vocabularies
        WHERE language = 'en' AND is_tianz = TRUE
        ORDER BY RANDOM() LIMIT 5
    """)
    for row in cur.fetchall():
        print(f"  - {row[0]}")

    cur.close()

def main():
    print("📚 Test Vocabulary Import Script")
    print("=" * 40)

    # Connect to database
    conn = get_db_connection()

    try:
        # First, ensure the table exists
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS test_vocabularies (
                word VARCHAR(100) NOT NULL,
                language VARCHAR(10) NOT NULL DEFAULT 'en',
                is_toefl BOOLEAN DEFAULT FALSE,
                is_ielts BOOLEAN DEFAULT FALSE,
                is_tianz BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (word, language)
            )
        """)
        conn.commit()
        cur.close()

        # Import vocabularies
        import_test_vocabularies(conn)

        # Verify the import
        verify_import(conn)

    finally:
        conn.close()

if __name__ == "__main__":
    main()