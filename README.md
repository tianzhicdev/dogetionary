# Dogetionary

AI-powered dictionary app with spaced repetition learning for language acquisition.

## Features

- 🔍 Multi-language word definitions with AI-powered translations
- 🧠 Spaced repetition learning using Fibonacci intervals
- 🎯 Track learning progress with review history
- 🎤 Text-to-speech pronunciation support
- 📱 Native iOS app with SwiftUI interface
- 🚀 RESTful API backend with PostgreSQL database

## Architecture

### Backend Stack
- **Framework**: Flask (Python)
- **Database**: PostgreSQL
- **Caching**: Built-in audio caching for TTS
- **Deployment**: Docker Compose with Nginx reverse proxy

### iOS Frontend
- **Framework**: SwiftUI
- **Architecture**: MVVM pattern
- **Minimum iOS**: 17.0
- **API Client**: Native URLSession with async/await

### Database Schema
- `user_preferences` - Language and learning preferences
- `audio` - Cached TTS audio data
- `definitions` - Word definitions with multilingual support
- `saved_words` - User vocabulary lists
- `reviews` - Spaced repetition history

## Quick Start

### Prerequisites
- Docker and Docker Compose
- Xcode 15+ (for iOS development)
- Python 3.9+ (for testing scripts)

### Backend Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/dogetionary.git
cd dogetionary
```

2. Start all services:
```bash
docker-compose up -d
```

This will start:
- Flask API server on `http://localhost:5000`
- PostgreSQL database on port 5432
- Nginx reverse proxy on port 80

3. Verify backend health:
```bash
curl http://localhost:5000/health
```

### iOS App Setup

1. Open the Xcode project:
```bash
open ios/dogetionary/dogetionary.xcodeproj
```

2. Configure the API endpoint in `DictionaryService.swift` (default: `http://localhost:5000`)

3. Build and run on simulator or device (⌘+R)

## Development

### Backend Development

Rebuild backend after changes:
```bash
docker-compose build app --no-cache
docker-compose up -d app
```

Reset database:
```bash
docker-compose down
docker volume rm dogetionary_postgres_data
docker-compose up -d
```

Sync database from production:
```bash
./scripts/sync_db_from_remote.sh
```
See [Database Sync Guide](docs/database-sync-guide.md) for detailed instructions.

Run integration tests:
```bash
python scripts/integration_test.py
```

### iOS Development

The iOS app follows MVVM architecture:
- **Views**: `ContentView`, `SearchView`, `ReviewView`, `SavedWordsView`
- **Models**: Defined in `DictionaryModels.swift`
- **Service**: `DictionaryService` handles all API communication

## API Endpoints

### Core Endpoints
- `POST /api/search` - Search for word definitions
- `GET /api/saved-words/:userId` - Get user's saved words
- `POST /api/saved-words` - Save a word to user's list
- `GET /api/review-words/:userId` - Get words due for review
- `POST /api/record-review` - Record review result
- `GET /api/audio/:wordId` - Get pronunciation audio

## Spaced Repetition Algorithm

The app uses a Fibonacci-based interval system:
- Consecutive correct answers: 1, 1, 2, 3, 5, 8, 13, 21, 34, 55 days
- Wrong answer resets to 1-day interval
- All intervals calculated on-demand from review history

## Testing

Run the comprehensive integration test suite:
```bash
python scripts/integration_test.py
```

This tests:
- User preferences management
- Word search and definitions
- Saved words functionality
- Review system and spaced repetition
- Audio generation and caching

## Configuration

Environment variables can be set in `docker-compose.yml`:
- `FLASK_ENV`: Development/production mode
- `DATABASE_URL`: PostgreSQL connection string
- `OPENAI_API_KEY`: Required for AI translations

## License

MIT License - See LICENSE file for details

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests to ensure everything works
5. Submit a pull request

## Support

For issues and questions, please open a GitHub issue.