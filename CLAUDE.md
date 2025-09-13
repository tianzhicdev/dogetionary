# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# principles:
1. always choose the most simple implementation
2. when writing tests, no skipping
3. if a change involves db; make sure you take down the db valumn on docker and restart the service
4. if a change involves backend, always add proper integration tests and run them
5. if a change involves frontend, alwyas make sure frontend/ios app compiles properly


## Project Overview
This is an AI-powered dictionary app with spaced repetition learning. The system consists of a Flask backend with PostgreSQL database and a SwiftUI iOS frontend.

## Architecture

### Backend (Flask + PostgreSQL)
- **Location**: `/src/app.py` (674 lines)
- **Database Schema**: Simplified 5-table design in `/db/init.sql`
  - `user_preferences`: Language settings
  - `audio`: Cached TTS audio data
  - `definitions`: Word definitions with multilingual support  
  - `saved_words`: User's vocabulary list
  - `reviews`: Spaced repetition history

### iOS Frontend (SwiftUI)
- **Location**: `/ios/dogetionary/`
- **Architecture**: MVVM with `DictionaryService` as API client
- **Key Views**: `ContentView`, `SearchView`, `ReviewView`, `SavedWordsView`
- **Models**: `DictionaryModels.swift` defines API contracts

## Development Commands

### Backend Development
```bash
# Start all services (backend, database, nginx)
docker-compose up -d

# Rebuild backend only
docker-compose build app --no-cache
docker-compose up -d app

# Initialize fresh database
docker-compose down
docker volume rm dogetionary_postgres_data
docker-compose up -d

# Run integration tests
python scripts/integration_test.py

# Check backend health
curl http://localhost:5000/health
```

### iOS Development
- Open `ios/dogetionary/dogetionary.xcodeproj` in Xcode
- Ensure backend is running on `localhost:5000`
- Build and run on simulator or device

## Key Implementation Details

### Spaced Repetition Algorithm
- Uses Fibonacci intervals instead of traditional SM-2
- All review data calculated on-demand from `reviews` table
- No stored `next_review_date` or `interval_days` fields
- Consecutive correct answers advance through Fibonacci sequence
- Wrong answers reset to 1-day interval

### API Architecture
- RESTful endpoints following iOS naming conventions
- UUID validation for all user operations
- SQL-optimized queries using CTEs for performance
- Real-time due count calculations

### Database Design Philosophy
- Minimal schema with calculated fields
- PostgreSQL arrays for Fibonacci sequence storage
- JSONB for flexible definition data
- No schema versioning table (compile-time constant)

## Testing Requirements
- Do not make fake/false tests, do not skip tests because they won't pass
- When making backend changes, create integration tests
- When making frontend changes, ensure compilation succeeds
- Use `scripts/integration_test.py` for backend API testing

