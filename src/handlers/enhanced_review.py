"""
Enhanced Review Handlers

Provides API endpoints for enhanced review system with diverse question types.
"""

from flask import jsonify, request
import logging
import json
import base64
from typing import Dict, Any, Optional
from utils.database import db_fetch_one, get_db_connection
from services.question_generation_service import get_or_generate_question
from services.user_service import get_user_preferences
from services.audio_service import get_or_generate_audio_base64

logger = logging.getLogger(__name__)


