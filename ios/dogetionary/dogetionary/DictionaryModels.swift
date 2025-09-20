//
//  DictionaryModels.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import Foundation

struct WordDefinitionResponse: Identifiable, Codable {
    let id = UUID()
    let word: String
    let learning_language: String
    let native_language: String
    let definition_data: DefinitionData
    let audio_references: AudioReferences
    let audio_generation_status: String
    
    private enum CodingKeys: String, CodingKey {
        case word, learning_language, native_language, definition_data, audio_references, audio_generation_status
    }
}

struct DefinitionData: Codable {
    let phonetic: String?
    let word: String?
    let translations: [String]?
    let definitions: [DefinitionEntry]
}

struct DefinitionEntry: Codable {
    let definition: String
    let type: String
    let examples: [String]
    let definition_native: String?
    let cultural_notes: String?
}

struct AudioReferences: Codable {
    let word_audio: Bool?
    let example_audio: [String: Bool] // text -> availability mapping
}

// Audio fetch models for getting actual audio data
struct AudioDataResponse: Codable {
    let audio_data: String // Base64 encoded audio data
    let content_type: String
    let created_at: String
    let generated: Bool? // Whether this was generated on-demand
}

// UI-compatible models converted from new API response
struct Definition: Identifiable {
    let id: UUID
    let word: String
    let phonetic: String?
    let learning_language: String
    let native_language: String
    let translations: [String] // Direct translations from learning to native language
    let meanings: [Meaning]
    let audioData: Data? // Decoded audio data ready for playback
    let hasWordAudio: Bool // whether word audio is available
    let exampleAudioAvailability: [String: Bool] // text -> availability mapping for examples
    
    init(from response: WordDefinitionResponse) {
        self.id = UUID()
        self.word = response.word
        self.phonetic = response.definition_data.phonetic
        self.learning_language = response.learning_language
        self.native_language = response.native_language
        self.translations = response.definition_data.translations ?? []
        
        // Always show native definition if it exists and is different from main definition
        
        // Convert new format to UI-compatible format
        // Group definitions by type (part of speech)
        let groupedDefinitions = Dictionary(grouping: response.definition_data.definitions) { $0.type }
        self.meanings = groupedDefinitions.map { (partOfSpeech, definitions) in
            let definitionDetails = definitions.map { def in
                // Show native definition if it exists and is different from main definition
                let definitionText: String
                if let nativeDefinition = def.definition_native, 
                   !nativeDefinition.isEmpty && nativeDefinition != def.definition {
                    definitionText = "\(def.definition)\n\n\(nativeDefinition)"
                } else {
                    definitionText = def.definition
                }
                
                // Use first example (always in learning language)
                let exampleText = def.examples.first
                
                return DefinitionDetail(
                    definition: definitionText,
                    example: exampleText,
                    synonyms: nil,
                    antonyms: def.cultural_notes != nil ? [def.cultural_notes!] : nil // Use antonyms field for cultural notes
                )
            }
            return Meaning(partOfSpeech: partOfSpeech, definitions: definitionDetails)
        }
        
        // Store audio availability information
        self.hasWordAudio = response.audio_references.word_audio ?? false
        self.exampleAudioAvailability = response.audio_references.example_audio
        self.audioData = nil // Will be loaded separately when needed
    }
    
    // Custom initializer for updating with audio data
    init(id: UUID = UUID(), word: String, phonetic: String?, learning_language: String, native_language: String, translations: [String] = [], meanings: [Meaning], audioData: Data?, hasWordAudio: Bool = false, exampleAudioAvailability: [String: Bool] = [:]) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.learning_language = learning_language
        self.native_language = native_language
        self.translations = translations
        self.meanings = meanings
        self.audioData = audioData
        self.hasWordAudio = hasWordAudio
        self.exampleAudioAvailability = exampleAudioAvailability
    }
}

struct Meaning: Codable {
    let partOfSpeech: String
    let definitions: [DefinitionDetail]
}

struct DefinitionDetail: Codable {
    let definition: String
    let example: String?
    let synonyms: [String]?
    let antonyms: [String]?
}

// Saved Words Models
struct SavedWordsResponse: Codable {
    let user_id: String
    let saved_words: [SavedWord]
    let count: Int
    let due_only: Bool?
}

struct SavedWord: Identifiable, Codable {
    let id: Int
    let word: String
    let learning_language: String
    let native_language: String
    let metadata: [String: Any]?
    let created_at: String
    // Calculated fields from review history (backend provides these)
    let review_count: Int
    let ease_factor: Double
    let interval_days: Int
    let next_review_date: String?
    let last_reviewed_at: String?

    private enum CodingKeys: String, CodingKey {
        case id, word, learning_language, native_language, created_at, review_count, ease_factor, interval_days, next_review_date, last_reviewed_at
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        learning_language = try container.decode(String.self, forKey: .learning_language)
        native_language = try container.decode(String.self, forKey: .native_language)
        created_at = try container.decode(String.self, forKey: .created_at)
        review_count = try container.decodeIfPresent(Int.self, forKey: .review_count) ?? 0
        ease_factor = try container.decodeIfPresent(Double.self, forKey: .ease_factor) ?? 2.5
        interval_days = try container.decodeIfPresent(Int.self, forKey: .interval_days) ?? 1
        next_review_date = try container.decodeIfPresent(String.self, forKey: .next_review_date)
        last_reviewed_at = try container.decodeIfPresent(String.self, forKey: .last_reviewed_at)
        metadata = nil // We'll skip decoding metadata for now
    }
    
    // Convenience initializer for testing
    init(id: Int, word: String, learning_language: String, native_language: String, metadata: [String: Any]?, created_at: String, review_count: Int, ease_factor: Double, interval_days: Int, next_review_date: String?, last_reviewed_at: String?) {
        self.id = id
        self.word = word
        self.learning_language = learning_language
        self.native_language = native_language
        self.metadata = metadata
        self.created_at = created_at
        self.review_count = review_count
        self.ease_factor = ease_factor
        self.interval_days = interval_days
        self.next_review_date = next_review_date
        self.last_reviewed_at = last_reviewed_at
    }
}

// Review Models
struct ReviewSubmissionRequest: Codable {
    let user_id: String
    let word_id: Int
    let response: Bool
}

struct ReviewSubmissionResponse: Codable {
    let success: Bool
    let word_id: Int
    let response: Bool
    let review_count: Int
    let ease_factor: Double
    let interval_days: Int
    let next_review_date: String
}

// Next Due Words Models
struct NextDueWordsResponse: Codable {
    let user_id: String
    let saved_words: [SavedWord]
    let count: Int
    let limit: Int
}

// Review Words Models (simplified for review_next endpoint)
struct ReviewWordsResponse: Codable {
    let user_id: String
    let saved_words: [ReviewWord]
    let count: Int
}

struct ReviewWord: Identifiable, Codable {
    let id: Int
    let word: String
    let learning_language: String
    let native_language: String
}

struct ReviewStats: Codable {
    let user_id: String
    let total_words: Int
    let due_today: Int
    let reviews_today: Int
    let success_rate_7_days: Double
}

struct ReviewProgressStats: Codable {
    let reviews_today: Int
    let success_rate_today: Double
    let acquainted_to_familiar: Int
    let familiar_to_remembered: Int
    let remembered_to_unforgettable: Int
    let total_reviews: Int
}

// Word Detail Models
struct WordDetails: Codable {
    let id: Int
    let word: String
    let learning_language: String
    let metadata: [String: Any]?
    let created_at: String
    let review_count: Int
    let ease_factor: Double
    let interval_days: Int
    let next_review_date: String?
    let last_reviewed_at: String?
    let review_history: [ReviewHistoryEntry]
    
    private enum CodingKeys: String, CodingKey {
        case id, word, learning_language, created_at, review_count, ease_factor, interval_days, next_review_date, last_reviewed_at, review_history
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        learning_language = try container.decode(String.self, forKey: .learning_language)
        created_at = try container.decode(String.self, forKey: .created_at)
        review_count = try container.decode(Int.self, forKey: .review_count)
        ease_factor = try container.decode(Double.self, forKey: .ease_factor)
        interval_days = try container.decode(Int.self, forKey: .interval_days)
        next_review_date = try container.decodeIfPresent(String.self, forKey: .next_review_date)
        last_reviewed_at = try container.decodeIfPresent(String.self, forKey: .last_reviewed_at)
        review_history = try container.decode([ReviewHistoryEntry].self, forKey: .review_history)
        metadata = nil // Skip metadata decoding for now
    }
}

struct ReviewHistoryEntry: Codable {
    let response: Bool
    let response_time_ms: Int?
    let reviewed_at: String
}

// User Preferences Models
struct UserPreferences: Codable {
    let user_id: String
    let learning_language: String
    let native_language: String
    let user_name: String?
    let user_motto: String?
    let updated: Bool?
}

// Leaderboard Models
struct LeaderboardEntry: Codable, Identifiable {
    let id = UUID()
    let rank: Int
    let user_id: String
    let user_name: String
    let user_motto: String
    let total_reviews: Int
    
    private enum CodingKeys: String, CodingKey {
        case rank, user_id, user_name, user_motto, total_reviews
    }
}

struct LeaderboardResponse: Codable {
    let leaderboard: [LeaderboardEntry]
    let total_users: Int
}

// AI Illustration Models
struct IllustrationResponse: Codable {
    let word: String
    let language: String
    let scene_description: String
    let image_data: String // Base64 encoded image data
    let content_type: String
    let cached: Bool?
    let created_at: String
}

// Due Counts Models
struct DueCountsResponse: Codable {
    let user_id: String
    let overdue_count: Int
    let total_count: Int
}

// Save Word Response Model
struct SaveWordResponse: Codable {
    let success: Bool
    let message: String
    let word_id: Int
    let created_at: String
}

// Forgetting Curve Models
struct ForgettingCurveResponse: Codable {
    let word_id: Int
    let word: String
    let created_at: String
    let forgetting_curve: [CurveDataPointAPI]
    let next_review_date: String?
    let review_markers: [ReviewMarker]?
    let all_markers: [AllMarker]?
}

struct CurveDataPointAPI: Codable {
    let date: String
    let retention: Double
    let is_projection: Bool?
}

struct ReviewMarker: Codable {
    let date: String
    let success: Bool
}

struct AllMarker: Codable {
    let date: String
    let type: String // "creation", "review", "next_review"
    let success: Bool?
}

// MARK: - V2 API Models for Word Validation

struct WordDefinitionV2Response: Codable {
    let word: String
    let learning_language: String
    let native_language: String
    let definition: String
    let examples: [String]
    let validation: WordValidation
}

struct WordValidation: Codable {
    let confidence: Double
    let suggested: String?
}

// UI-compatible model for v2 API
struct DefinitionV2: Identifiable {
    let id = UUID()
    let word: String
    let definition: String
    let examples: [String]
    let validation: WordValidation

    init(from response: WordDefinitionV2Response) {
        self.word = response.word
        self.definition = response.definition
        self.examples = response.examples
        self.validation = response.validation
    }

    var isValid: Bool {
        return validation.confidence >= 0.9
    }
}
