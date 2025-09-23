#!/usr/bin/env python3
"""
Script to find saved words without definitions and generate them.
This ensures the static site has all words that users have saved.
"""

import psycopg2
from psycopg2.extras import RealDictCursor
import requests
import json
import time
import os
from dotenv import load_dotenv

load_dotenv()

def get_missing_words():
    """Find saved words that don't have definitions"""
    db_url = os.getenv('DATABASE_URL', 'postgresql://dogeuser:dogepass@localhost:5432/dogetionary')

    conn = psycopg2.connect(db_url, cursor_factory=RealDictCursor)
    cur = conn.cursor()

    query = """
        SELECT DISTINCT sw.word, sw.learning_language, sw.native_language
        FROM saved_words sw
        LEFT JOIN definitions d ON
            sw.word = d.word AND
            sw.learning_language = d.learning_language AND
            sw.native_language = d.native_language
        WHERE d.word IS NULL
        ORDER BY sw.word
    """

    cur.execute(query)
    missing_words = cur.fetchall()

    cur.close()
    conn.close()

    return missing_words

def generate_definition(api_url, word, learning_lang, native_lang):
    """Generate definition for a word via API"""
    endpoint = f"{api_url}/api/words/generate"
    payload = {
        "word": word,
        "learning_language": learning_lang,
        "native_language": native_lang
    }

    try:
        response = requests.post(endpoint, json=payload, timeout=30)

        if response.status_code in [200, 201]:
            print(f"✅ Generated: {word} ({learning_lang}->{native_lang})")
            return True
        elif "already exists" in response.text:
            print(f"⚠️  Exists: {word} ({learning_lang}->{native_lang})")
            return True
        else:
            print(f"❌ Failed: {word} - {response.status_code}: {response.text[:200]}")
            return False
    except Exception as e:
        print(f"❌ Error: {word} - {str(e)}")
        return False

def main():
    # Configuration
    api_url = os.getenv('API_URL', 'http://localhost:5000')
    delay = 0.5  # Delay between API calls

    print("🔍 Finding saved words without definitions...")
    missing_words = get_missing_words()

    if not missing_words:
        print("✅ All saved words have definitions!")
        return

    print(f"📝 Found {len(missing_words)} words without definitions")
    print("-" * 60)

    # Show first few words
    print("First 10 words to generate:")
    for word_data in missing_words[:10]:
        print(f"  - {word_data['word']} ({word_data['learning_language']}->{word_data['native_language']})")

    if len(missing_words) > 10:
        print(f"  ... and {len(missing_words) - 10} more")

    print("-" * 60)

    # Confirm before processing
    response = input(f"\nGenerate definitions for all {len(missing_words)} words? (y/n): ")
    if response.lower() != 'y':
        print("Cancelled.")
        return

    # Process all missing words
    successful = 0
    failed = 0

    for i, word_data in enumerate(missing_words, 1):
        print(f"[{i}/{len(missing_words)}] Processing: {word_data['word']}")

        if generate_definition(
            api_url,
            word_data['word'],
            word_data['learning_language'],
            word_data['native_language']
        ):
            successful += 1
        else:
            failed += 1

        if delay > 0 and i < len(missing_words):
            time.sleep(delay)

    print("-" * 60)
    print(f"📊 Summary:")
    print(f"   ✅ Successful: {successful}")
    print(f"   ❌ Failed: {failed}")

    if successful > 0:
        print("\n🚀 Now regenerate your static site to include these words:")
        print("   docker-compose -f docker-compose.prod.yml restart generator")

if __name__ == "__main__":
    main()