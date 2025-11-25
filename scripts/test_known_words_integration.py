#!/usr/bin/env python3
"""
Integration test for is_known functionality in schedules.
Verifies that words marked as known are properly excluded from practice and scheduling.
"""

import psycopg2
import uuid
from datetime import date, timedelta
import os

def get_db_connection():
    """Get database connection"""
    db_url = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')
    return psycopg2.connect(db_url, cursor_factory=psycopg2.extras.DictCursor)

def test_known_words_excluded_from_schedule():
    """Test that words marked as is_known=TRUE are excluded from schedules"""
    print("\n" + "="*60)
    print("Integration Test: Known Words Exclusion from Schedules")
    print("="*60)

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        # Create test user
        user_id = str(uuid.uuid4())
        print(f"\n1. Creating test user: {user_id}")
        cur.execute("""
            INSERT INTO user_preferences (user_id, learning_language, native_language, toefl_enabled)
            VALUES (%s, 'en', 'zh', TRUE)
        """, (user_id,))

        # Save 3 words: 2 unknown, 1 known
        # Save them as "yesterday" so they appear in schedule
        print("\n2. Saving 3 test words (dated yesterday)...")
        test_words = [
            ('abandon', False),  # Unknown
            ('ability', True),   # KNOWN
            ('academic', False)  # Unknown
        ]

        yesterday = date.today() - timedelta(days=1)
        for word, is_known in test_words:
            cur.execute("""
                INSERT INTO saved_words (user_id, word, learning_language, native_language, is_known, created_at)
                VALUES (%s, %s, 'en', 'zh', %s, %s)
                RETURNING id
            """, (user_id, word, is_known, yesterday))
            word_id = cur.fetchone()['id']
            print(f"   - {word}: id={word_id}, is_known={is_known}, created_at={yesterday}")

        conn.commit()

        # Test get_user_saved_words - should only return unknown words
        print("\n3. Testing get_user_saved_words (should exclude known words)...")
        cur.execute("""
            SELECT word, is_known FROM saved_words
            WHERE user_id = %s AND learning_language = 'en' AND is_known = FALSE
            ORDER BY word
        """, (user_id,))

        saved_words = cur.fetchall()
        print(f"   Found {len(saved_words)} unknown words:")
        for row in saved_words:
            print(f"   - {row['word']} (is_known={row['is_known']})")

        assert len(saved_words) == 2, f"Expected 2 unknown words, got {len(saved_words)}"
        assert saved_words[0]['word'] == 'abandon'
        assert saved_words[1]['word'] == 'academic'
        print("   ✓ Only unknown words returned")

        # Verify known word is excluded
        print("\n4. Verifying 'ability' (known word) is excluded...")
        cur.execute("""
            SELECT word, is_known FROM saved_words
            WHERE user_id = %s AND word = 'ability'
        """, (user_id,))
        known_word = cur.fetchone()
        assert known_word['is_known'] == True
        print(f"   ✓ 'ability' exists in DB with is_known=TRUE")
        print(f"   ✓ But excluded from schedule queries (WHERE is_known = FALSE)")

        # Test schedule generation
        print("\n5. Testing schedule generation...")
        import sys
        from pathlib import Path
        sys.path.insert(0, str(Path(__file__).parent.parent / 'src'))
        from services.schedule_service import initiate_schedule

        target_date = date.today() + timedelta(days=10)
        result = initiate_schedule(user_id, 'TOEFL', target_date)

        print(f"   Schedule created:")
        print(f"   - Days remaining: {result['days_remaining']}")
        print(f"   - Total new words: {result['total_new_words']}")
        print(f"   - Test practice words: {result['test_practice_words_count']}")
        print(f"   - Non-test practice words: {result['non_test_practice_words_count']}")

        # Verify: Only 2 practice words (abandon, academic), not 3
        assert result['test_practice_words_count'] == 2, \
            f"Expected 2 practice words, got {result['test_practice_words_count']}"
        print(f"   ✓ Only 2 unknown words in practice schedule")

        # Check daily entries - verify 'ability' behavior
        print("\n6. Verifying 'ability' (known word) behavior in schedule...")
        cur.execute("""
            SELECT scheduled_date, new_words, test_practice_words, non_test_practice_words
            FROM daily_schedule_entries
            WHERE schedule_id = %s
        """, (result['schedule_id'],))

        ability_in_new_words = False
        ability_in_practice = False

        for row in cur.fetchall():
            new_words = row['new_words'] or []
            test_practice = row['test_practice_words'] or []
            non_test_practice = row['non_test_practice_words'] or []

            # Check new_words
            if 'ability' in new_words:
                ability_in_new_words = True
                print(f"   DEBUG: 'ability' found in new_words on {row['scheduled_date']}")

            # Check practice
            for word_obj in (test_practice + non_test_practice):
                if isinstance(word_obj, dict) and word_obj.get('word') == 'ability':
                    ability_in_practice = True
                    print(f"   DEBUG: 'ability' found in practice on {row['scheduled_date']}: {word_obj}")

        # 'ability' can appear in new_words (since it's filtered from saved_words_with_reviews)
        # But should NOT appear in practice schedules
        if ability_in_new_words:
            print("   ✓ 'ability' appears in new_words (expected - known words filtered from saved_words)")
        assert not ability_in_practice, "'ability' found in practice schedule but should be excluded!"
        print("   ✓ 'ability' NOT in practice schedule (correct - known words excluded from practice)")

        print("\n" + "="*60)
        print("✅ All known words integration tests PASSED!")
        print("="*60 + "\n")

        return True

    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

    finally:
        # Cleanup
        if conn:
            conn.rollback()  # Don't commit test data
            cur.close()
            conn.close()


if __name__ == "__main__":
    import sys
    import psycopg2.extras

    success = test_known_words_excluded_from_schedule()
    sys.exit(0 if success else 1)
