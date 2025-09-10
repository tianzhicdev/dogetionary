#!/usr/bin/env python3
"""
Demo Data Script for Dogetionary
Adds sample saved words and review records for demo user
"""

import psycopg2
import os
import sys
from datetime import datetime, timedelta
import random

# Add src to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'src'))
from review import get_next_review_datetime

# Database connection
def get_db_connection():
    return psycopg2.connect(
        host=os.getenv('DB_HOST', 'localhost'),
        database=os.getenv('DB_NAME', 'dogetionary'),
        user=os.getenv('DB_USER', 'dogetionary_user'),
        password=os.getenv('DB_PASSWORD', 'your_password'),
        port=os.getenv('DB_PORT', 5432)
    )

# Demo user
DEMO_USER_ID = 'B7734CA0-8D9E-47B4-BAA2-ABE6957D4B09'
LEARNING_LANGUAGE = 'en'

# Demo words with varying difficulty and review patterns
DEMO_WORDS = [
    # Easy words (learned well)
    {'word': 'hello', 'success_rate': 0.9, 'review_count': 15},
    {'word': 'goodbye', 'success_rate': 0.85, 'review_count': 12},
    {'word': 'thank', 'success_rate': 0.95, 'review_count': 18},
    {'word': 'please', 'success_rate': 0.9, 'review_count': 14},
    {'word': 'water', 'success_rate': 0.88, 'review_count': 16},
    
    # Medium words (learning progress)
    {'word': 'beautiful', 'success_rate': 0.7, 'review_count': 10},
    {'word': 'important', 'success_rate': 0.75, 'review_count': 8},
    {'word': 'understand', 'success_rate': 0.65, 'review_count': 12},
    {'word': 'remember', 'success_rate': 0.8, 'review_count': 9},
    {'word': 'different', 'success_rate': 0.72, 'review_count': 11},
    
    # Harder words (struggling)
    {'word': 'serendipity', 'success_rate': 0.4, 'review_count': 7},
    {'word': 'ephemeral', 'success_rate': 0.3, 'review_count': 6},
    {'word': 'ubiquitous', 'success_rate': 0.45, 'review_count': 8},
    {'word': 'pernicious', 'success_rate': 0.35, 'review_count': 5},
    {'word': 'perspicacious', 'success_rate': 0.25, 'review_count': 4},
    
    # Recently added (few reviews)
    {'word': 'magnificent', 'success_rate': 0.6, 'review_count': 3},
    {'word': 'adventure', 'success_rate': 0.8, 'review_count': 2},
    {'word': 'knowledge', 'success_rate': 0.5, 'review_count': 4},
    {'word': 'creativity', 'success_rate': 0.7, 'review_count': 3},
    {'word': 'friendship', 'success_rate': 0.85, 'review_count': 2},
    
    # Due for review (varied schedule)
    {'word': 'challenge', 'success_rate': 0.6, 'review_count': 6},
    {'word': 'opportunity', 'success_rate': 0.75, 'review_count': 5},
    {'word': 'curiosity', 'success_rate': 0.8, 'review_count': 4},
    {'word': 'perseverance', 'success_rate': 0.55, 'review_count': 7},
    {'word': 'imagination', 'success_rate': 0.7, 'review_count': 5},
]

def add_saved_words():
    """Add saved words to database"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    print(f"Adding {len(DEMO_WORDS)} demo words for user {DEMO_USER_ID}...")
    
    # Clear existing data for demo user
    cur.execute("DELETE FROM reviews WHERE user_id = %s", (DEMO_USER_ID,))
    cur.execute("DELETE FROM saved_words WHERE user_id = %s", (DEMO_USER_ID,))
    
    word_ids = {}
    
    for word_info in DEMO_WORDS:
        word = word_info['word']
        # Add words with staggered creation dates (last 30 days)
        days_ago = random.randint(1, 30)
        created_at = datetime.now() - timedelta(days=days_ago)
        
        cur.execute("""
            INSERT INTO saved_words (user_id, word, learning_language, created_at)
            VALUES (%s, %s, %s, %s)
            RETURNING id
        """, (DEMO_USER_ID, word, LEARNING_LANGUAGE, created_at))
        
        word_id = cur.fetchone()[0]
        word_ids[word] = word_id
        print(f"  Added word: {word} (ID: {word_id})")
    
    conn.commit()
    cur.close()
    conn.close()
    
    return word_ids

def add_review_records(word_ids):
    """Add realistic review records with spaced repetition"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    print("\nAdding review records...")
    
    for word_info in DEMO_WORDS:
        word = word_info['word']
        word_id = word_ids[word]
        success_rate = word_info['success_rate']
        review_count = word_info['review_count']
        
        print(f"  Adding {review_count} reviews for '{word}' (success rate: {success_rate:.0%})")
        
        # Generate review history
        reviews = []
        review_times = []
        
        # Start reviews a few days after word was saved
        start_date = datetime.now() - timedelta(days=random.randint(20, 29))
        current_date = start_date
        
        for i in range(review_count):
            # Determine if this review was successful based on success rate
            is_success = random.random() < success_rate
            
            # Add some randomness to review timing
            if i == 0:
                # First review within 1-2 days
                current_date += timedelta(hours=random.randint(6, 48))
            else:
                # Use spaced repetition to calculate next review
                numeric_reviews = []
                for review_time, response in zip(review_times, reviews):
                    numeric_score = 0.9 if response else 0.1
                    numeric_reviews.append((review_time, numeric_score))
                
                if numeric_reviews:
                    next_review_time = get_next_review_datetime(numeric_reviews)
                    # Add some randomness (±6 hours)
                    random_offset = timedelta(hours=random.randint(-6, 6))
                    current_date = next_review_time + random_offset
                else:
                    current_date += timedelta(days=1)
            
            reviews.append(is_success)
            review_times.append(current_date)
            
            # Insert review record
            cur.execute("""
                INSERT INTO reviews (user_id, word_id, response, reviewed_at)
                VALUES (%s, %s, %s, %s)
            """, (DEMO_USER_ID, word_id, is_success, current_date))
        
        # Calculate next review date for the last review
        if reviews:
            numeric_reviews = []
            for review_time, response in zip(review_times, reviews):
                numeric_score = 0.9 if response else 0.1
                numeric_reviews.append((review_time, numeric_score))
            
            next_review_date = get_next_review_datetime(numeric_reviews)
            
            # Update the last review with next_review_date
            cur.execute("""
                UPDATE reviews 
                SET next_review_date = %s 
                WHERE user_id = %s AND word_id = %s 
                ORDER BY reviewed_at DESC 
                LIMIT 1
            """, (next_review_date, DEMO_USER_ID, word_id))
    
    conn.commit()
    cur.close()
    conn.close()

def add_user_preferences():
    """Ensure user preferences exist"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    print(f"\nSetting user preferences for {DEMO_USER_ID}...")
    
    cur.execute("""
        INSERT INTO user_preferences (user_id, learning_language, native_language)
        VALUES (%s, %s, %s)
        ON CONFLICT (user_id) DO UPDATE SET
            learning_language = EXCLUDED.learning_language,
            native_language = EXCLUDED.native_language
    """, (DEMO_USER_ID, 'en', 'zh'))
    
    conn.commit()
    cur.close()
    conn.close()

def print_summary():
    """Print summary of added data"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    # Count saved words
    cur.execute("SELECT COUNT(*) FROM saved_words WHERE user_id = %s", (DEMO_USER_ID,))
    word_count = cur.fetchone()[0]
    
    # Count reviews
    cur.execute("SELECT COUNT(*) FROM reviews WHERE user_id = %s", (DEMO_USER_ID,))
    review_count = cur.fetchone()[0]
    
    # Count due for review
    cur.execute("""
        SELECT COUNT(DISTINCT sw.id)
        FROM saved_words sw
        JOIN reviews r ON sw.id = r.word_id
        WHERE sw.user_id = %s 
        AND r.next_review_date <= NOW()
        AND r.id = (
            SELECT MAX(id) FROM reviews r2 
            WHERE r2.word_id = sw.id
        )
    """, (DEMO_USER_ID,))
    due_count = cur.fetchone()[0]
    
    # Get recent activity
    cur.execute("""
        SELECT COUNT(*) FROM reviews 
        WHERE user_id = %s 
        AND reviewed_at >= NOW() - INTERVAL '7 days'
    """, (DEMO_USER_ID,))
    recent_reviews = cur.fetchone()[0]
    
    cur.close()
    conn.close()
    
    print(f"\n=== DEMO DATA SUMMARY ===")
    print(f"User ID: {DEMO_USER_ID}")
    print(f"Saved words: {word_count}")
    print(f"Total reviews: {review_count}")
    print(f"Words due for review: {due_count}")
    print(f"Reviews in last 7 days: {recent_reviews}")
    print(f"========================")

def main():
    print("🐕 Dogetionary Demo Data Generator")
    print("Adding demo data for comprehensive testing...\n")
    
    try:
        # Add user preferences
        add_user_preferences()
        
        # Add saved words
        word_ids = add_saved_words()
        
        # Add review records
        add_review_records(word_ids)
        
        # Print summary
        print_summary()
        
        print("\n✅ Demo data added successfully!")
        print("You can now test the app with realistic review patterns.")
        
    except Exception as e:
        print(f"\n❌ Error adding demo data: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())