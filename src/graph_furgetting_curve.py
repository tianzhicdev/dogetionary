import plotly.graph_objects as go
import plotly.express as px
from datetime import datetime, timedelta
from typing import List, Tuple
import numpy as np

def graph_forgetting_curve(reviews: List[Tuple[datetime, float]]):
    """
    Create an interactive Plotly graph showing the forgetting curve based on review history.
    
    Args:
        reviews: List of (review_datetime, success_score) tuples, ordered chronologically
                success_score: 0.0 (complete failure) to 1.0 (perfect recall)
    """
    if not reviews:
        print("No reviews to plot")
        return
    
    # Sort reviews by date
    reviews = sorted(reviews, key=lambda x: x[0])
    
    fig = go.Figure()
    
    # Start from first review date
    start_date = reviews[0][0]
    end_date = reviews[-1][0] + timedelta(days=30)  # Show 30 days after last review
    
    # Generate time points for smooth curve
    total_days = (end_date - start_date).days
    time_points = []
    retention_values = []
    
    # Create detailed time series
    for day in range(total_days + 1):
        current_date = start_date + timedelta(days=day)
        time_points.append(current_date)
        
        # Calculate retention at this point in time
        retention = calculate_retention_at_date(current_date, reviews)
        retention_values.append(retention * 100)  # Convert to percentage
    
    # Plot the main forgetting curve
    fig.add_trace(go.Scatter(
        x=time_points,
        y=retention_values,
        mode='lines',
        name='Memory Retention',
        line=dict(color='#2E86AB', width=3),
        hovertemplate='<b>Date:</b> %{x}<br><b>Retention:</b> %{y:.1f}%<extra></extra>'
    ))
    
    # Add review points
    review_dates = [r[0] for r in reviews]
    review_scores = [r[1] * 100 for r in reviews]  # Convert to percentage
    
    # Calculate retention just before each review (except the first)
    pre_review_retention = []
    for i, (date, score) in enumerate(reviews):
        if i == 0:
            pre_review_retention.append(100)  # First review starts at 100%
        else:
            retention = calculate_retention_at_date(date, reviews[:i])
            pre_review_retention.append(retention * 100)
    
    # Add review markers
    fig.add_trace(go.Scatter(
        x=review_dates,
        y=pre_review_retention,
        mode='markers',
        name='Pre-Review Retention',
        marker=dict(
            size=12,
            color='#A23B72',
            symbol='circle',
            line=dict(width=2, color='white')
        ),
        hovertemplate='<b>Review Date:</b> %{x}<br><b>Pre-Review Retention:</b> %{y:.1f}%<br><b>Review Score:</b> %{text:.1f}%<extra></extra>',
        text=review_scores
    ))
    
    # Add review score markers (post-review boost)
    post_review_retention = [calculate_post_review_retention(score) * 100 for _, score in reviews]
    
    fig.add_trace(go.Scatter(
        x=review_dates,
        y=post_review_retention,
        mode='markers',
        name='Post-Review Boost',
        marker=dict(
            size=10,
            color='#F18F01',
            symbol='star',
            line=dict(width=1, color='white')
        ),
        hovertemplate='<b>Review Date:</b> %{x}<br><b>Post-Review Retention:</b> %{y:.1f}%<br><b>Review Score:</b> %{text:.1f}%<extra></extra>',
        text=review_scores
    ))
    
    # Add vertical lines for reviews
    for i, (date, score) in enumerate(reviews):
        fig.add_shape(
            type="line",
            x0=date, x1=date,
            y0=0, y1=105,
            line=dict(color='rgba(255,0,0,0.3)', width=1, dash='dash'),
        )
        fig.add_annotation(
            x=date,
            y=105,
            text=f"Review {i+1}",
            showarrow=False,
            yanchor="bottom"
        )
    
    # Add next review prediction
    if len(reviews) > 0:
        next_review_date = get_next_review_datetime(reviews)
        current_retention = calculate_retention_at_date(next_review_date, reviews)
        
        fig.add_trace(go.Scatter(
            x=[next_review_date],
            y=[current_retention * 100],
            mode='markers',
            name='Next Scheduled Review',
            marker=dict(
                size=15,
                color='#C73E1D',
                symbol='diamond',
                line=dict(width=3, color='white')
            ),
            hovertemplate='<b>Next Review:</b> %{x}<br><b>Predicted Retention:</b> %{y:.1f}%<extra></extra>'
        ))
        
        fig.add_shape(
            type="line",
            x0=next_review_date, x1=next_review_date,
            y0=0, y1=105,
            line=dict(color='rgba(199,62,29,0.5)', width=2, dash='dot'),
        )
        fig.add_annotation(
            x=next_review_date,
            y=0,
            text="Next Review",
            showarrow=False,
            yanchor="top"
        )
    
    # Customize layout
    fig.update_layout(
        title={
            'text': 'Memory Retention and Forgetting Curve',
            'x': 0.5,
            'xanchor': 'center',
            'font': {'size': 20}
        },
        xaxis=dict(
            title='Date',
            showgrid=True,
            gridcolor='rgba(128,128,128,0.2)'
        ),
        yaxis=dict(
            title='Memory Retention (%)',
            range=[0, 105],
            showgrid=True,
            gridcolor='rgba(128,128,128,0.2)'
        ),
        hovermode='closest',
        showlegend=True,
        legend=dict(
            yanchor="top",
            y=0.99,
            xanchor="left",
            x=0.01
        ),
        plot_bgcolor='white',
        paper_bgcolor='white',
        font=dict(size=12),
        height=600
    )
    
    # Add annotations for retention thresholds
    fig.add_hline(
        y=80,
        line=dict(color='rgba(0,128,0,0.3)', width=1, dash='dash'),
    )
    fig.add_annotation(
        x=time_points[-1],  # Right side of the graph
        y=80,
        text="Good Retention (80%)",
        showarrow=False,
        xanchor="right",
        font=dict(size=10, color='green'),
        bgcolor='rgba(255,255,255,0.8)',
        bordercolor='green',
        borderwidth=1
    )
    
    fig.add_hline(
        y=60,
        line=dict(color='rgba(255,165,0,0.3)', width=1, dash='dash'),
    )
    fig.add_annotation(
        x=time_points[-1],  # Right side of the graph
        y=60,
        text="Acceptable Retention (60%)",
        showarrow=False,
        xanchor="right",
        font=dict(size=10, color='orange'),
        bgcolor='rgba(255,255,255,0.8)',
        bordercolor='orange',
        borderwidth=1
    )
    
    return fig

def calculate_retention_at_date(target_date: datetime, reviews: List[Tuple[datetime, float]]) -> float:
    """
    Calculate memory retention at a specific date based on review history.
    Uses exponential decay with reinforcement from reviews.
    """
    if not reviews:
        return 0.0
    
    # Find the most recent review before or at target_date
    relevant_reviews = [(date, score) for date, score in reviews if date <= target_date]
    
    if not relevant_reviews:
        return 0.0
    
    # Start with the most recent review
    last_review_date, last_review_score = relevant_reviews[-1]
    
    # Calculate days since last review
    days_since_review = (target_date - last_review_date).days
    
    if days_since_review < 0:
        days_since_review = 0
    
    # Base retention after review (based on how well they performed)
    base_retention = calculate_post_review_retention(last_review_score)
    
    # Calculate decay rate based on review history
    # More reviews = slower decay (stronger memory consolidation)
    num_reviews = len(relevant_reviews)
    
    # Adaptive decay rate: more reviews = slower forgetting
    if num_reviews == 1:
        decay_rate = 0.15  # Fast decay for first exposure
    elif num_reviews == 2:
        decay_rate = 0.10  # Slower decay after first review
    elif num_reviews <= 4:
        decay_rate = 0.07  # Even slower for repeated reviews
    else:
        decay_rate = 0.04  # Very slow decay for well-established memories
    
    # Apply exponential decay
    retention = base_retention * np.exp(-decay_rate * days_since_review)
    
    return max(0.0, min(1.0, retention))

def calculate_post_review_retention(review_score: float) -> float:
    """
    Calculate retention immediately after a review based on performance.
    Higher scores lead to better initial retention.
    """
    if review_score >= 0.9:
        return 0.98  # Excellent performance
    elif review_score >= 0.8:
        return 0.95  # Very good
    elif review_score >= 0.7:
        return 0.90  # Good
    elif review_score >= 0.6:
        return 0.85  # Acceptable
    elif review_score >= 0.4:
        return 0.75  # Poor but some learning
    else:
        return 0.60  # Very poor performance

def get_next_review_datetime(reviews: List[Tuple[datetime, float]]) -> datetime:
    """
    Calculate when the next review should occur based on spaced repetition principles.
    Uses the number of reviews and performance to determine optimal spacing.
    """
    if not reviews:
        return datetime.now() + timedelta(days=1)
    
    last_review_date, last_score = reviews[-1]
    num_reviews = len(reviews)
    
    # Calculate interval based on number of successful reviews
    # Uses a modified Fibonacci-like sequence for spacing
    if num_reviews == 1:
        base_interval = 1  # 1 day after first review
    elif num_reviews == 2:
        base_interval = 3  # 3 days after second review
    elif num_reviews == 3:
        base_interval = 7  # 1 week after third review
    elif num_reviews == 4:
        base_interval = 14  # 2 weeks after fourth review
    elif num_reviews == 5:
        base_interval = 30  # 1 month after fifth review
    else:
        base_interval = 60  # 2 months for well-established memories
    
    # Adjust interval based on performance
    if last_score >= 0.9:
        interval_multiplier = 1.3  # Extend interval for excellent performance
    elif last_score >= 0.8:
        interval_multiplier = 1.1  # Slightly extend for good performance
    elif last_score >= 0.6:
        interval_multiplier = 1.0  # Keep standard interval
    elif last_score >= 0.4:
        interval_multiplier = 0.6  # Reduce interval for poor performance
    else:
        interval_multiplier = 0.3  # Much shorter interval for very poor performance
    
    # Calculate final interval
    interval_days = int(base_interval * interval_multiplier)
    interval_days = max(1, interval_days)  # Minimum 1 day interval
    
    return last_review_date + timedelta(days=interval_days)


# Example usage and testing
if __name__ == "__main__":
    # Test with sample data
    base_date = datetime(2024, 1, 1, 10, 0)
    
    sample_reviews = [
        (base_date, 0.8),                              # Good start
        (base_date + timedelta(days=1), 0.9),          # Better next day  
        (base_date + timedelta(days=4), 0.85),         # Review after 3 days
        (base_date + timedelta(days=11), 0.9),         # Review after 7 days
        (base_date + timedelta(days=25), 0.95),        # Review after 14 days
    ]
    
    print("Creating forgetting curve visualization...")
    fig = graph_forgetting_curve(sample_reviews)
    
    if fig:
        fig.show()
        
        # Also save as HTML
        fig.write_html("forgetting_curve.html")
        print("Graph saved as 'forgetting_curve.html'")
        
        # Print some statistics
        print(f"\nReview Statistics:")
        print(f"Total reviews: {len(sample_reviews)}")
        print(f"Average score: {np.mean([score for _, score in sample_reviews]):.2f}")
        print(f"Score trend: {sample_reviews[-1][1] - sample_reviews[0][1]:+.2f}")
        
        # Show next review prediction
        next_review = get_next_review_datetime(sample_reviews)
        days_until_next = (next_review - sample_reviews[-1][0]).days
        print(f"Next review in: {days_until_next} days")