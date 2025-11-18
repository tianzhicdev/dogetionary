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
        