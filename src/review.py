from datetime import datetime, timedelta
from typing import List, Tuple

def get_next_review_datetime(reviews: List[Tuple[datetime, float]]) -> datetime:
    """
    Calculate next review date using adaptive spaced repetition with continuous success scores.
    Modified to prevent consecutive successful reviews from always scheduling tomorrow.
    
    Args:
        reviews: List of (review_datetime, success_score) tuples, ordered chronologically
                success_score: 0.0 (complete failure) to 1.0 (perfect recall)
        
    Returns:
        datetime: Next recommended review date
    """
    if not reviews:
        # First review - start immediately
        return datetime.now()
    
    # Sort reviews by date to ensure chronological order
    reviews = sorted(reviews, key=lambda x: x[0])
    last_review_date = reviews[-1][0]
    last_success_score = reviews[-1][1]
    
    # Initialize or calculate E-Factor (Easiness Factor) from SuperMemo
    ef = calculate_efactor(reviews)
    
    # Count consecutive successful reviews from the end (key change!)
    consecutive_successes = count_consecutive_successes(reviews)
    
    # Count total successful repetitions for overall progress tracking
    total_successful_reps = sum(1 for _, score in reviews if score >= 0.6)
    
    # Calculate base interval using MODIFIED SuperMemo progression
    if consecutive_successes == 0:
        # Only reset to 1 day for actual failures, not just any score < 0.6
        if last_success_score < 0.4:  # True failure threshold
            base_interval = 1
        else:
            base_interval = 2  # Give struggling performance a bit more time
    elif consecutive_successes == 1:
        base_interval = 3  # Faster than original 6 days for first success
    elif consecutive_successes == 2:
        base_interval = 7  # One week
    else:
        # For n >= 3: Use exponential growth based on consecutive successes
        # This is the key fix - base interval on consecutive successes, not total
        if consecutive_successes <= 5:
            # Early stage: aggressive growth
            base_interval = 7 * (2.0 ** (consecutive_successes - 2))
        else:
            # Later stage: use E-Factor for fine-tuning
            prev_interval = get_previous_interval_improved(reviews)
            base_interval = prev_interval * ef
    
    # Apply modern adaptations for flexible scheduling (with constraints)
    
    # 1. Recent performance modifier (but don't let it reduce interval too much)
    recent_reviews = reviews[-min(5, len(reviews)):]
    avg_recent_score = sum(score for _, score in recent_reviews) / len(recent_reviews)
    performance_modifier = calculate_performance_modifier_improved(avg_recent_score, consecutive_successes)
    
    # 2. Consistency bonus (reward streaks more aggressively)
    consistency_bonus = calculate_consistency_bonus_improved(consecutive_successes)
    
    # 3. Timing modifier (less punitive)
    timing_modifier = calculate_timing_modifier_improved(reviews)
    
    # 4. Score modifier (reward high scores)
    score_modifier = calculate_score_modifier_improved(last_success_score, consecutive_successes)
    
    # Apply all modifiers
    final_interval = (base_interval * 
                     performance_modifier * 
                     consistency_bonus * 
                     timing_modifier * 
                     score_modifier)
    
    # Apply constraints with minimum based on consecutive successes
    min_interval = min(consecutive_successes + 1, 7)  # Minimum grows with success streak
    final_interval = max(min_interval, min(final_interval, 365))
    final_interval = round(final_interval)
    
    # Calculate next review date
    next_review = last_review_date + timedelta(days=final_interval)
    
    return next_review


def count_consecutive_successes(reviews: List[Tuple[datetime, float]]) -> int:
    """Count consecutive successful reviews from the most recent backwards."""
    consecutive = 0
    for _, score in reversed(reviews):
        if score >= 0.6:  # Success threshold
            consecutive += 1
        else:
            break
    return consecutive


def get_previous_interval_improved(reviews: List[Tuple[datetime, float]]) -> float:
    """Get the most recent interval between successful reviews."""
    if len(reviews) < 2:
        return 7  # Default base interval
    
    # Find the last successful review before the current one
    for i in range(len(reviews) - 2, -1, -1):
        if reviews[i][1] >= 0.6:  # Previous successful review
            interval = (reviews[-1][0] - reviews[i][0]).days
            return max(interval, 1)  # Ensure positive interval
    
    # If no previous successful review found, use default progression
    return 7


def calculate_performance_modifier_improved(avg_score: float, consecutive_successes: int) -> float:
    """
    Modify interval based on recent performance, but be less aggressive about reducing intervals
    when there are consecutive successes.
    """
    if consecutive_successes >= 3:
        # Don't penalize too much if user has a good streak going
        if avg_score >= 0.8:
            return 1.2
        elif avg_score >= 0.7:
            return 1.1
        elif avg_score >= 0.6:
            return 1.0  # Don't reduce interval for passing scores in a streak
        else:
            return 0.9  # Gentle reduction instead of aggressive
    else:
        # Original logic for early reviews
        if avg_score >= 0.9:
            return 1.3
        elif avg_score >= 0.8:
            return 1.15
        elif avg_score >= 0.7:
            return 1.0
        elif avg_score >= 0.6:
            return 0.9  # Less aggressive than original 0.8
        else:
            return 0.7  # Less aggressive than original 0.6


def calculate_consistency_bonus_improved(consecutive_successes: int) -> float:
    """More aggressive bonus for consecutive successes to push intervals out."""
    if consecutive_successes >= 10:
        return 1.5  # Big bonus for long streaks
    elif consecutive_successes >= 7:
        return 1.4
    elif consecutive_successes >= 5:
        return 1.3
    elif consecutive_successes >= 3:
        return 1.2
    elif consecutive_successes >= 2:
        return 1.1
    else:
        return 1.0


def calculate_timing_modifier_improved(reviews: List[Tuple[datetime, float]]) -> float:
    """Less punitive timing modifier - don't reduce intervals as aggressively."""
    if len(reviews) < 2:
        return 1.0
    
    # Calculate if last review was on time (simplified)
    actual_interval = (reviews[-1][0] - reviews[-2][0]).days
    
    # Be more lenient about what constitutes "late"
    if actual_interval <= 14:  # Within 2 weeks is considered reasonable
        return 1.0
    elif actual_interval <= 30:  # Within a month
        return 0.95
    elif actual_interval <= 90:  # Within 3 months
        return 0.9
    else:  # Very late
        return 0.8  # Less punitive than original


def calculate_score_modifier_improved(last_score: float, consecutive_successes: int) -> float:
    """
    Reward high scores more aggressively, especially with consecutive successes.
    """
    base_modifier = 1.0
    
    if last_score >= 0.95:
        base_modifier = 1.15
    elif last_score >= 0.85:
        base_modifier = 1.1
    elif last_score >= 0.75:
        base_modifier = 1.05
    elif last_score >= 0.6:
        base_modifier = 1.0
    else:
        base_modifier = 0.85
    
    # Additional bonus for consecutive successes with high scores
    if consecutive_successes >= 3 and last_score >= 0.8:
        base_modifier *= 1.1
    
    return base_modifier


def calculate_efactor(reviews: List[Tuple[datetime, float]]) -> float:
    """
    Calculate E-Factor based on SuperMemo SM-2 algorithm.
    EF' = EF + (0.1 - (5-q)*(0.08+(5-q)*0.02))
    
    Adapted for 0-1 scale by converting: q = score * 5
    """
    ef = 2.5  # Initial E-Factor
    
    for _, score in reviews:
        # Convert 0-1 score to SuperMemo's 0-5 scale
        q = score * 5
        
        # Apply SuperMemo E-Factor formula
        ef = ef + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        
        # Enforce minimum E-Factor of 1.3
        ef = max(1.3, ef)
    
    return ef


# Test the improved algorithm
if __name__ == "__main__":
    def print_test_results(test_name, reviews, base_date):
        """Helper function to print detailed test results."""
        print(f"\n{test_name}")
        print("=" * len(test_name))
        
        if not reviews:
            next_review = get_next_review_datetime(reviews)
            print(f"First review scheduled for: {next_review}")
            return
        
        # Print review history
        print("Review History:")
        for i, (date, score) in enumerate(reviews):
            days_since_start = (date - base_date).days
            score_desc = get_score_description(score)
            print(f"  Day {days_since_start:2d}: Score {score:.2f} ({score_desc})")
        
        # Calculate next review
        next_review = get_next_review_datetime(reviews)
        last_date = reviews[-1][0]
        interval = (next_review - last_date).days
        
        # Calculate metrics
        ef = calculate_efactor(reviews)
        consecutive_successes = count_consecutive_successes(reviews)
        total_successful = sum(1 for _, score in reviews if score >= 0.6)
        
        print(f"\nResults:")
        print(f"  E-Factor: {ef:.2f}")
        print(f"  Consecutive successes: {consecutive_successes}")
        print(f"  Total successful reviews: {total_successful}")
        print(f"  Next review: {next_review.strftime('%Y-%m-%d')} ({interval} days from last)")
        print(f"  Total days since start: {(next_review - base_date).days}")
    
    def get_score_description(score):
        """Convert score to descriptive text."""
        if score >= 0.95:
            return "Perfect"
        elif score >= 0.85:
            return "Excellent"
        elif score >= 0.75:
            return "Good"
        elif score >= 0.6:
            return "Acceptable"
        elif score >= 0.4:
            return "Poor"
        else:
            return "Failure"
    
    base_date = datetime(2024, 1, 1, 10, 0)
    
    # Test case: Your specific problem - consecutive successful reviews
    print("TESTING THE MAIN ISSUE: Consecutive Successful Reviews")
    print("="*60)
    
    # Simulate a user reviewing the same word repeatedly with good scores
    consecutive_success_reviews = [
        (base_date, 0.8),                              # Good start
        (base_date + timedelta(days=1), 0.9),          # Better next day
        (base_date + timedelta(days=2), 0.85),         # Still good next day
        (base_date + timedelta(days=3), 0.9),          # Great again next day
        (base_date + timedelta(days=4), 0.95),         # Perfect next day
    ]
    
    print("ORIGINAL ALGORITHM BEHAVIOR:")
    print("Problem: Each successful review still schedules next review for tomorrow")
    print("\nWith the IMPROVED algorithm:")
    print_test_results("Consecutive Successful Reviews", consecutive_success_reviews, base_date)
    
    # Show progression of intervals
    print(f"\nInterval Progression Analysis:")
    temp_reviews = []
    for i, (date, score) in enumerate(consecutive_success_reviews):
        temp_reviews.append((date, score))
        if i > 0:  # Skip first review
            next_review = get_next_review_datetime(temp_reviews)
            interval = (next_review - date).days
            consecutive = count_consecutive_successes(temp_reviews)
            print(f"  After review {i+1} (score {score:.2f}): Next in {interval} days (consecutive: {consecutive})")
    
    # Test more scenarios
    print_test_results("Test: Perfect Learner Gets Longer Intervals", [
        (base_date, 1.0),
        (base_date + timedelta(days=3), 1.0),
        (base_date + timedelta(days=10), 0.95),
        (base_date + timedelta(days=24), 0.9),
        (base_date + timedelta(days=72), 0.95),
    ], base_date)
    
    print_test_results("Test: Recovery Doesn't Over-Penalize", [
        (base_date, 0.8),
        (base_date + timedelta(days=1), 0.3),  # One failure
        (base_date + timedelta(days=2), 0.8),  # Back to good
        (base_date + timedelta(days=5), 0.9),  # Even better
        (base_date + timedelta(days=12), 0.85), # Consistent
    ], base_date)