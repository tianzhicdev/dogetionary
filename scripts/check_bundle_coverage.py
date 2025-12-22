#!/usr/bin/env python3
"""
Check video coverage for each vocabulary bundle.

Usage:
    # Local database
    python3 scripts/check_bundle_coverage.py

    # Custom database
    python3 scripts/check_bundle_coverage.py --db-url postgresql://user:pass@host:port/dbname

    # Export to CSV
    python3 scripts/check_bundle_coverage.py --output coverage.csv
"""

import argparse
import psycopg2
import sys
from typing import Optional

def get_bundle_coverage(db_url: str) -> list:
    """Execute the bundle coverage query and return results."""
    query = """
    WITH bundle_unpivot AS (
        SELECT word, language, 'toefl_beginner' AS bundle_name
        FROM bundle_vocabularies WHERE is_toefl_beginner = TRUE
        UNION ALL
        SELECT word, language, 'toefl_intermediate' AS bundle_name
        FROM bundle_vocabularies WHERE is_toefl_intermediate = TRUE
        UNION ALL
        SELECT word, language, 'toefl_advanced' AS bundle_name
        FROM bundle_vocabularies WHERE is_toefl_advanced = TRUE
        UNION ALL
        SELECT word, language, 'ielts_beginner' AS bundle_name
        FROM bundle_vocabularies WHERE is_ielts_beginner = TRUE
        UNION ALL
        SELECT word, language, 'ielts_intermediate' AS bundle_name
        FROM bundle_vocabularies WHERE is_ielts_intermediate = TRUE
        UNION ALL
        SELECT word, language, 'ielts_advanced' AS bundle_name
        FROM bundle_vocabularies WHERE is_ielts_advanced = TRUE
        UNION ALL
        SELECT word, language, 'business_english' AS bundle_name
        FROM bundle_vocabularies WHERE business_english = TRUE
        UNION ALL
        SELECT word, language, 'everyday_english' AS bundle_name
        FROM bundle_vocabularies WHERE everyday_english = TRUE
        UNION ALL
        SELECT word, language, 'demo' AS bundle_name
        FROM bundle_vocabularies WHERE is_demo = TRUE
    )
    SELECT
        bv.bundle_name,
        COUNT(DISTINCT bv.word) AS total_words,
        COUNT(DISTINCT wtv.word) AS words_with_videos,
        COUNT(wtv.id) AS total_video_mappings,
        ROUND(
            (COUNT(DISTINCT wtv.word)::DECIMAL / NULLIF(COUNT(DISTINCT bv.word), 0) * 100),
            2
        ) AS coverage_pct,
        ROUND(
            (COUNT(wtv.id)::DECIMAL / NULLIF(COUNT(DISTINCT bv.word), 0)),
            2
        ) AS avg_videos_per_word,
        ROUND(
            (COUNT(wtv.id)::DECIMAL / NULLIF(COUNT(DISTINCT wtv.word), 0)),
            2
        ) AS avg_videos_per_word_with_video
    FROM bundle_unpivot bv
    LEFT JOIN word_to_video wtv
        ON LOWER(bv.word) = LOWER(wtv.word)
        AND bv.language = wtv.learning_language
    GROUP BY bv.bundle_name
    HAVING COUNT(DISTINCT bv.word) > 0
    ORDER BY coverage_pct DESC, bundle_name;
    """

    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()

    try:
        cursor.execute(query)
        columns = [desc[0] for desc in cursor.description]
        results = cursor.fetchall()
        return columns, results
    finally:
        cursor.close()
        conn.close()

def print_table(columns: list, rows: list):
    """Print results as a formatted table."""
    # Calculate column widths
    widths = [len(col) for col in columns]
    for row in rows:
        for i, val in enumerate(row):
            widths[i] = max(widths[i], len(str(val)))

    # Print header
    header = " | ".join(col.ljust(widths[i]) for i, col in enumerate(columns))
    separator = "-+-".join("-" * w for w in widths)
    print(header)
    print(separator)

    # Print rows
    for row in rows:
        print(" | ".join(str(val).ljust(widths[i]) for i, val in enumerate(row)))

def save_csv(columns: list, rows: list, filename: str):
    """Save results to CSV file."""
    import csv

    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(columns)
        writer.writerows(rows)

    print(f"Results saved to {filename}")

def main():
    parser = argparse.ArgumentParser(
        description="Check video coverage for vocabulary bundles"
    )
    parser.add_argument(
        "--db-url",
        default="postgresql://dogeuser:dogepass@localhost:5432/dogetionary",
        help="Database URL (default: local database)"
    )
    parser.add_argument(
        "--output",
        help="Output CSV filename (optional)"
    )

    args = parser.parse_args()

    try:
        print("Fetching bundle coverage data...")
        columns, rows = get_bundle_coverage(args.db_url)

        if args.output:
            save_csv(columns, rows, args.output)
        else:
            print()
            print_table(columns, rows)
            print(f"\nTotal bundles: {len(rows)}")

    except psycopg2.Error as e:
        print(f"Database error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    return 0

if __name__ == "__main__":
    sys.exit(main())
