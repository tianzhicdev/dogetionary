#!/usr/bin/env python3
"""
Prepopulate words script for Dogetionary

This script fetches existing words from the API, asks OpenAI to generate new words,
and then triggers lookups for those words to store them in the database.

Usage:
    python prepopulate_words.py --domain=localhost:5000 --words=10 --learning_language=en --native_language=zh
"""

import argparse
import requests
import json
import time
import sys
import os
from typing import List, Set
from openai import OpenAI

# Load environment variables from .env.secrets if it exists
from dotenv import load_dotenv
import pathlib

# Try to find .env.secrets in parent directory or src directory
script_dir = pathlib.Path(__file__).parent
project_root = script_dir.parent
env_secrets_path = project_root / '.env.secrets'
src_env_secrets = project_root / 'src' / '.env.secrets'

if env_secrets_path.exists():
    load_dotenv(env_secrets_path)
elif src_env_secrets.exists():
    load_dotenv(src_env_secrets)
else:
    load_dotenv('.env.secrets')  # Try current directory as fallback
    env_secrets_path = src_env_secrets  # For error message

# Initialize OpenAI client
openai_key = os.getenv('OPENAI_API_KEY')
if not openai_key:
    print("❌ Error: OPENAI_API_KEY not found in environment variables")
    print(f"   Please ensure .env.secrets exists at {env_secrets_path}")
    sys.exit(1)

client = OpenAI(api_key=openai_key)


def fetch_existing_words(domain: str, learning_lang: str, native_lang: str) -> Set[str]:
    """Fetch all existing words for a language pair from the API"""
    url = f"{domain}/v3/{learning_lang}/{native_lang}/all_words"

    print(f"📥 Fetching existing words from {url}...")

    try:
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        words = response.json()

        if not isinstance(words, list):
            print(f"❌ Error: Expected list of words, got {type(words)}")
            return set()

        print(f"✅ Found {len(words)} existing words")
        return set(words)

    except requests.exceptions.RequestException as e:
        print(f"❌ Error fetching existing words: {e}")
        sys.exit(1)


def generate_new_words(existing_words: Set[str], count: int, learning_lang: str, native_lang: str) -> List[str]:
    """Use OpenAI to generate new words that don't exist in the database"""

    lang_names = {
        'en': 'English', 'zh': 'Chinese', 'de': 'German', 'es': 'Spanish',
        'fr': 'French', 'ja': 'Japanese', 'ko': 'Korean', 'ru': 'Russian',
        'ar': 'Arabic', 'pt': 'Portuguese', 'it': 'Italian', 'nl': 'Dutch'
    }

    learning_lang_name = lang_names.get(learning_lang, learning_lang.upper())
    native_lang_name = lang_names.get(native_lang, native_lang.upper())

    print(f"\n🤖 Asking OpenAI to generate {count} new {learning_lang_name} words for {native_lang_name} learners...")

    # Create exclusion list (limit to avoid token limits)
    exclusion_sample = list(existing_words)[:500] if len(existing_words) > 500 else list(existing_words)

    prompt = f"""Generate {count} useful {learning_lang_name} words for {native_lang_name} language learners to study.

Requirements:
- Words should be useful for language learning (common vocabulary, idioms, phrases)
- Mix of difficulty levels (beginner to advanced)
- Include single words, compound words, and common phrases
- Exclude these existing words: {json.dumps(exclusion_sample)}

Return ONLY a JSON array of words, nothing else. Format: ["word1", "word2", ...]"""

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {
                    "role": "system",
                    "content": "You are a language learning expert who suggests useful vocabulary words."
                },
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            response_format={"type": "json_object"},
            temperature=0.8
        )

        result = json.loads(response.choices[0].message.content)

        # Handle different response formats
        if isinstance(result, list):
            words = result
        elif isinstance(result, dict) and 'words' in result:
            words = result['words']
        elif isinstance(result, dict):
            # Try to find any list value in the dict
            for value in result.values():
                if isinstance(value, list):
                    words = value
                    break
            else:
                print(f"❌ Error: Unexpected response format: {result}")
                return []
        else:
            print(f"❌ Error: Unexpected response type: {type(result)}")
            return []

        # Filter out words that already exist (case-insensitive)
        existing_words_lower = {w.lower() for w in existing_words}
        new_words = [w for w in words if w.lower() not in existing_words_lower]

        print(f"✅ OpenAI generated {len(new_words)} new words (filtered {len(words) - len(new_words)} duplicates)")

        return new_words[:count]  # Ensure we don't exceed requested count

    except Exception as e:
        print(f"❌ Error generating words with OpenAI: {e}")
        sys.exit(1)


def populate_word(domain: str, word: str, learning_lang: str, native_lang: str, max_retries: int = 3) -> bool:
    """Trigger a word lookup to populate it in the database"""
    url = f"{domain}/v3/word"

    # Use a dummy user_id for prepopulation
    params = {
        'w': word,
        'user_id': '00000000-0000-0000-0000-000000000000',
        'learning_lang': learning_lang,
        'native_lang': native_lang
    }

    for attempt in range(max_retries):
        try:
            response = requests.get(url, params=params, timeout=60)
            response.raise_for_status()

            data = response.json()

            # Check if word was successfully defined
            if 'definition_data' in data:
                return True
            else:
                print(f"  ⚠️  Warning: No definition_data in response for '{word}'")
                return False

        except requests.exceptions.RequestException as e:
            if attempt < max_retries - 1:
                print(f"  ⚠️  Retry {attempt + 1}/{max_retries} for '{word}' (error: {e})")
                time.sleep(2 ** attempt)  # Exponential backoff
            else:
                print(f"  ❌ Failed: {word} (error: {e})")
                return False

    return False


def main():
    parser = argparse.ArgumentParser(description='Prepopulate words in Dogetionary database')
    parser.add_argument('--domain', default='https://dogetionary.webhop.net/api',
                        help='API domain (default: https://dogetionary.webhop.net/api)')
    parser.add_argument('--words', type=int, default=10,
                        help='Number of new words to generate (default: 10)')
    parser.add_argument('--learning_language', required=True,
                        help='Learning language code (e.g., en, de, zh)')
    parser.add_argument('--native_language', required=True,
                        help='Native language code (e.g., zh, en)')

    args = parser.parse_args()

    # Normalize domain (ensure no trailing slash, add http:// if missing)
    domain = args.domain.rstrip('/')
    if not domain.startswith('http://') and not domain.startswith('https://'):
        # Assume http for localhost, https for others
        if 'localhost' in domain or '127.0.0.1' in domain:
            domain = f'http://{domain}'
        else:
            domain = f'https://{domain}'

    print("=" * 60)
    print("🔤 Dogetionary Word Prepopulation Script")
    print("=" * 60)
    print(f"Domain: {domain}")
    print(f"Language Pair: {args.learning_language} → {args.native_language}")
    print(f"Target Words: {args.words}")
    print("=" * 60)

    # Step 1: Fetch existing words
    existing_words = fetch_existing_words(domain, args.learning_language, args.native_language)

    # Step 2: Generate new words
    new_words = generate_new_words(existing_words, args.words, args.learning_language, args.native_language)

    if not new_words:
        print("\n⚠️  No new words to populate. Exiting.")
        sys.exit(0)

    # Step 3: Populate each word
    print(f"\n📝 Populating {len(new_words)} new words...")
    print("-" * 60)

    success_count = 0
    fail_count = 0

    for i, word in enumerate(new_words, 1):
        print(f"[{i}/{len(new_words)}] Processing: {word}...", end=" ")

        if populate_word(domain, word, args.learning_language, args.native_language):
            print(f"✅ Added")
            success_count += 1
        else:
            print(f"❌ Failed")
            fail_count += 1

        # Rate limiting: wait between requests
        if i < len(new_words):
            time.sleep(0.5)

    # Summary
    print("-" * 60)
    print(f"\n📊 Summary:")
    print(f"  ✅ Successfully added: {success_count}/{len(new_words)}")
    print(f"  ❌ Failed: {fail_count}/{len(new_words)}")
    print(f"  📚 Total words in database: {len(existing_words) + success_count}")
    print("\n✨ Done!")


if __name__ == '__main__':
    main()
