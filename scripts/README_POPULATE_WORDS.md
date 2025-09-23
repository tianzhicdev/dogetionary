# Word Definition Generator Script

This script generates and stores English-Chinese definitions using OpenAI API for common words, perfect for building SEO content quickly.

## Features

✅ **New API Endpoint**: `POST /api/words/generate`
✅ **2000+ Common Words**: List of most common English words
✅ **OpenAI Integration**: Generates high-quality definitions and translations
✅ **Batch Processing**: Efficient bulk generation with rate limiting
✅ **Duplicate Prevention**: Automatically skips existing definitions
✅ **Error Handling**: Comprehensive error reporting and retry logic
✅ **Progress Tracking**: Real-time progress updates and statistics

## Quick Start

### 1. Start your Flask backend
```bash
cd /Users/biubiu/projects/dogetionary/src
python app_refactored.py
```

### 2. Run the definition generator script
```bash
cd /Users/biubiu/projects/dogetionary/scripts

# Generate all words (local development)
python populate_en_zh_words.py

# Generate using production API
python populate_en_zh_words.py --api-url https://dogetionary.webhop.net

# Generate only first 100 words (for testing)
python populate_en_zh_words.py --limit 100

# Slower requests (0.5s delay between requests)
python populate_en_zh_words.py --delay 0.5
```

## API Usage

### Generate Single Definition
```bash
curl -X POST https://dogetionary.webhop.net/api/words/generate \
  -H "Content-Type: application/json" \
  -d '{
    "word": "hello",
    "learning_language": "en",
    "native_language": "zh"
  }'
```

### Response Format
```json
{
  "message": "Definition generated and stored successfully",
  "definition_id": 123,
  "word": "hello",
  "learning_language": "en",
  "native_language": "zh",
  "definition_data": {
    "word": "hello",
    "phonetic": "/həˈloʊ/",
    "part_of_speech": "interjection",
    "definition": "used as a greeting or to begin a phone conversation",
    "translation": "你好",
    "examples": [
      {
        "english": "Hello, how are you?",
        "translation": "你好，你好吗？"
      }
    ]
  }
}
```

## Benefits

1. **High Quality**: OpenAI-generated definitions with proper translations
2. **SEO Ready**: Immediately available content for static site generation
3. **Consistent Format**: Standardized definition structure
4. **Bulk Operations**: Can generate thousands of words efficiently
5. **Smart Caching**: Avoids regenerating existing definitions

## Script Options

| Option | Default | Description |
|--------|---------|-------------|
| `--api-url` | `http://localhost:5000` | Backend API base URL |
| `--limit` | `130` | Number of words to process |
| `--delay` | `0.1` | Delay between requests (seconds) |

## Word Data Structure

Each word includes:
- **Word**: English word
- **Translation**: Chinese translation
- **Definition**: English definition
- **Part of Speech**: Grammar category
- **Phonetic**: IPA pronunciation
- **Examples**: Sample sentences with translations

## Error Handling

The script handles:
- ❌ Network connectivity issues
- ❌ API rate limiting
- ❌ Invalid data formats
- ❌ Database constraints
- ✅ Duplicate word detection
- ✅ Partial success scenarios

## Integration with Static Site

After populating words, the static site generator will have immediate access to:
- Word definitions for SEO pages
- Search functionality
- Letter-based navigation
- Featured words sections

This creates a solid foundation for your `unforgettable-dictionary.com` SEO strategy!