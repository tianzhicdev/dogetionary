#!/usr/bin/env python3
"""
Import TOEFL and IELTS vocabulary words with level annotations into test_vocabularies table.
Reads from annotated CSV files (word,level format) and populates the database with cumulative level flags.

Cumulative Logic:
- beginner level words: included in beginner, intermediate, and advanced
- intermediate level words: included in intermediate and advanced only
- advanced level words: included in advanced only
"""

import csv
import psycopg2
from psycopg2.extras import execute_batch
import os
from pathlib import Path
from typing import Dict, Tuple


def get_db_connection():
    """Get database connection from environment or use defaults"""
    db_url = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')
    return psycopg2.connect(db_url)


def read_annotated_csv(file_path: Path) -> Dict[str, str]:
    """
    Read annotated CSV with word,level columns.

    Args:
        file_path: Path to CSV file with 'word' and 'level' columns

    Returns:
        Dictionary mapping word -> level ('beginner', 'intermediate', 'advanced')
    """
    word_levels = {}

    if not file_path.exists():
        print(f"Warning: File not found: {file_path}")
        return word_levels

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            word = row.get('word', '').strip().lower()
            level = row.get('level', '').strip().lower()

            # Skip empty words or levels
            if not word or not level:
                continue

            # Validate level
            if level not in ['beginner', 'intermediate', 'advanced']:
                print(f"Warning: Invalid level '{level}' for word '{word}', skipping")
                continue

            word_levels[word] = level

    return word_levels


def compute_cumulative_flags(level: str) -> Tuple[bool, bool, bool]:
    """
    Convert level to cumulative boolean flags.

    Cumulative logic:
    - beginner: appears in beginner, intermediate, and advanced sets
    - intermediate: appears in intermediate and advanced sets only
    - advanced: appears in advanced set only

    Args:
        level: One of 'beginner', 'intermediate', 'advanced', or None

    Returns:
        Tuple of (is_beginner, is_intermediate, is_advanced)
    """
    if level == 'beginner':
        return (True, True, True)  # Beginner words included in all levels
    elif level == 'intermediate':
        return (False, True, True)  # Intermediate words in intermediate and advanced
    elif level == 'advanced':
        return (False, False, True)  # Advanced words only in advanced
    else:
        return (False, False, False)  # Not in this test


def import_test_vocabularies(conn):
    """Import TOEFL and IELTS vocabulary words with level support"""
    cur = conn.cursor()

    # Get the project root directory
    project_root = Path(__file__).parent.parent

    # Read annotated CSV files
    toefl_file = project_root / 'resources' / 'toefl-4889-annotated.csv'
    ielts_file = project_root / 'resources' / 'ielts-4323-annotated.csv'
    tianz_file = project_root / 'resources' / 'tianz.csv'  # No levels for tianz

    print(f"Reading TOEFL words from {toefl_file}")
    toefl_word_levels = read_annotated_csv(toefl_file)
    print(f"Found {len(toefl_word_levels)} TOEFL words")

    print(f"Reading IELTS words from {ielts_file}")
    ielts_word_levels = read_annotated_csv(ielts_file)
    print(f"Found {len(ielts_word_levels)} IELTS words")

    # Read TIANZ words (no levels, just a simple list)
    tianz_words = set()
    if tianz_file.exists():
        with open(tianz_file, 'r', encoding='utf-8') as f:
            # Try to read as CSV first
            first_line = f.readline().strip()
            f.seek(0)

            if 'word' in first_line.lower():
                reader = csv.DictReader(f)
                for row in reader:
                    word = row.get('word', '').strip().lower()
                    if word:
                        tianz_words.add(word)
            else:
                # Plain text, one word per line
                for line in f:
                    word = line.strip().lower()
                    if word:
                        tianz_words.add(word)

    print(f"Reading TIANZ words from {tianz_file}")
    print(f"Found {len(tianz_words)} TIANZ words")

    # Get all unique words across all tests
    all_words = set(toefl_word_levels.keys()) | set(ielts_word_levels.keys()) | tianz_words

    print(f"\nTotal unique words: {len(all_words)}")
    print(f"TOEFL words: {len(toefl_word_levels)}")
    print(f"IELTS words: {len(ielts_word_levels)}")
    print(f"TIANZ words: {len(tianz_words)}")

    # Prepare data for insertion with level flags
    data = []
    for word in all_words:
        # Get TOEFL level and compute cumulative flags
        toefl_level = toefl_word_levels.get(word)
        toefl_beginner, toefl_intermediate, toefl_advanced = compute_cumulative_flags(toefl_level)

        # Get IELTS level and compute cumulative flags
        ielts_level = ielts_word_levels.get(word)
        ielts_beginner, ielts_intermediate, ielts_advanced = compute_cumulative_flags(ielts_level)

        # TIANZ is simple boolean
        is_tianz = word in tianz_words

        # For backward compatibility, also set old boolean flags
        is_toefl = toefl_advanced  # Old flag = advanced level
        is_ielts = ielts_advanced  # Old flag = advanced level

        data.append((
            word, 'en',
            is_toefl, is_ielts, is_tianz,  # Old columns
            toefl_beginner, toefl_intermediate, toefl_advanced,  # TOEFL levels
            ielts_beginner, ielts_intermediate, ielts_advanced   # IELTS levels
        ))

    # Insert into database
    try:
        # Clear existing data
        print("\nClearing existing test vocabularies...")
        cur.execute("TRUNCATE TABLE test_vocabularies RESTART IDENTITY CASCADE")

        print(f"Inserting {len(data)} vocabulary entries with level information...")
        execute_batch(cur, """
            INSERT INTO test_vocabularies (
                word, language,
                is_toefl, is_ielts, is_tianz,
                is_toefl_beginner, is_toefl_intermediate, is_toefl_advanced,
                is_ielts_beginner, is_ielts_intermediate, is_ielts_advanced
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (word, language) DO UPDATE SET
                is_toefl = EXCLUDED.is_toefl,
                is_ielts = EXCLUDED.is_ielts,
                is_tianz = EXCLUDED.is_tianz,
                is_toefl_beginner = EXCLUDED.is_toefl_beginner,
                is_toefl_intermediate = EXCLUDED.is_toefl_intermediate,
                is_toefl_advanced = EXCLUDED.is_toefl_advanced,
                is_ielts_beginner = EXCLUDED.is_ielts_beginner,
                is_ielts_intermediate = EXCLUDED.is_ielts_intermediate,
                is_ielts_advanced = EXCLUDED.is_ielts_advanced
        """, data, page_size=100)

        conn.commit()

        # Get statistics with cumulative counts
        cur.execute("""
            SELECT
                COUNT(*) as total,
                COUNT(CASE WHEN is_toefl_beginner THEN 1 END) as toefl_beginner,
                COUNT(CASE WHEN is_toefl_intermediate THEN 1 END) as toefl_intermediate,
                COUNT(CASE WHEN is_toefl_advanced THEN 1 END) as toefl_advanced,
                COUNT(CASE WHEN is_ielts_beginner THEN 1 END) as ielts_beginner,
                COUNT(CASE WHEN is_ielts_intermediate THEN 1 END) as ielts_intermediate,
                COUNT(CASE WHEN is_ielts_advanced THEN 1 END) as ielts_advanced,
                COUNT(CASE WHEN is_tianz THEN 1 END) as tianz_count
            FROM test_vocabularies
            WHERE language = 'en'
        """)

        stats = cur.fetchone()
        print("\n" + "="*60)
        print("DATABASE STATISTICS (Cumulative Counts)")
        print("="*60)
        print(f"Total unique words: {stats[0]}")
        print(f"\nTOEFL Cumulative Levels:")
        print(f"  Beginner level:     {stats[1]:5d} words (beginner only)")
        print(f"  Intermediate level: {stats[2]:5d} words (beginner + intermediate)")
        print(f"  Advanced level:     {stats[3]:5d} words (all TOEFL words)")
        print(f"\nIELTS Cumulative Levels:")
        print(f"  Beginner level:     {stats[4]:5d} words (beginner only)")
        print(f"  Intermediate level: {stats[5]:5d} words (beginner + intermediate)")
        print(f"  Advanced level:     {stats[6]:5d} words (all IELTS words)")
        print(f"\nTIANZ: {stats[7]} words")

        # Verify cumulative logic
        print("\n" + "="*60)
        print("VERIFICATION: Cumulative counts should satisfy:")
        print("  Advanced >= Intermediate >= Beginner")
        print("="*60)
        toefl_valid = stats[3] >= stats[2] >= stats[1]
        ielts_valid = stats[6] >= stats[5] >= stats[4]
        print(f"TOEFL: {stats[3]} >= {stats[2]} >= {stats[1]} ... {'✅ PASS' if toefl_valid else '❌ FAIL'}")
        print(f"IELTS: {stats[6]} >= {stats[5]} >= {stats[4]} ... {'✅ PASS' if ielts_valid else '❌ FAIL'}")

        if toefl_valid and ielts_valid:
            print("\n✅ Import completed successfully with correct cumulative logic!")
        else:
            print("\n⚠️  Warning: Cumulative logic verification failed!")

    except Exception as e:
        conn.rollback()
        print(f"❌ Error during import: {e}")
        raise
    finally:
        cur.close()


def verify_import(conn):
    """Verify the import by showing sample words at each level"""
    cur = conn.cursor()

    print("\n" + "="*60)
    print("SAMPLE WORDS BY LEVEL")
    print("="*60)

    # TOEFL Beginner (only beginner level words)
    print("\nTOEFL Beginner-only words (not in intermediate/advanced):")
    cur.execute("""
        SELECT word FROM test_vocabularies
        WHERE language = 'en'
        AND is_toefl_beginner = TRUE
        AND is_toefl_intermediate = FALSE
        ORDER BY RANDOM() LIMIT 5
    """)
    for row in cur.fetchall():
        print(f"  - {row[0]}")

    # TOEFL Intermediate-only (not beginner, not advanced-only)
    print("\nTOEFL Intermediate-only words:")
    cur.execute("""
        SELECT word FROM test_vocabularies
        WHERE language = 'en'
        AND is_toefl_beginner = FALSE
        AND is_toefl_intermediate = TRUE
        ORDER BY RANDOM() LIMIT 5
    """)
    for row in cur.fetchall():
        print(f"  - {row[0]}")

    # TOEFL Advanced-only (not beginner, not intermediate)
    print("\nTOEFL Advanced-only words:")
    cur.execute("""
        SELECT word FROM test_vocabularies
        WHERE language = 'en'
        AND is_toefl_beginner = FALSE
        AND is_toefl_intermediate = FALSE
        AND is_toefl_advanced = TRUE
        ORDER BY RANDOM() LIMIT 5
    """)
    for row in cur.fetchall():
        print(f"  - {row[0]}")

    # IELTS samples
    print("\nIELTS Beginner-only words:")
    cur.execute("""
        SELECT word FROM test_vocabularies
        WHERE language = 'en'
        AND is_ielts_beginner = TRUE
        AND is_ielts_intermediate = FALSE
        ORDER BY RANDOM() LIMIT 5
    """)
    for row in cur.fetchall():
        print(f"  - {row[0]}")

    # TIANZ words
    print("\nTIANZ words:")
    cur.execute("""
        SELECT word FROM test_vocabularies
        WHERE language = 'en' AND is_tianz = TRUE
        ORDER BY RANDOM() LIMIT 5
    """)
    for row in cur.fetchall():
        print(f"  - {row[0]}")

    cur.close()


def main():
    print("📚 Test Vocabulary Import Script (Level-Based)")
    print("=" * 60)

    # Connect to database
    conn = get_db_connection()

    try:
        # Import vocabularies
        import_test_vocabularies(conn)

        # Verify the import
        verify_import(conn)

    finally:
        conn.close()


if __name__ == "__main__":
    main()
