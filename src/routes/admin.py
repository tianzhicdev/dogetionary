from flask import Blueprint
from handlers.admin import (
    test_review_intervals, fix_next_review_dates, privacy_agreement,
    support_page, health_check
)
from handlers.usage_dashboard import get_usage_dashboard

admin_bp = Blueprint('admin', __name__)

# Health and monitoring
admin_bp.route('/health', methods=['GET'])(health_check)
admin_bp.route('/usage', methods=['GET'])(get_usage_dashboard)

# Testing and debugging
admin_bp.route('/test-review-intervals', methods=['GET'])(test_review_intervals)
admin_bp.route('/fix_next_review_dates', methods=['POST'])(fix_next_review_dates)

# Static pages
admin_bp.route('/privacy', methods=['GET'])(privacy_agreement)
admin_bp.route('/support', methods=['GET'])(support_page)