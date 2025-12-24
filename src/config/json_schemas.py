"""
JSON Schema definitions for LLM responses.

These schemas enforce strict type safety for LLM outputs using the JSON Schema
format supported by OpenAI's Structured Outputs API.

Supported models:
- OpenAI: gpt-4o, gpt-4o-mini
- Google: gemini-2.0-flash-exp, gemini-2.0-flash-thinking-exp-01-21
- (Other models fall back to json_object mode with validation)

References:
- OpenAI Structured Outputs: https://platform.openai.com/docs/guides/structured-outputs
- JSON Schema: https://json-schema.org/
"""

# ============================================================================
# Word Definition Schema
# ============================================================================

DEFINITION_SCHEMA = {
    "name": "word_definition_v4",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "valid_word_score": {
                "type": "number",
                "description": "Score between 0 and 1 indicating validity (0.9+ = highly valid)"
            },
            "suggestion": {
                "type": ["string", "null"],
                "description": "Suggested correction if score < 0.9, otherwise null"
            },
            "word": {"type": "string"},
            "phonetic": {"type": "string"},
            "translations": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Direct translations from learning language to native language"
            },
            "definitions": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "part_of_speech": {"type": "string"},
                        "definition": {"type": "string"},
                        "definition_native": {"type": "string"},
                        "examples": {
                            "type": "array",
                            "items": {"type": "string"}
                        },
                        "cultural_notes": {"type": ["string", "null"]}
                    },
                    "required": ["part_of_speech", "definition", "definition_native", "examples", "cultural_notes"],
                    "additionalProperties": False
                }
            },
            "collocations": {
                "type": "array",
                "items": {"type": "string"}
            },
            "synonyms": {
                "type": ["array", "null"],
                "items": {"type": "string"}
            },
            "antonyms": {
                "type": ["array", "null"],
                "items": {"type": "string"}
            },
            "comment": {"type": ["string", "null"]},
            "source": {"type": ["string", "null"]},
            "word_family": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "word": {"type": "string"},
                        "part_of_speech": {"type": "string"}
                    },
                    "required": ["word", "part_of_speech"],
                    "additionalProperties": False
                }
            },
            "cognates": {"type": ["string", "null"]},
            "famous_quote": {
                "type": ["object", "null"],
                "properties": {
                    "quote": {"type": "string"},
                    "source": {"type": "string"}
                },
                "required": ["quote", "source"],
                "additionalProperties": False
            }
        },
        "required": [
            "valid_word_score", "suggestion", "word", "phonetic", "translations",
            "definitions", "collocations", "synonyms", "antonyms", "comment",
            "source", "word_family", "cognates", "famous_quote"
        ],
        "additionalProperties": False
    }
}

# ============================================================================
# User Profile Schema
# ============================================================================

USER_PROFILE_SCHEMA = {
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

# ============================================================================
# Pronunciation Comparison Schema
# ============================================================================

PRONUNCIATION_SCHEMA = {
    "name": "pronunciation_result",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "similar": {
                "type": "boolean",
                "description": "Whether the spoken pronunciation is similar enough to the original"
            },
            "score": {
                "type": "number",
                "description": "Pronunciation accuracy score from 0.0 to 1.0"
            },
            "feedback": {
                "type": "string",
                "description": "Constructive feedback on pronunciation quality"
            }
        },
        "required": ["similar", "score", "feedback"],
        "additionalProperties": False
    }
}

# ============================================================================
# Multiple Choice Question Schemas
# ============================================================================

MC_OPTION_SCHEMA = {
    "type": "object",
    "properties": {
        "id": {
            "type": "string",
            "enum": ["A", "B"],
            "description": "Option identifier (A or B)"
        },
        "text": {
            "type": "string",
            "description": "The text content of this option in English"
        },
        "text_native": {
            "type": "string",
            "description": "The text content translated to learner's native language"
        }
    },
    "required": ["id", "text", "text_native"],
    "additionalProperties": False
}

MC_DEFINITION_QUESTION_SCHEMA = {
    "name": "mc_definition_question",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "question_text": {
                "type": "string",
                "description": "The question prompt asking for the word's meaning"
            },
            "options": {
                "type": "array",
                "items": MC_OPTION_SCHEMA,
                "minItems": 2,
                "maxItems": 2,
                "description": "Exactly 2 answer options (A, B)"
            },
            "correct_answer": {
                "type": "string",
                "enum": ["A", "B"],
                "description": "The ID of the correct option"
            }
        },
        "required": ["question_text", "options", "correct_answer"],
        "additionalProperties": False
    }
}

MC_FILLIN_QUESTION_SCHEMA = {
    "name": "mc_fillin_question",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "sentence": {
                "type": "string",
                "description": "Sentence with blank (___) where target word should go"
            },
            "question_text": {
                "type": "string",
                "description": "The question prompt (usually 'Fill in the blank:')"
            },
            "options": {
                "type": "array",
                "items": MC_OPTION_SCHEMA,
                "minItems": 2,
                "maxItems": 2,
                "description": "Exactly 2 answer options (A, B)"
            },
            "correct_answer": {
                "type": "string",
                "enum": ["A", "B"],
                "description": "The ID of the correct option"
            },
            "sentence_translation": {
                "type": "string",
                "description": "Translation of the complete sentence to learner's native language"
            }
        },
        "required": ["sentence", "question_text", "options", "correct_answer", "sentence_translation"],
        "additionalProperties": False
    }
}

PRONOUNCE_SENTENCE_QUESTION_SCHEMA = {
    "name": "pronounce_sentence_question",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "sentence": {
                "type": "string",
                "description": "Natural sentence containing the target word for pronunciation practice"
            },
            "sentence_translation": {
                "type": "string",
                "description": "Translation of the sentence to learner's native language"
            },
            "question_text": {
                "type": "string",
                "description": "The question prompt (usually 'Pronounce this sentence:')"
            }
        },
        "required": ["sentence", "sentence_translation", "question_text"],
        "additionalProperties": False
    }
}

# ============================================================================
# Video Multiple Choice Schema (Simplified - always tests meaning in context)
# ============================================================================

VIDEO_MC_SIMPLE_SCHEMA = {
    "name": "video_mc_simple",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "question": {
                "type": "string",
                "description": "Question asking what the word means in this context"
            },
            "options": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "text": {
                            "type": "string",
                            "description": "Option text in English"
                        },
                        "text_native": {
                            "type": "string",
                            "description": "Option text translated to learner's native language"
                        },
                        "correct": {
                            "type": "boolean",
                            "description": "Whether this option is correct"
                        }
                    },
                    "required": ["text", "text_native", "correct"],
                    "additionalProperties": False
                },
                "minItems": 2,
                "maxItems": 2,
                "description": "Exactly 2 options (binary choice for better pedagogy)"
            },
            "explanation": {
                "type": "string",
                "description": "One sentence explaining why the correct answer is right (shown after answering)"
            }
        },
        "required": ["question", "options", "explanation"],
        "additionalProperties": False
    }
}

# ============================================================================
# Schema Registry (for easy lookup by use case)
# ============================================================================

SCHEMA_REGISTRY = {
    "definition": DEFINITION_SCHEMA,
    "user_profile": USER_PROFILE_SCHEMA,
    "pronunciation": PRONUNCIATION_SCHEMA,
    "mc_definition": MC_DEFINITION_QUESTION_SCHEMA,
    "mc_fillin": MC_FILLIN_QUESTION_SCHEMA,
    "pronounce_sentence": PRONOUNCE_SENTENCE_QUESTION_SCHEMA,
    "video_mc_simple": VIDEO_MC_SIMPLE_SCHEMA,
}


def get_schema(use_case: str) -> dict:
    """
    Get JSON schema for a specific use case.

    Args:
        use_case: One of: pronunciation, mc_definition, mc_fillin,
                  pronounce_sentence, video_mc_options

    Returns:
        Schema dict in OpenAI Structured Outputs format

    Raises:
        ValueError: If use_case not found in registry
    """
    if use_case not in SCHEMA_REGISTRY:
        raise ValueError(f"Unknown schema use_case: {use_case}. "
                        f"Available: {list(SCHEMA_REGISTRY.keys())}")
    return SCHEMA_REGISTRY[use_case]
