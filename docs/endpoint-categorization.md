# API Endpoint Categorization

## Categories Overview
- **iOS**: Endpoints primarily used by the iOS app for core functionality
- **Web**: Endpoints for web/static site features
- **Admin**: Administrative and monitoring endpoints
- **Test**: Test preparation and vocabulary testing endpoints
- **Analytics**: User analytics and tracking endpoints
- **Internal**: Background jobs and internal operations

---

## iOS Endpoints

### Core Dictionary Features
- `GET /word` - Get word definition (v1)
- `GET /v2/word` - Get word definition (v2)
- `GET /words/<int:word_id>/details` - Get detailed word information
- `POST /save` - Save word to user's list
- `POST /unsave` - Remove word from user's list (v1)
- `POST /v2/unsave` - Remove word from user's list (v2)
- `GET /saved_words` - Get user's saved words

### Review System
- `GET /reviews/next` - Get next review word (v1)
- `GET /reviews/v2/next` - Get next review word (v2)
- `POST /reviews/submit` - Submit review result
- `GET /reviews/due_counts` - Get count of due reviews
- `GET /reviews/stats` - Get review statistics
- `GET /reviews/progress_stats` - Get detailed progress statistics

### User Features
- `GET /users/<user_id>/preferences` - Get user preferences
- `POST /users/<user_id>/preferences` - Update user preferences
- `GET /users/languages` - Get supported languages
- `POST /users/feedback` - Submit user feedback

### Media
- `GET /audio/<path:text>/<language>` - Get TTS audio
- `POST /generate-illustration` - Generate word illustration
- `GET /illustration` - Get word illustration

### Pronunciation Practice (iOS-specific)
- `POST /users/pronunciation/practice` - Practice pronunciation
- `GET /users/pronunciation/history` - Get pronunciation history
- `GET /users/pronunciation/stats` - Get pronunciation statistics

---

## Web Endpoints

### Static Site Content
- `GET /words` - Get all words for static site
- `GET /words/summary` - Get words summary
- `GET /words/featured` - Get featured words

### Leaderboard
- `GET /users/leaderboard` - Get user leaderboard

### Review Visualization
- `GET /reviews/words/<int:word_id>/forgetting-curve` - Get forgetting curve data
- `GET /reviews/statistics` - Get comprehensive review statistics
- `GET /reviews/weekly_counts` - Get weekly review counts
- `GET /reviews/progress_funnel` - Get progress funnel data
- `GET /reviews/activity` - Get review activity data

---

## Admin Endpoints

### Health & Monitoring
- `GET /health` - Health check endpoint
- `GET /usage` - Usage dashboard

### Maintenance & Testing
- `GET /test-review-intervals` - Test review interval calculations
- `POST /fix_next_review_dates` - Fix review dates (maintenance)

### Legal/Support
- `GET /privacy` - Privacy agreement page
- `GET /support` - Support page

---

## Test Preparation Endpoints

### Test Vocabulary Management
- `GET /api/test-prep/settings` - Get test preparation settings
- `PUT /api/test-prep/settings` - Update test preparation settings
- `POST /api/test-prep/add-words` - Add daily test vocabulary words
- `GET /api/test-prep/stats` - Get test vocabulary statistics

### Background Jobs
- `POST /api/test-prep/run-daily-job` - Manual trigger for daily vocabulary job

---

## Analytics Endpoints

### User Analytics
- `POST /analytics/track` - Track user action
- `GET /analytics/data` - Get analytics data

---

## Bulk Operations Endpoints

### Word Generation
- `POST /api/words/generate` - Generate word definitions in bulk

---

## Endpoint Usage by Client

### iOS App Primary Endpoints
1. Word lookup and saving
2. Review system (next word, submit)
3. User preferences
4. Audio playback
5. Pronunciation practice

### Web Dashboard Primary Endpoints
1. Statistics and visualizations
2. Leaderboard
3. Static word content

### Admin Panel Primary Endpoints
1. Health monitoring
2. Usage statistics
3. Maintenance operations

### Background Services
1. Daily test vocabulary addition
2. Audio generation (worker)
3. Analytics tracking