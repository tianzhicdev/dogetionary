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
            "enum": ["A", "B", "C", "D"],
            "description": "Option identifier (A, B, C, or D)"
        },
        "text": {
            "type": "string",
            "description": "The text content of this option"
        }
    },
    "required": ["id", "text"],
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
                "minItems": 4,
                "maxItems": 4,
                "description": "Exactly 4 answer options (A, B, C, D)"
            },
            "correct_answer": {
                "type": "string",
                "enum": ["A", "B", "C", "D"],
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
                "minItems": 4,
                "maxItems": 4,
                "description": "Exactly 4 answer options (A, B, C, D)"
            },
            "correct_answer": {
                "type": "string",
                "enum": ["A", "B", "C", "D"],
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
# Video Multiple Choice Schema
# ============================================================================

VIDEO_MC_OPTIONS_SCHEMA = {
    "name": "video_mc_options",
    "strict": True,
    "schema": {
        "type": "object",
        "properties": {
            "correct_meaning": {
                "type": "string",
                "description": "The correct meaning/translation of the word shown in the video"
            },
            "distractors": {
                "type": "array",
                "items": {
                    "type": "string"
                },
                "minItems": 3,
                "maxItems": 3,
                "description": "Exactly 3 plausible but incorrect alternatives"
            }
        },
        "required": ["correct_meaning", "distractors"],
        "additionalProperties": False
    }
}

# ============================================================================
# Schema Registry (for easy lookup by use case)
# ============================================================================

SCHEMA_REGISTRY = {
    "pronunciation": PRONUNCIATION_SCHEMA,
    "mc_definition": MC_DEFINITION_QUESTION_SCHEMA,
    "mc_fillin": MC_FILLIN_QUESTION_SCHEMA,
    "pronounce_sentence": PRONOUNCE_SENTENCE_QUESTION_SCHEMA,
    "video_mc_options": VIDEO_MC_OPTIONS_SCHEMA,
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
