"""
App Version Handler

Provides endpoint for checking if the iOS app version is supported.
Used for forced upgrades when breaking changes are deployed.
"""

from flask import jsonify, request
import logging
import os
from packaging import version

logger = logging.getLogger(__name__)

# Configuration via environment variables (can be overridden in production)
# Defaults are set to allow all versions during development
IOS_MIN_VERSION = os.environ.get('IOS_MIN_VERSION', '1.0.0')
IOS_LATEST_VERSION = os.environ.get('IOS_LATEST_VERSION', '5.0.0')
IOS_APP_STORE_URL = os.environ.get('IOS_APP_STORE_URL', 'https://apps.apple.com/app/id6752226667')
FORCE_UPGRADE_MESSAGE = os.environ.get('FORCE_UPGRADE_MESSAGE', 'Please update to the latest version to continue using the app.')


def check_app_version():
    """
    Check if the app version is supported.

    GET /v3/app-version?platform=ios&version=1.0.0

    Query Parameters:
        platform: The platform (ios, android) - currently only ios is supported
        version: The app version string (e.g., "1.0.0", "1.2.3")

    Returns:
        JSON with version status:
        {
            "status": "ok" | "upgrade_required" | "upgrade_recommended",
            "min_version": "1.0.0",
            "latest_version": "1.2.0",
            "upgrade_url": "https://apps.apple.com/...",
            "message": "Optional message to display"
        }
    """
    try:
        platform = request.args.get('platform', '').lower()
        app_version = request.args.get('version', '')

        # Validate required parameters
        if not platform:
            return jsonify({"error": "platform parameter is required"}), 400

        if not app_version:
            return jsonify({"error": "version parameter is required"}), 400

        # Currently only iOS is supported
        if platform != 'ios':
            return jsonify({
                "status": "ok",
                "message": f"Platform '{platform}' is not subject to version checks"
            }), 200

        # Parse versions for comparison
        try:
            current = version.parse(app_version)
            min_ver = version.parse(IOS_MIN_VERSION)
            latest_ver = version.parse(IOS_LATEST_VERSION)
        except Exception as e:
            logger.error(f"Error parsing version strings: {e}", exc_info=True)
            return jsonify({"error": f"Invalid version format: {app_version}"}), 400

        # Determine status
        if current < min_ver:
            status = "upgrade_required"
            message = FORCE_UPGRADE_MESSAGE
            logger.info(f"App version {app_version} requires upgrade (min: {IOS_MIN_VERSION})")
        elif current < latest_ver:
            status = "upgrade_recommended"
            message = "A new version is available with improvements and bug fixes."
            logger.info(f"App version {app_version} has update available (latest: {IOS_LATEST_VERSION})")
        else:
            status = "ok"
            message = None
            logger.debug(f"App version {app_version} is up to date")

        response = {
            "status": status,
            "min_version": IOS_MIN_VERSION,
            "latest_version": IOS_LATEST_VERSION,
            "upgrade_url": IOS_APP_STORE_URL
        }

        if message:
            response["message"] = message

        return jsonify(response), 200

    except Exception as e:
        logger.error(f"Error checking app version: {e}", exc_info=True)
        # On error, allow the app to continue (fail open)
        return jsonify({
            "status": "ok",
            "message": "Version check temporarily unavailable"
        }), 200
