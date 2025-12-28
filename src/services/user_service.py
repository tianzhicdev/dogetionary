import json
import logging
from utils.database import get_db_connection
from utils.llm import llm_completion_with_fallback

logger = logging.getLogger(__name__)

def generate_user_profile() -> tuple[str, str]:
    """Generate a proper, civil user name and motto using LLM with fallback chain"""
    try:
        # Uses fallback chain: Gemini 2.0 -> DeepSeek V3 -> Qwen 2.5 -> GPT-4o-mini
        content = llm_completion_with_fallback(
            messages=[
                {
                    "role": "system",
                    "content": "You are a helpful assistant that generates appropriate, civil usernames and motivational mottos for language learning app users."
                },
                {
                    "role": "user",
                    "content": "Generate a friendly, appropriate username and motivational motto for a language learning app user. The username should be suitable for all ages, contain no real names, and avoid numbers/special characters. The motto should be positive, motivational, related to learning or personal growth, and under 50 characters. Both should be completely appropriate, civil, and encouraging."
                }
            ],
            use_case="user_profile",
            schema_name="user_profile",  # Uses USER_PROFILE_SCHEMA from config/json_schemas.py
            max_tokens=150
        )

        if not content:
            return "LearningExplorer", "Every word is a new adventure!"

        # Parse the structured JSON response
        profile_data = json.loads(content)

        username = profile_data.get("username", "LearningExplorer")
        motto = profile_data.get("motto", "Every word is a new adventure!")

        # Ensure lengths are within limits
        username = username[:20] if len(username) > 20 else username
        motto = motto[:50] if len(motto) > 50 else motto

        logger.info(f"✓ Generated user profile - Username: {username}, Motto: {motto}")
        return username, motto

    except Exception as e:
        logger.error(f"❌ Error generating user profile: {e}", exc_info=True)
        logger.info(f"Using fallback profile: LearningExplorer / Every word is a new adventure!")
        # Provide safe fallbacks
        return "LearningExplorer", "Every word is a new adventure!"

def get_user_preferences(user_id: str) -> tuple[str, str, str, str]:
    conn = None
    cur = None
    try:
        logger.info(f"📋 get_user_preferences called for user_id='{user_id}'")
        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT learning_language, native_language, user_name, user_motto
            FROM user_preferences
            WHERE user_id = %s
        """, (user_id,))

        result = cur.fetchone()

        if result:
            logger.info(f"✓ Found user preferences: user_id='{user_id}', learning_lang='{result['learning_language']}', native_lang='{result['native_language']}'")
            return (result['learning_language'], result['native_language'],
                   result['user_name'] or '', result['user_motto'] or '')
        else:
            # Generate AI profile for new user
            logger.warning(f"⚠️ No preferences found for user_id='{user_id}', creating new user with defaults (learning='en', native='zh')")
            username, motto = generate_user_profile()

            cur.execute("""
                INSERT INTO user_preferences (user_id, learning_language, native_language, user_name, user_motto)
                VALUES (%s, 'en', 'zh', %s, %s)
                ON CONFLICT (user_id) DO NOTHING
            """, (user_id, username, motto))
            conn.commit()
            logger.info(f"✓ Created new user: user_id='{user_id}', learning='en', native='zh', username='{username}'")
            return 'en', 'zh', username, motto

    except Exception as e:
        if conn:
            conn.rollback()
        logger.error(f"❌ ERROR in get_user_preferences for user_id='{user_id}'")
        logger.error(f"❌ Exception type: {type(e).__name__}")
        logger.error(f"❌ Exception message: {e}")
        logger.error(f"❌ Full stack trace:", exc_info=True)
        logger.error(f"❌ Returning fallback values: learning='en', native='zh'")
        return 'en', 'zh', 'LearningExplorer', 'Every word is a new adventure!'
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()

def toggle_word_exclusion(user_id: str, word: str, excluded: bool, learning_language: str = None, native_language: str = None) -> dict:
    """
    Toggle whether a word is excluded from practice (marks as known/unknown).
    If word is not yet saved, it will be automatically saved first.

    Args:
        user_id: UUID of the user
        word: The word to toggle
        excluded: True to exclude from practice, False to include
        learning_language: Optional - the word's learning language (if not provided, uses user preferences)
        native_language: Optional - the word's native language (if not provided, uses user preferences)

    Returns:
        dict with success status, word info, and message
    """
    conn = None
    cur = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        # If languages provided, use them to find the specific word
        # Otherwise, fall back to user preferences (for backward compatibility)
        if learning_language and native_language:
            # Check if word exists with specific languages
            cur.execute("""
                SELECT id, word, is_known, learning_language, native_language
                FROM saved_words
                WHERE user_id = %s AND word = %s AND learning_language = %s AND native_language = %s
            """, (user_id, word.lower(), learning_language, native_language))
        else:
            # Backward compatibility: find any matching word for this user
            cur.execute("""
                SELECT id, word, is_known, learning_language, native_language
                FROM saved_words
                WHERE user_id = %s AND word = %s
            """, (user_id, word.lower()))

        result = cur.fetchone()

        if not result:
            # Word not saved yet - need languages to save it
            if not learning_language or not native_language:
                # Fall back to user preferences
                cur.execute("""
                    SELECT learning_language, native_language
                    FROM user_preferences
                    WHERE user_id = %s
                """, (user_id,))

                prefs = cur.fetchone()
                if not prefs:
                    return {
                        "success": False,
                        "error": "User preferences not found",
                        "message": "Unable to save word - language parameters required or user preferences not configured"
                    }

                learning_language = prefs['learning_language']
                native_language = prefs['native_language']

            # Save the word
            cur.execute("""
                INSERT INTO saved_words
                (user_id, word, learning_language, native_language, is_known)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id
            """, (user_id, word.lower(), learning_language, native_language, excluded))

            word_id = cur.fetchone()['id']
            current_status = False  # Word was just created, so previous status is False

            conn.commit()

            message = "Word saved and excluded from practice" if excluded else "Word saved and included in practice"

            print(f"Auto-saved word '{word}' for user {user_id} with is_known={excluded}")
        else:
            # Word exists - update the exclusion status
            word_id = result['id']
            current_status = result['is_known']

            # Update the exclusion status
            cur.execute("""
                UPDATE saved_words
                SET is_known = %s
                WHERE id = %s
            """, (excluded, word_id))

            conn.commit()

            message = "Word excluded from practice" if excluded else "Word included in practice"

        return {
            "success": True,
            "word_id": str(word_id),
            "word": word,
            "is_excluded": excluded,
            "previous_status": current_status,
            "message": message
        }

    except Exception as e:
        if conn:
            conn.rollback()
        print(f"Error toggling word exclusion: {str(e)}")
        return {
            "success": False,
            "error": str(e),
            "message": "Failed to update word exclusion status"
        }
    finally:
        if cur:
            cur.close()
        if conn:
            conn.close()
