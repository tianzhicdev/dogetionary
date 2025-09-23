#!/usr/bin/env python3
"""
Script to generate definitions for specific missing words that users are trying to access.
This helps quickly fill gaps in the static site.
"""

import requests
import json
import time
import sys

# Add words that are showing 404 errors here
MISSING_WORDS = [
    "malagasy",
    # Add more words as you find them in your 404 logs
]

def generate_word(api_url: str, word: str, learning_lang: str = "en", native_lang: str = "zh"):
    """Generate a single word definition via API"""
    endpoint = f"{api_url}/api/words/generate"
    payload = {
        "word": word,
        "learning_language": learning_lang,
        "native_language": native_lang
    }

    try:
        response = requests.post(endpoint, json=payload, timeout=30)

        if response.status_code in [200, 201]:
            print(f"✅ Generated: {word}")
            return True
        elif response.status_code == 200 and "already exists" in response.text:
            print(f"⚠️  Already exists: {word}")
            return True
        else:
            print(f"❌ Failed: {word} - {response.status_code}: {response.text[:200]}")
            return False
    except Exception as e:
        print(f"❌ Error: {word} - {str(e)}")
        return False

def main():
    # Configure your API URL
    api_url = "https://dogetionary.webhop.net"  # or "http://localhost:5000" for local

    print(f"🚀 Generating {len(MISSING_WORDS)} missing word definitions")
    print(f"📡 API URL: {api_url}")
    print("-" * 60)

    successful = 0
    failed = 0

    for word in MISSING_WORDS:
        print(f"Processing: {word}")
        if generate_word(api_url, word):
            successful += 1
        else:
            failed += 1
        time.sleep(0.5)  # Small delay between requests

    print("-" * 60)
    print(f"✅ Successful: {successful}")
    print(f"❌ Failed: {failed}")

    if successful > 0:
        print("\n📝 Now regenerate your static site to include these words:")
        print("   docker-compose -f docker-compose.prod.yml up -d generator")

if __name__ == "__main__":
    main()