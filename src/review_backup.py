from datetime import datetime, timedelta
from typing import List, Tuple

def get_next_review_datetime(reviews: List[Tuple[datetime, float]]) -> datetime:
    """
    Calculate next review date using adaptive spaced repetition with continuous success scores.
    Based on SuperMemo SM-2 algorithm with modern adaptations.
    
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
    # E-Factor represents how easy an item is to remember (1.3 to 2.5)
    ef = calculate_efactor(reviews)
    
    # Count successful repetitions (score >= 0.6 threshold for "passing")
    successful_reps = sum(1 for _, score in reviews if score >= 0.6)
    
    # Calculate base interval using SuperMemo progression
    if successful_reps == 0:
        base_interval = 1
    elif successful_reps == 1:
        base_interval = 6
    else:
        # For n > 2: I(n) = I(n-1) * EF
        # Calculate previous interval and multiply by EF
        prev_interval = get_previous_interval(reviews, successful_reps - 1)
        base_interval = prev_interval * ef
    
    # If last score was poor (< 0.6), restart the sequence but keep EF
    if last_success_score < 0.6:
        base_interval = 1
    
    # Apply modern adaptations for flexible scheduling
    
    # 1. Recent performance modifier (last 3-5 reviews)
    recent_reviews = reviews[-5:]
    avg_recent_score = sum(score for _, score in recent_reviews) / len(recent_reviews)
    performance_modifier = calculate_performance_modifier(avg_recent_score)
    
    # 2. Consistency bonus (streak of good performance)
    consistency_bonus = calculate_consistency_bonus(reviews)
    
    # 3. Timing penalty for late reviews
    timing_modifier = calculate_timing_modifier(reviews)
    
    # 4. Gradual score consideration (how close to perfect was the last review)
    score_modifier = calculate_score_modifier(last_success_score)
    
    # Apply all modifiers
    final_interval = (base_interval * 
                     performance_modifier * 
                     consistency_bonus * 
                     timing_modifier * 
                     score_modifier)
    
    # Apply constraints
    final_interval = max(1, min(final_interval, 365))  # Between 1 day and 1 year
    final_interval = round(final_interval)
    
    # Calculate next review date
    next_review = last_review_date + timedelta(days=final_interval)
    
    return next_review


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


def get_previous_interval(reviews: List[Tuple[datetime, float]], target_success_count: int) -> float:
    """Get the interval length for the nth successful review."""
    successful_reviews = []
    for i, (date, score) in enumerate(reviews):
        if score >= 0.6:  # Consider as successful
            if i > 0:
                interval = (date - reviews[i-1][0]).days
                successful_reviews.append(interval)
    
    if target_success_count <= len(successful_reviews):
        return successful_reviews[target_success_count - 1] if target_success_count > 0 else 1
    
    # Fallback: use SuperMemo base progression
    if target_success_count == 1:
        return 1
    elif target_success_count == 2:
        return 6
    else:
        # Estimate based on average E-Factor
        return 6 * (2.0 ** (target_success_count - 2))


def calculate_performance_modifier(avg_score: float) -> float:
    """Modify interval based on recent average performance."""
    if avg_score >= 0.9:      # Excellent performance
        return 1.3
    elif avg_score >= 0.8:    # Good performance
        return 1.15
    elif avg_score >= 0.7:    # Decent performance
        return 1.0
    elif avg_score >= 0.6:    # Struggling but passing
        return 0.8
    else:                     # Poor performance
        return 0.6


def calculate_consistency_bonus(reviews: List[Tuple[datetime, float]]) -> float:
    """Bonus for consecutive good performances."""
    consecutive_good = 0
    for _, score in reversed(reviews):
        if score >= 0.8:  # High threshold for "good"
            consecutive_good += 1
        else:
            break
    
    if consecutive_good >= 5:
        return 1.25
    elif consecutive_good >= 3:
        return 1.15
    else:
        return 1.0


def calculate_timing_modifier(reviews: List[Tuple[datetime, float]]) -> float:
    """Penalty for reviewing too late."""
    if len(reviews) < 2:
        return 1.0
    
    # Calculate if last review was on time
    actual_interval = (reviews[-1][0] - reviews[-2][0]).days
    
    # Estimate expected interval based on position in sequence
    successful_count = sum(1 for _, score in reviews[:-1] if score >= 0.6)
    if successful_count == 0:
        expected_interval = 1
    elif successful_count == 1:
        expected_interval = 6
    else:
        expected_interval = 6 * (2.0 ** (successful_count - 1))  # Rough estimate
    
    delay_ratio = actual_interval / expected_interval if expected_interval > 0 else 1
    
    if delay_ratio <= 1.2:    # On time
        return 1.0
    elif delay_ratio <= 2.0:  # Slightly late
        return 0.95
    elif delay_ratio <= 3.0:  # Moderately late
        return 0.85
    else:                     # Very late
        return 0.7


def calculate_score_modifier(last_score: float) -> float:
    """Fine-tune based on quality of last review."""
    if last_score >= 0.95:    # Perfect or near-perfect
        return 1.1
    elif last_score >= 0.85:  # Very good
        return 1.05
    elif last_score >= 0.75:  # Good
        return 1.0
    elif last_score >= 0.6:   # Acceptable
        return 0.95
    else:                     # Poor (but this case handled earlier)
        return 0.8


# Example usage and test cases
if __name__ == "__main__":
    # Test case 1: First review
    print("Test 1 - First review:")
    reviews1 = []
    next1 = get_next_review_datetime(reviews1)
    print(f"Next review: {next1}")
    print()
    
    # Test case 2: Perfect performance progression
    print("Test 2 - Perfect performance:")
    base_date = datetime(2024, 1, 1, 10, 0)
    reviews2 = [
        (base_date, 1.0),                              # Perfect recall
        (base_date + timedelta(days=1), 0.95),         # Near perfect
        (base_date + timedelta(days=7), 0.9),          # Very good
        (base_date + timedelta(days=19), 0.85),        # Good
    ]
    next2 = get_next_review_datetime(reviews2)
    interval2 = (next2 - reviews2[-1][0]).days
    print(f"Reviews: {[(r[0].strftime('%Y-%m-%d'), r[1]) for r in reviews2]}")
    print(f"Next review: {next2.strftime('%Y-%m-%d')} (interval: {interval2} days)")
    print()
    
    # Test case 3: Mixed performance with failure
    print("Test 3 - Mixed performance with failure:")
    reviews3 = [
        (base_date, 0.8),                              # Good
        (base_date + timedelta(days=1), 0.4),          # Failure - restart sequence
        (base_date + timedelta(days=2), 0.7),          # Acceptable after restart
        (base_date + timedelta(days=8), 0.6),          # Just passing
        (base_date + timedelta(days=15), 0.9),         # Much better
    ]
    next3 = get_next_review_datetime(reviews3)
    interval3 = (next3 - reviews3[-1][0]).days
    print(f"Reviews: {[(r[0].strftime('%Y-%m-%d'), r[1]) for r in reviews3]}")
    print(f"Next review: {next3.strftime('%Y-%m-%d')} (interval: {interval3} days)")
    print()
    
    # Test case 4: Gradual improvement
    print("Test 4 - Gradual improvement:")
    reviews4 = [
        (base_date, 0.6),                              # Just passing
        (base_date + timedelta(days=1), 0.7),          # Improving
        (base_date + timedelta(days=7), 0.8),          # Good
        (base_date + timedelta(days=18), 0.95),        # Excellent
    ]
    next4 = get_next_review_datetime(reviews4)
    interval4 = (next4 - reviews4[-1][0]).days
    print(f"Reviews: {[(r[0].strftime('%Y-%m-%d'), r[1]) for r in reviews4]}")
    print(f"Next review: {next4.strftime('%Y-%m-%d')} (interval: {interval4} days)")
    
    # Test E-Factor calculation
    print(f"\nE-Factor for test 4: {calculate_efactor(reviews4):.2f}")
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
        
        # Calculate E-Factor
        ef = calculate_efactor(reviews)
        
        # Count successful reviews
        successful_count = sum(1 for _, score in reviews if score >= 0.6)
        
        print(f"\nResults:")
        print(f"  E-Factor: {ef:.2f}")
        print(f"  Successful reviews: {successful_count}")
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
    
    # Test 1: First review
    print_test_results("Test 1: First Review", [], base_date)
    
    # Test 2: Perfect learner (high E-Factor development)
    reviews_perfect = [
        (base_date, 1.0),
        (base_date + timedelta(days=1), 1.0),
        (base_date + timedelta(days=7), 0.95),
        (base_date + timedelta(days=25), 0.9),
        (base_date + timedelta(days=85), 0.95),
    ]
    print_test_results("Test 2: Perfect Learner", reviews_perfect, base_date)
    
    # Test 3: Struggling learner (low E-Factor)
    reviews_struggling = [
        (base_date, 0.6),
        (base_date + timedelta(days=1), 0.5),  # Failure - restart
        (base_date + timedelta(days=2), 0.6),
        (base_date + timedelta(days=8), 0.4),  # Failure - restart again
        (base_date + timedelta(days=9), 0.7),
        (base_date + timedelta(days=15), 0.6),
        (base_date + timedelta(days=21), 0.8),
    ]
    print_test_results("Test 3: Struggling Learner", reviews_struggling, base_date)
    
    # Test 4: Improving over time
    reviews_improving = [
        (base_date, 0.5),  # Failure
        (base_date + timedelta(days=1), 0.6),
        (base_date + timedelta(days=7), 0.7),
        (base_date + timedelta(days=19), 0.8),
        (base_date + timedelta(days=58), 0.9),
        (base_date + timedelta(days=158), 0.95),
    ]
    print_test_results("Test 4: Gradual Improvement", reviews_improving, base_date)
    
    # Test 5: Inconsistent performance
    reviews_inconsistent = [
        (base_date, 0.9),
        (base_date + timedelta(days=1), 0.5),  # Sudden drop
        (base_date + timedelta(days=2), 0.8),
        (base_date + timedelta(days=8), 0.3),  # Another drop
        (base_date + timedelta(days=9), 0.7),
        (base_date + timedelta(days=15), 0.9),
        (base_date + timedelta(days=30), 0.6),
    ]
    print_test_results("Test 5: Inconsistent Performance", reviews_inconsistent, base_date)
    
    # Test 6: Late reviews (timing penalty)
    reviews_late = [
        (base_date, 0.8),
        (base_date + timedelta(days=3), 0.8),      # Should have been day 1
        (base_date + timedelta(days=15), 0.8),     # Should have been day 9
        (base_date + timedelta(days=45), 0.8),     # Should have been day 30
        (base_date + timedelta(days=150), 0.8),    # Should have been day 90
    ]
    print_test_results("Test 6: Chronically Late Reviews", reviews_late, base_date)
    
    # Test 7: Overachiever (early and perfect)
    reviews_early = [
        (base_date, 1.0),
        (base_date + timedelta(days=1), 1.0),
        (base_date + timedelta(days=5), 1.0),      # Early (should be day 6)
        (base_date + timedelta(days=18), 1.0),     # Early (should be day 21+)
        (base_date + timedelta(days=55), 1.0),     # Early
        (base_date + timedelta(days=180), 0.95),   # On time, still excellent
    ]
    print_test_results("Test 7: Overachiever (Early Reviews)", reviews_early, base_date)
    
    # Test 8: Recovery after long break
    reviews_comeback = [
        (base_date, 0.9),
        (base_date + timedelta(days=1), 0.9),
        (base_date + timedelta(days=7), 0.85),
        # Long gap - user disappeared for 6 months
        (base_date + timedelta(days=200), 0.4),    # Forgot after long break
        (base_date + timedelta(days=201), 0.7),    # Relearning
        (base_date + timedelta(days=207), 0.8),    # Getting better
        (base_date + timedelta(days=225), 0.9),    # Back to form
    ]
    print_test_results("Test 8: Recovery After Long Break", reviews_comeback, base_date)
    
    # Test 9: Extremely difficult item (E-Factor hits minimum)
    reviews_difficult = [
        (base_date, 0.3),  # Multiple failures
        (base_date + timedelta(days=1), 0.4),
        (base_date + timedelta(days=2), 0.2),
        (base_date + timedelta(days=3), 0.5),
        (base_date + timedelta(days=4), 0.3),
        (base_date + timedelta(days=5), 0.6),  # Finally passes
        (base_date + timedelta(days=11), 0.4), # Back to failure
        (base_date + timedelta(days=12), 0.65),
        (base_date + timedelta(days=18), 0.7),
    ]
    print_test_results("Test 9: Extremely Difficult Item", reviews_difficult, base_date)
    
    # Test 10: Real-world mixed scenario
    reviews_realistic = [
        (base_date, 0.8),                          # Good start
        (base_date + timedelta(days=2), 0.7),      # Bit late, decent
        (base_date + timedelta(days=9), 0.9),      # On time, great
        (base_date + timedelta(days=32), 0.6),     # Late, barely passing
        (base_date + timedelta(days=45), 0.8),     # Getting back on track
        (base_date + timedelta(days=78), 0.85),    # Good progress
        (base_date + timedelta(days=180), 0.4),    # Long gap, forgot
        (base_date + timedelta(days=181), 0.75),   # Quick recovery
        (base_date + timedelta(days=188), 0.9),    # Solid
    ]
    print_test_results("Test 10: Realistic Mixed Scenario", reviews_realistic, base_date)
    
    # Summary comparison
    print("\n" + "="*60)
    print("SUMMARY COMPARISON")
    print("="*60)
    
    test_cases = [
        ("Perfect Learner", reviews_perfect),
        ("Struggling Learner", reviews_struggling),
        ("Gradual Improvement", reviews_improving),
        ("Inconsistent", reviews_inconsistent),
        ("Late Reviews", reviews_late),
        ("Overachiever", reviews_early),
        ("After Long Break", reviews_comeback),
        ("Difficult Item", reviews_difficult),
        ("Realistic Mixed", reviews_realistic),
    ]
    
    print(f"{'Scenario':<20} {'E-Factor':<10} {'Success%':<10} {'Next Interval':<15}")
    print("-" * 60)
    
    for name, reviews in test_cases:
        if reviews:
            ef = calculate_efactor(reviews)
            success_rate = sum(1 for _, score in reviews if score >= 0.6) / len(reviews) * 100
            next_review = get_next_review_datetime(reviews)
            interval = (next_review - reviews[-1][0]).days
            print(f"{name:<20} {ef:<10.2f} {success_rate:<10.1f} {interval:<15}")
    
    print("\nKey Insights:")
    print("- Perfect learners develop high E-Factors (2.5+) and long intervals")
    print("- Struggling learners get capped at minimum E-Factor (1.3) with short intervals")
    print("- Late reviews are penalized with shorter next intervals")
    print("- The algorithm adapts to individual item difficulty over time")
    print("- Failures restart the interval sequence but preserve learned E-Factor")