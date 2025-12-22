# Bundle Video Coverage Analysis

This directory contains tools to analyze video coverage for vocabulary bundles.

## Quick Start

### Using Python Script (Recommended)

```bash
# Check coverage on local database
python3 scripts/check_bundle_coverage.py

# Export to CSV
python3 scripts/check_bundle_coverage.py --output coverage.csv

# Check production database
python3 scripts/check_bundle_coverage.py --db-url "postgresql://user:pass@host:port/dbname"
```

### Using SQL File

```bash
# Local database
cat scripts/bundle_video_coverage.sql | docker-compose exec -T postgres psql -U dogeuser -d dogetionary

# Production database
psql -U <user> -d <database> -f scripts/bundle_video_coverage.sql
```

## Current Coverage (Local)

As of the last check:

| Bundle            | Total Words | Words with Videos | Coverage % |
|-------------------|-------------|-------------------|------------|
| demo              | 24          | 24                | 100.00%    |
| ielts_beginner    | 1,939       | 394               | 20.32%     |
| everyday_english  | 2,084       | 418               | 20.06%     |
| toefl_beginner    | 2,193       | 433               | 19.74%     |
| business_english  | 1,621       | 300               | 18.51%     |
| ielts_intermediate| 2,893       | 469               | 16.21%     |
| toefl_intermediate| 3,834       | 592               | 15.44%     |
| ielts_advanced    | 3,543       | 379               | 10.70%     |
| toefl_advanced    | 5,742       | 560               | 9.75%      |

## Output Columns

- **bundle_name**: Vocabulary bundle identifier
- **total_words**: Total number of words in the bundle
- **words_with_videos**: Number of words that have at least one video
- **total_video_mappings**: Total number of video-word associations (some words have multiple videos)
- **coverage_pct**: Percentage of words with videos
- **avg_videos_per_word**: Average videos per word (across all words in bundle)
- **avg_videos_per_word_with_video**: Average videos per word (only words that have videos)

## Understanding the Metrics

### Coverage Percentage
Percentage of words in the bundle that have at least one video associated with them.

### Average Videos per Word
Total video mappings divided by total words. Lower values mean many words have no videos.

### Average Videos per Word with Video
Average number of videos for words that have at least one video. Shows redundancy/quality for covered words.

## Next Steps to Improve Coverage

1. **Focus on low-coverage bundles**: toefl_advanced (9.75%), ielts_advanced (10.70%)
2. **Target specific words**: Run query to find words without videos in priority bundles
3. **Use the find_videos.py script**: Generate videos for uncovered words

```bash
# Example: Generate videos for toefl_advanced bundle
python3 scripts/find_videos.py --bundle toefl_advanced --max-videos 100 --backend-url http://localhost:5001
```

## Files

- `bundle_video_coverage.sql`: Raw SQL query for database analysis
- `check_bundle_coverage.py`: Python script with formatting and CSV export
- `README_BUNDLE_COVERAGE.md`: This documentation file
