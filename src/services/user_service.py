import json
from utils.database import get_db_connection
from utils.llm import llm_completion
from config.config import COMPLETION_MODEL_NAME

def generate_user_profile() -> tuple[str, str]:
    """Generate a proper, civil user name and motto using OpenAI with structured output"""
    try:
        content = llm_completion(
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
            model_name=COMPLETION_MODEL_NAME,
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "user_profile",
                    "strict": True,
                    "schema": {
                        "type": "object",
                        "properties": {
                            "username": {
                                "type": "string",
                                "description": "A friendly, appropriate username suitable for all ages (max 20 characters)"
                            },
                            "motto": {
                                "type": "string",
                                "description": "A positive, motivational motto related to learning (max 50 characters)"
                            }
                        },
                        "required": ["username", "motto"],
                        "additionalProperties": False
                    }
                }
            },
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

        # Note: app.logger reference will need to be handled
        print(f"Generated user profile - Username: {username}, Motto: {motto}")
        return username, motto

    except Exception as e:
        # Note: app.logger reference will need to be handled
        print(f"Error generating user profile: {str(e)}")
        # Provide safe fallbacks
        return "LearningExplorer", "Every word is a new adventure!"

def get_user_preferences(user_id: str) -> tuple[str, str, str, str]:
    try:
        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT learning_language, native_language, user_name, user_motto
            FROM user_preferences
            WHERE user_id = %s
        """, (user_id,))

        result = cur.fetchone()
        cur.close()
        conn.close()

        if result:
            return (result['learning_language'], result['native_language'],
                   result['user_name'] or '', result['user_motto'] or '')
        else:
            # Generate AI profile for new user
            username, motto = generate_user_profile()

            conn = get_db_connection()
            cur = conn.cursor()
            cur.execute("""
                INSERT INTO user_preferences (user_id, learning_language, native_language, user_name, user_motto)
                VALUES (%s, 'en', 'zh', %s, %s)
                ON CONFLICT (user_id) DO NOTHING
            """, (user_id, username, motto))
            conn.commit()
            conn.close()
            return 'en', 'zh', username, motto

    except Exception as e:
        # Note: app.logger reference will need to be handled
        print(f"Error getting user preferences: {str(e)}")
        return 'en', 'zh', 'LearningExplorer', 'Every word is a new adventure!'

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
                    cur.close()
                    conn.close()
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

        cur.close()
        conn.close()

        return {
            "success": True,
            "word_id": str(word_id),
            "word": word,
            "is_excluded": excluded,
            "previous_status": current_status,
            "message": message
        }

    except Exception as e:
        print(f"Error toggling word exclusion: {str(e)}")
        return {
            "success": False,
            "error": str(e),
            "message": "Failed to update word exclusion status"
        }
