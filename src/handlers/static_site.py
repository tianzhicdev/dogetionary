"""
Static Site API Handlers
Provides APIs for static site generation, including paginated word access
"""

from flask import request, jsonify
import logging
from utils.database import get_db_connection

logger = logging.getLogger(__name__)

def get_all_words():
    """
    Get all words with pagination for static site generation

    Query Parameters:
    - page: Page number (default: 1)
    - limit: Items per page (default: 1000, max: 5000)
    - letter: Filter by first letter (optional)
    - language_pair: Filter by language pair in format "learning-native" (optional)
    - include_metadata: Include additional metadata (default: false)

    Returns:
    {
        "words": [...],
        "pagination": {
            "page": 1,
            "limit": 1000,
            "total_pages": 10,
            "total_count": 9500,
            "has_next": true,
            "has_prev": false
        },
        "filters": {
            "letter": "a",
            "language_pair": "en-zh"
        }
    }
    """
    try:
        # Parse query parameters
        page = int(request.args.get('page', 1))
        limit = min(int(request.args.get('limit', 1000)), 5000)  # Cap at 5000
        letter = request.args.get('letter', '').lower() if request.args.get('letter') else None
        language_pair = request.args.get('language_pair', '')
        include_metadata = request.args.get('include_metadata', 'false').lower() == 'true'

        # Validate parameters
        if page < 1:
            return jsonify({"error": "Page must be >= 1"}), 400
        if limit < 1:
            return jsonify({"error": "Limit must be >= 1"}), 400
        if letter and (len(letter) != 1 or not letter.isalpha()):
            return jsonify({"error": "Letter must be a single alphabetic character"}), 400

        # Parse language pair
        learning_language = None
        native_language = None
        if language_pair:
            parts = language_pair.split('-')
            if len(parts) == 2:
                learning_language, native_language = parts
            else:
                return jsonify({"error": "Language pair must be in format 'learning-native'"}), 400

        # Calculate offset
        offset = (page - 1) * limit

        # Build query
        query_conditions = []
        query_params = []

        if letter:
            query_conditions.append("LOWER(word) LIKE %s")
            query_params.append(f"{letter}%")

        if learning_language:
            query_conditions.append("learning_language = %s")
            query_params.append(learning_language)

        if native_language:
            query_conditions.append("native_language = %s")
            query_params.append(native_language)

        where_clause = ""
        if query_conditions:
            where_clause = "WHERE " + " AND ".join(query_conditions)

        # Get total count
        count_query = f"""
        SELECT COUNT(*) as total_count
        FROM definitions
        {where_clause}
        """

        # Get words with pagination
        words_query = f"""
        SELECT
            word,
            learning_language,
            native_language,
            definition_data,
            created_at,
            updated_at
        FROM definitions
        {where_clause}
        ORDER BY word, learning_language, native_language
        LIMIT %s OFFSET %s
        """

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                # Get total count
                cur.execute(count_query, query_params)
                count_result = cur.fetchone()
                total_count = count_result['total_count']

                # Get words
                cur.execute(words_query, query_params + [limit, offset])
                words_raw = cur.fetchall()

        # Process words
        words = []
        for word_row in words_raw:
            word_data = {
                'word': word_row['word'],
                'learning_language': word_row['learning_language'],
                'native_language': word_row['native_language'],
                'definition_data': word_row['definition_data'],  # Already JSONB
            }

            if include_metadata:
                word_data.update({
                    'created_at': word_row['created_at'].isoformat() if word_row['created_at'] else None,
                    'updated_at': word_row['updated_at'].isoformat() if word_row['updated_at'] else None,
                })

            words.append(word_data)

        # Calculate pagination info
        total_pages = (total_count + limit - 1) // limit  # Ceiling division
        has_next = page < total_pages
        has_prev = page > 1

        # Build response
        response = {
            'words': words,
            'pagination': {
                'page': page,
                'limit': limit,
                'total_pages': total_pages,
                'total_count': total_count,
                'has_next': has_next,
                'has_prev': has_prev
            },
            'filters': {}
        }

        if letter:
            response['filters']['letter'] = letter
        if language_pair:
            response['filters']['language_pair'] = language_pair

        logger.info(f"Retrieved {len(words)} words (page {page}/{total_pages}, total: {total_count})")
        return jsonify(response)

    except ValueError as e:
        logger.error(f"Invalid parameter: {e}", exc_info=True)
        return jsonify({"error": f"Invalid parameter: {str(e)}"}), 400
    except Exception as e:
        import traceback
        logger.error(f"Error fetching words: {e}", exc_info=True)
        logger.error(f"Traceback: {traceback.format_exc()}")
        return jsonify({"error": f"Internal server error: {str(e)}"}), 500


def get_words_summary():
    """
    Get summary statistics about words for static site generation

    Returns:
    {
        "total_words": 50000,
        "total_definitions": 150000,
        "language_pairs": [
            {"learning": "en", "native": "zh", "count": 25000},
            {"learning": "en", "native": "es", "count": 20000},
            ...
        ],
        "letter_distribution": {
            "a": 2500,
            "b": 2200,
            ...
        },
        "last_updated": "2025-01-23T10:30:00Z"
    }
    """
    try:
        # Simplified query that works with all PostgreSQL versions
        query_total = """
        SELECT COUNT(*) as total_words,
               COUNT(CASE WHEN definition_data IS NOT NULL THEN 1 END) as total_definitions
        FROM definitions
        """

        query_language_pairs = """
        SELECT learning_language, native_language, COUNT(*) as count
        FROM definitions
        GROUP BY learning_language, native_language
        ORDER BY learning_language, native_language
        """

        query_letters = """
        SELECT LOWER(SUBSTRING(word FROM 1 FOR 1)) as first_letter, COUNT(*) as count
        FROM definitions
        WHERE word IS NOT NULL AND word != ''
        GROUP BY LOWER(SUBSTRING(word FROM 1 FOR 1))
        ORDER BY first_letter
        """

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                # Get total counts
                cur.execute(query_total)
                total_row = cur.fetchone()
                total_words = total_row['total_words']
                total_definitions = total_row['total_definitions']

                # Get language pairs
                cur.execute(query_language_pairs)
                language_pairs_raw = cur.fetchall()
                language_pairs_list = [
                    {
                        'learning': row['learning_language'],
                        'native': row['native_language'],
                        'count': row['count']
                    }
                    for row in language_pairs_raw
                ]

                # Get letter distribution
                cur.execute(query_letters)
                letters_raw = cur.fetchall()
                letter_distribution = {row['first_letter']: row['count'] for row in letters_raw}

                # Get last updated timestamp
                cur.execute("SELECT MAX(updated_at) as max_updated FROM definitions")
                last_updated_row = cur.fetchone()
                last_updated = last_updated_row['max_updated']

        response = {
            'total_words': total_words,
            'total_definitions': total_definitions,
            'language_pairs': language_pairs_list,
            'letter_distribution': letter_distribution,
            'last_updated': last_updated.isoformat() if last_updated else None
        }

        logger.info(f"Words summary: {total_words} words, {len(language_pairs_list)} language pairs")
        return jsonify(response)

    except Exception as e:
        import traceback
        logger.error(f"Error fetching words summary: {e}", exc_info=True)
        logger.error(f"Traceback: {traceback.format_exc()}")
        return jsonify({"error": f"Internal server error: {str(e)}"}), 500


def get_featured_words():
    """
    Get featured words for homepage

    Query Parameters:
    - count: Number of words to return (default: 10, max: 50)
    - seed: Random seed for consistent results (optional)

    Returns:
    {
        "featured_words": [
            {
                "word": "example",
                "learning_language": "en",
                "native_language": "zh",
                "definition_data": {...},
                "short_definition": "A thing characteristic of its kind..."
            }
        ]
    }
    """
    try:
        count = min(int(request.args.get('count', 10)), 50)
        seed = request.args.get('seed')

        # Use seed for consistent randomization if provided
        if seed:
            try:
                seed_val = int(seed)
                query = f"""
                SELECT word, learning_language, native_language, definition_data
                FROM definitions
                WHERE definition_data IS NOT NULL
                ORDER BY (word || '{seed_val}')::integer % 1000  -- Pseudo-random based on seed
                LIMIT %s
                """
                params = [count]
            except ValueError:
                query = """
                SELECT word, learning_language, native_language, definition_data
                FROM definitions
                WHERE definition_data IS NOT NULL
                ORDER BY RANDOM()
                LIMIT %s
                """
                params = [count]
        else:
            query = """
            SELECT word, learning_language, native_language, definition_data
            FROM definitions
            WHERE definition_data IS NOT NULL
            ORDER BY RANDOM()
            LIMIT %s
            """
            params = [count]

        with get_db_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(query, params)
                words_raw = cur.fetchall()

        # Process words
        featured_words = []
        for word_row in words_raw:
            definition_data = word_row['definition_data']

            # Extract short definition
            short_definition = ""
            if definition_data and 'definitions' in definition_data and definition_data['definitions']:
                first_def = definition_data['definitions'][0].get('definition', '')
                short_definition = first_def[:120] + "..." if len(first_def) > 120 else first_def

            word_data = {
                'word': word_row['word'],
                'learning_language': word_row['learning_language'],
                'native_language': word_row['native_language'],
                'definition_data': definition_data,
                'short_definition': short_definition,
                'phonetic': definition_data.get('phonetic') if definition_data else None
            }

            featured_words.append(word_data)

        response = {
            'featured_words': featured_words
        }

        logger.info(f"Retrieved {len(featured_words)} featured words")
        return jsonify(response)

    except ValueError as e:
        logger.error(f"Invalid parameter: {e}", exc_info=True)
        return jsonify({"error": f"Invalid parameter: {str(e)}"}), 400
    except Exception as e:
        import traceback
        logger.error(f"Error fetching featured words: {e}", exc_info=True)
        logger.error(f"Traceback: {traceback.format_exc()}")
        return jsonify({"error": f"Internal server error: {str(e)}"}), 500