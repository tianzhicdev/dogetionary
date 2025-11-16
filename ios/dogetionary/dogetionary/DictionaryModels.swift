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
    let valid_word_score: Double?  // V3: Top-level for backward compatibility with v2.7.2
    let suggestion: String?  // V3: Top-level for backward compatibility with v2.7.2

    private enum CodingKeys: String, CodingKey {
        case word, learning_language, native_language, definition_data, audio_references, audio_generation_status, valid_word_score, suggestion
    }
}

struct DefinitionData: Codable {
    let phonetic: String?
    let word: String?
    let translations: [String]?
    let definitions: [DefinitionEntry]
    let valid_word_score: Double?  // V3: Validation score (0-1), optional for backward compatibility
    let suggestion: String?  // V3: Suggested correction if score < 0.9, optional for backward compatibility

    private enum CodingKeys: String, CodingKey {
        case phonetic, word, translations, definitions, valid_word_score, suggestion
    }
}

struct DefinitionEntry: Codable {
    let definition: String
    let type: String
    let examples: [String]
    let definition_native: String?
    let cultural_notes: String?

    private enum CodingKeys: String, CodingKey {
        case definition, type, examples, definition_native, cultural_notes
    }
}

struct AudioReferences: Codable {
    let word_audio: Bool?
    let example_audio: [String: Bool] // text -> availability mapping

    private enum CodingKeys: String, CodingKey {
        case word_audio, example_audio
    }
}

// Audio fetch models for getting actual audio data
struct AudioDataResponse: Codable {
    let audio_data: String // Base64 encoded audio data
    let content_type: String
    let created_at: String
    let generated: Bool? // Whether this was generated on-demand

    private enum CodingKeys: String, CodingKey {
        case audio_data, content_type, created_at, generated
    }
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
    let validWordScore: Double // V3 validation score (0-1)
    let suggestion: String? // V3 suggested word if score < 0.9

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

        // Store V3 validation data - prefer top-level (v2.7.2 compat), fall back to definition_data
        self.validWordScore = response.valid_word_score ?? response.definition_data.valid_word_score ?? 1.0
        self.suggestion = response.suggestion ?? response.definition_data.suggestion
    }

    // Custom initializer for updating with audio data
    init(id: UUID = UUID(), word: String, phonetic: String?, learning_language: String, native_language: String, translations: [String] = [], meanings: [Meaning], audioData: Data?, hasWordAudio: Bool = false, exampleAudioAvailability: [String: Bool] = [:], validWordScore: Double = 1.0, suggestion: String? = nil) {
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
        self.validWordScore = validWordScore
        self.suggestion = suggestion
    }

    var isValid: Bool {
        return validWordScore >= 0.9
    }
}

struct Meaning: Codable {
    let partOfSpeech: String
    let definitions: [DefinitionDetail]

    private enum CodingKeys: String, CodingKey {
        case partOfSpeech, definitions
    }
}

struct DefinitionDetail: Codable {
    let definition: String
    let example: String?
    let synonyms: [String]?
    let antonyms: [String]?

    private enum CodingKeys: String, CodingKey {
        case definition, example, synonyms, antonyms
    }
}

// Saved Words Models
struct SavedWordsResponse: Codable {
    let user_id: String
    let saved_words: [SavedWord]
    let count: Int
    let due_only: Bool?

    private enum CodingKeys: String, CodingKey {
        case user_id, saved_words, count, due_only
    }
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
    let interval_days: Int
    let next_review_date: String?
    let last_reviewed_at: String?
    let is_toefl: Bool?
    let is_ielts: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, word, learning_language, native_language, created_at, review_count, interval_days, next_review_date, last_reviewed_at, is_toefl, is_ielts
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        learning_language = try container.decode(String.self, forKey: .learning_language)
        native_language = try container.decode(String.self, forKey: .native_language)
        created_at = try container.decode(String.self, forKey: .created_at)
        review_count = try container.decodeIfPresent(Int.self, forKey: .review_count) ?? 0
        interval_days = try container.decodeIfPresent(Int.self, forKey: .interval_days) ?? 1
        next_review_date = try container.decodeIfPresent(String.self, forKey: .next_review_date)
        last_reviewed_at = try container.decodeIfPresent(String.self, forKey: .last_reviewed_at)
        is_toefl = try container.decodeIfPresent(Bool.self, forKey: .is_toefl)
        is_ielts = try container.decodeIfPresent(Bool.self, forKey: .is_ielts)
        metadata = nil // We'll skip decoding metadata for now
    }
    
    // Convenience initializer for testing
    init(id: Int, word: String, learning_language: String, native_language: String, metadata: [String: Any]?, created_at: String, review_count: Int, interval_days: Int, next_review_date: String?, last_reviewed_at: String?, is_toefl: Bool? = nil, is_ielts: Bool? = nil) {
        self.id = id
        self.word = word
        self.learning_language = learning_language
        self.native_language = native_language
        self.metadata = metadata
        self.created_at = created_at
        self.review_count = review_count
        self.interval_days = interval_days
        self.next_review_date = next_review_date
        self.last_reviewed_at = last_reviewed_at
        self.is_toefl = is_toefl
        self.is_ielts = is_ielts
    }
}

// Review Models
struct ReviewSubmissionRequest: Codable {
    let user_id: String
    let word_id: Int
    let response: Bool

    private enum CodingKeys: String, CodingKey {
        case user_id, word_id, response
    }
}

struct ReviewSubmissionResponse: Codable {
    let success: Bool
    let word_id: Int
    let response: Bool
    let review_count: Int
    let interval_days: Int
    let next_review_date: String

    private enum CodingKeys: String, CodingKey {
        case success, word_id, response, review_count, interval_days, next_review_date
    }
}

// Next Due Words Models
struct NextDueWordsResponse: Codable {
    let user_id: String
    let saved_words: [SavedWord]
    let count: Int
    let limit: Int

    private enum CodingKeys: String, CodingKey {
        case user_id, saved_words, count, limit
    }
}

// Review Words Models (simplified for review_next endpoint)
struct ReviewWordsResponse: Codable {
    let user_id: String
    let saved_words: [ReviewWord]
    let count: Int

    private enum CodingKeys: String, CodingKey {
        case user_id, saved_words, count
    }
}

struct ReviewWord: Identifiable, Codable {
    let id: Int
    let word: String
    let learning_language: String
    let native_language: String

    private enum CodingKeys: String, CodingKey {
        case id, word, learning_language, native_language
    }
}


struct ReviewProgressStats: Codable {
    let reviews_today: Int
    let success_rate_today: Double
    let acquainted_to_familiar: Int
    let familiar_to_remembered: Int
    let remembered_to_unforgettable: Int
    let total_reviews: Int

    private enum CodingKeys: String, CodingKey {
        case reviews_today, success_rate_today, acquainted_to_familiar, familiar_to_remembered, remembered_to_unforgettable, total_reviews
    }
}

// Word Detail Models
struct WordDetails: Codable {
    let id: Int
    let word: String
    let learning_language: String
    let metadata: [String: Any]?
    let created_at: String
    let review_count: Int
    let interval_days: Int
    let next_review_date: String?
    let last_reviewed_at: String?
    let review_history: [ReviewHistoryEntry]
    
    private enum CodingKeys: String, CodingKey {
        case id, word, learning_language, created_at, review_count, interval_days, next_review_date, last_reviewed_at, review_history
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        learning_language = try container.decode(String.self, forKey: .learning_language)
        created_at = try container.decode(String.self, forKey: .created_at)
        review_count = try container.decode(Int.self, forKey: .review_count)
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

    private enum CodingKeys: String, CodingKey {
        case response, response_time_ms, reviewed_at
    }
}

// User Preferences Models
struct UserPreferences: Codable {
    let user_id: String
    let learning_language: String
    let native_language: String
    let user_name: String?
    let user_motto: String?
    let updated: Bool?

    private enum CodingKeys: String, CodingKey {
        case user_id, learning_language, native_language, user_name, user_motto, updated
    }
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

    private enum CodingKeys: String, CodingKey {
        case leaderboard, total_users
    }
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

    private enum CodingKeys: String, CodingKey {
        case word, language, scene_description, image_data, content_type, cached, created_at
    }
}

// Due Counts Models
struct DueCountsResponse: Codable {
    let user_id: String
    let overdue_count: Int
    let total_count: Int

    private enum CodingKeys: String, CodingKey {
        case user_id, overdue_count, total_count
    }
}

// Save Word Response Model
struct SaveWordResponse: Codable {
    let success: Bool
    let message: String
    let word_id: Int
    let created_at: String

    private enum CodingKeys: String, CodingKey {
        case success, message, word_id, created_at
    }
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

    private enum CodingKeys: String, CodingKey {
        case word_id, word, created_at, forgetting_curve, next_review_date, review_markers, all_markers
    }
}

struct CurveDataPointAPI: Codable {
    let date: String
    let retention: Double
    let is_projection: Bool?

    private enum CodingKeys: String, CodingKey {
        case date, retention, is_projection
    }
}

struct ReviewMarker: Codable {
    let date: String
    let success: Bool

    private enum CodingKeys: String, CodingKey {
        case date, success
    }
}

struct AllMarker: Codable {
    let date: String
    let type: String // "creation", "review", "next_review"
    let success: Bool?

    private enum CodingKeys: String, CodingKey {
        case date, type, success
    }
}

// MARK: - Test Preparation Models

struct TestSettings: Codable {
    let toefl_enabled: Bool
    let ielts_enabled: Bool
    let last_test_words_added: String?
    let learning_language: String
    let native_language: String
    let toefl_target_days: Int
    let ielts_target_days: Int

    private enum CodingKeys: String, CodingKey {
        case toefl_enabled, ielts_enabled, last_test_words_added, learning_language, native_language, toefl_target_days, ielts_target_days
    }
}

struct TestProgress: Codable {
    let saved: Int
    let total: Int
    let percentage: Double

    private enum CodingKeys: String, CodingKey {
        case saved, total, percentage
    }
}

struct TestSettingsResponse: Codable {
    let settings: TestSettings
    let progress: TestProgressData

    private enum CodingKeys: String, CodingKey {
        case settings, progress
    }
}

struct TestProgressData: Codable {
    let toefl: TestProgress?
    let ielts: TestProgress?

    private enum CodingKeys: String, CodingKey {
        case toefl, ielts
    }
}

struct TestSettingsUpdateRequest: Codable {
    let user_id: String
    let toefl_enabled: Bool?
    let ielts_enabled: Bool?
    let toefl_target_days: Int?
    let ielts_target_days: Int?

    private enum CodingKeys: String, CodingKey {
        case user_id, toefl_enabled, ielts_enabled, toefl_target_days, ielts_target_days
    }
}

struct TestSettingsUpdateResponse: Codable {
    let success: Bool
    let settings: TestSettings

    private enum CodingKeys: String, CodingKey {
        case success, settings
    }
}

struct TestVocabularyStatsResponse: Codable {
    let language: String
    let statistics: TestVocabularyStatistics

    private enum CodingKeys: String, CodingKey {
        case language, statistics
    }
}

struct TestVocabularyStatistics: Codable {
    let total_unique_words: Int
    let toefl_words: Int
    let ielts_words: Int
    let words_in_both: Int
    let toefl_exclusive: Int
    let ielts_exclusive: Int

    private enum CodingKeys: String, CodingKey {
        case total_unique_words, toefl_words, ielts_words, words_in_both, toefl_exclusive, ielts_exclusive
    }
}

// WordValidation struct remains as it's used by merged V1 endpoint
struct WordValidation: Codable {
    let confidence: Double
    let suggested: String?

    private enum CodingKeys: String, CodingKey {
        case confidence, suggested
    }
}

// MARK: - Schedule Models

/// Study schedule metadata returned when creating/refreshing a schedule
struct StudySchedule: Codable {
    let schedule_id: Int
    let days_remaining: Int
    let total_new_words: Int
    let daily_new_words: Int
    let test_practice_words_count: Int
    let non_test_practice_words_count: Int

    private enum CodingKeys: String, CodingKey {
        case schedule_id, days_remaining, total_new_words, daily_new_words,
             test_practice_words_count, non_test_practice_words_count
    }
}

/// Response when creating a schedule
struct CreateScheduleResponse: Codable {
    let success: Bool
    let schedule: StudySchedule

    private enum CodingKeys: String, CodingKey {
        case success, schedule
    }
}

/// Word in a practice session with expected retention
struct SchedulePracticeWord: Codable, Identifiable {
    let word: String
    let word_id: Int?  // Can be null for new words not yet saved
    let expected_retention: Double
    let review_number: Int

    var id: String {
        if let wordId = word_id {
            return "\(wordId)"
        } else {
            return word  // Use word itself as ID for unsaved words
        }
    }

    private enum CodingKeys: String, CodingKey {
        case word, word_id, expected_retention, review_number
    }
}

/// Today's schedule entry with new words and practice words
struct DailyScheduleEntry: Codable {
    let date: String
    let has_schedule: Bool
    let new_words: [String]
    let test_practice_words: [SchedulePracticeWord]
    let non_test_practice_words: [SchedulePracticeWord]
    let summary: ScheduleSummary?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case date, has_schedule, new_words, test_practice_words,
             non_test_practice_words, summary, message
    }
}

/// Summary of today's schedule
struct ScheduleSummary: Codable {
    let total_new: Int
    let total_test_practice: Int
    let total_non_test_practice: Int
    let total_words: Int

    private enum CodingKeys: String, CodingKey {
        case total_new, total_test_practice, total_non_test_practice, total_words
    }
}

/// Response when reviewing a new word from schedule
struct ReviewNewWordResponse: Codable {
    let success: Bool
    let word_id: Int
    let next_review_date: String

    private enum CodingKeys: String, CodingKey {
        case success, word_id, next_review_date
    }
}

/// Response when updating timezone
struct UpdateTimezoneResponse: Codable {
    let success: Bool
    let timezone: String

    private enum CodingKeys: String, CodingKey {
        case success, timezone
    }
}

/// Response when getting schedule range
struct GetScheduleRangeResponse: Codable {
    let schedules: [DailyScheduleEntry]

    private enum CodingKeys: String, CodingKey {
        case schedules
    }
}
