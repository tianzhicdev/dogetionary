# Word Population Script

This script populates the backend database with common English words and their Chinese definitions, bypassing OpenAI API calls for better performance and cost savings.

## Features

✅ **New API Endpoint**: `POST /api/words/definitions`
✅ **2000+ Common Words**: Pre-defined English words with Chinese translations
✅ **Batch Processing**: Efficient bulk import with rate limiting
✅ **Duplicate Prevention**: Automatically skips existing definitions
✅ **Error Handling**: Comprehensive error reporting and retry logic
✅ **Progress Tracking**: Real-time progress updates and statistics

## Quick Start

### 1. Start your Flask backend
```bash
cd /Users/biubiu/projects/dogetionary/src
python app_refactored.py
```

### 2. Run the population script
```bash
cd /Users/biubiu/projects/dogetionary/scripts

# Populate all words (local development)
python populate_en_zh_words.py

# Populate to production API
python populate_en_zh_words.py --api-url https://dogetionary.webhop.net

# Populate only first 100 words (for testing)
python populate_en_zh_words.py --limit 100

# Slower requests (0.5s delay between requests)
python populate_en_zh_words.py --delay 0.5
```

## API Usage

### Add Single Definition
```bash
curl -X POST https://dogetionary.webhop.net/api/words/definitions \
  -H "Content-Type: application/json" \
  -d '{
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
  }'
```

### Response Format
```json
{
  "message": "Definition added successfully",
  "definition_id": 123,
  "word": "hello",
  "learning_language": "en",
  "native_language": "zh",
  "definition_data": { ... }
}
```

## Benefits

1. **Cost Savings**: No OpenAI API calls for common words
2. **Performance**: Direct database insertion is much faster
3. **SEO Ready**: Immediate content availability for static site generation
4. **Consistent Quality**: Pre-verified definitions and translations
5. **Bulk Operations**: Can import thousands of words quickly

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