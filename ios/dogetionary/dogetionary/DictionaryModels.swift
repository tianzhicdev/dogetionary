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
        case definition
        case type
        case part_of_speech
        case examples
        case definition_native
        case cultural_notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        definition = try container.decode(String.self, forKey: .definition)
        examples = try container.decode([String].self, forKey: .examples)
        definition_native = try container.decodeIfPresent(String.self, forKey: .definition_native)
        cultural_notes = try container.decodeIfPresent(String.self, forKey: .cultural_notes)

        // Try "type" first, fallback to "part_of_speech" for compatibility
        if let typeValue = try? container.decode(String.self, forKey: .type) {
            type = typeValue
        } else if let partOfSpeech = try? container.decode(String.self, forKey: .part_of_speech) {
            type = partOfSpeech
        } else {
            throw DecodingError.keyNotFound(CodingKeys.type, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Neither 'type' nor 'part_of_speech' field found"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definition, forKey: .definition)
        try container.encode(type, forKey: .type)
        try container.encode(examples, forKey: .examples)
        try container.encodeIfPresent(definition_native, forKey: .definition_native)
        try container.encodeIfPresent(cultural_notes, forKey: .cultural_notes)
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
    let correct_reviews: Int
    let incorrect_reviews: Int
    let word_progress_level: Int  // 1-7 scale (will be replaced with real logic later)
    let interval_days: Int
    let next_review_date: String?
    let last_reviewed_at: String?
    let is_toefl: Bool?
    let is_ielts: Bool?
    var is_known: Bool  // Whether user has marked this word as known

    private enum CodingKeys: String, CodingKey {
        case id, word, learning_language, native_language, created_at, review_count, correct_reviews, incorrect_reviews, word_progress_level, interval_days, next_review_date, last_reviewed_at, is_toefl, is_ielts, is_known
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        learning_language = try container.decode(String.self, forKey: .learning_language)
        native_language = try container.decode(String.self, forKey: .native_language)
        created_at = try container.decode(String.self, forKey: .created_at)
        review_count = try container.decodeIfPresent(Int.self, forKey: .review_count) ?? 0
        correct_reviews = try container.decodeIfPresent(Int.self, forKey: .correct_reviews) ?? 0
        incorrect_reviews = try container.decodeIfPresent(Int.self, forKey: .incorrect_reviews) ?? 0
        word_progress_level = try container.decodeIfPresent(Int.self, forKey: .word_progress_level) ?? 1
        interval_days = try container.decodeIfPresent(Int.self, forKey: .interval_days) ?? 1
        next_review_date = try container.decodeIfPresent(String.self, forKey: .next_review_date)
        last_reviewed_at = try container.decodeIfPresent(String.self, forKey: .last_reviewed_at)
        is_toefl = try container.decodeIfPresent(Bool.self, forKey: .is_toefl)
        is_ielts = try container.decodeIfPresent(Bool.self, forKey: .is_ielts)
        is_known = try container.decodeIfPresent(Bool.self, forKey: .is_known) ?? false
        metadata = nil // We'll skip decoding metadata for now
    }

    // Convenience initializer for testing
    init(id: Int, word: String, learning_language: String, native_language: String, metadata: [String: Any]?, created_at: String, review_count: Int, correct_reviews: Int, incorrect_reviews: Int, word_progress_level: Int, interval_days: Int, next_review_date: String?, last_reviewed_at: String?, is_toefl: Bool? = nil, is_ielts: Bool? = nil, is_known: Bool = false) {
        self.id = id
        self.word = word
        self.learning_language = learning_language
        self.native_language = native_language
        self.metadata = metadata
        self.created_at = created_at
        self.review_count = review_count
        self.correct_reviews = correct_reviews
        self.incorrect_reviews = incorrect_reviews
        self.word_progress_level = word_progress_level
        self.interval_days = interval_days
        self.next_review_date = next_review_date
        self.last_reviewed_at = last_reviewed_at
        self.is_toefl = is_toefl
        self.is_ielts = is_ielts
        self.is_known = is_known
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
    let new_score: Int?
    let new_badge: NewBadge?

    private enum CodingKeys: String, CodingKey {
        case success, word_id, response, review_count, interval_days, next_review_date, new_score, new_badge
    }
}

// Badge earned from review
struct NewBadge: Codable {
    let milestone: Int
    let title: String
    let symbol: String
    let tier: String
    let is_award: Bool
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
    let new_words_remaining_today: Int?  // NEW: count of scheduled new words remaining today

    private enum CodingKeys: String, CodingKey {
        case user_id, saved_words, count, new_words_remaining_today
    }
}

struct ReviewWord: Identifiable, Codable {
    let id: Int
    let word: String
    let learning_language: String
    let native_language: String
    let is_new_word: Bool?  // NEW: indicates if this is a scheduled new word

    private enum CodingKeys: String, CodingKey {
        case id, word, learning_language, native_language, is_new_word
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
    let user_has_schedule: Bool?  // NEW: Whether user has created any schedule (determines tab visibility)
    let has_schedule: Bool  // Whether today has tasks scheduled
    let test_type: String?  // TOEFL, IELTS, or BOTH
    let user_name: String?  // User's name for personalization
    let new_words: [String]?  // Optional when has_schedule is false
    let test_practice_words: [SchedulePracticeWord]?  // Optional when has_schedule is false
    let non_test_practice_words: [SchedulePracticeWord]?  // Optional when has_schedule is false
    let summary: ScheduleSummary?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case date, user_has_schedule, has_schedule, test_type, user_name, new_words, test_practice_words,
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
    let test_type: String?
    let user_name: String?

    private enum CodingKeys: String, CodingKey {
        case schedules, test_type, user_name
    }
}

// MARK: - Test Progress Models

/// Response from /v3/schedule/test-progress
struct TestProgressResponse: Codable {
    let has_schedule: Bool
    let test_type: String?  // "TOEFL", "IELTS", or "BOTH"
    let total_words: Int
    let saved_words: Int
    let progress: Double  // 0.0 to 1.0
    let streak_days: Int  // Consecutive days of completing reviews

    private enum CodingKeys: String, CodingKey {
        case has_schedule, test_type, total_words, saved_words, progress, streak_days
    }
}

// MARK: - Enhanced Review Question Models

/// Question option for multiple choice or fill-in-blank
struct QuestionOption: Codable, Identifiable {
    let id: String
    let text: String

    private enum CodingKeys: String, CodingKey {
        case id, text
    }
}

/// Enhanced review question data
struct ReviewQuestion: Codable {
    let question_type: String  // "recognition", "mc_definition", "mc_word", "fill_blank"
    let word: String
    let question_text: String
    let options: [QuestionOption]?
    let correct_answer: String?
    let sentence: String?  // For fill_blank type
    let sentence_translation: String?  // For fill_blank type
    let show_definition: Bool?  // For recognition type

    private enum CodingKeys: String, CodingKey {
        case question_type, word, question_text, options, correct_answer, sentence, sentence_translation, show_definition
    }
}

/// Response from /v3/review_next_enhanced
struct EnhancedReviewResponse: Codable {
    let user_id: String
    let word_id: Int?
    let word: String?
    let learning_language: String?
    let native_language: String?
    let is_new_word: Bool?
    let new_words_remaining_today: Int?
    let question: ReviewQuestion?
    let definition: DefinitionData?

    // Fields for "no words" response
    let count: Int?
    let message: String?
    let saved_words: [String]?

    // Helper to check if there's a word to review
    var hasWordToReview: Bool {
        return word_id != nil && word != nil && question != nil
    }

    private enum CodingKeys: String, CodingKey {
        case user_id, word_id, word, learning_language, native_language, is_new_word, new_words_remaining_today, question, definition, count, message, saved_words
    }
}

/// Enhanced review submission using composite key (word + learning_language + native_language)
struct EnhancedReviewSubmissionRequest: Codable {
    let user_id: String
    let word: String
    let learning_language: String
    let native_language: String
    let response: Bool
    let question_type: String?  // Optional for backward compatibility

    private enum CodingKeys: String, CodingKey {
        case user_id, word, learning_language, native_language, response, question_type
    }
}

/// Streak Days Response
struct StreakDaysResponse: Codable {
    let user_id: String
    let streak_days: Int

    private enum CodingKeys: String, CodingKey {
        case user_id, streak_days
    }
}

// MARK: - Batch Review Questions (Performance Optimization)

/// Single question from batch endpoint
struct BatchReviewQuestion: Codable, Identifiable {
    var id: String { word }  // Use word as unique ID (composite key with learning_language + native_language)
    let word: String
    let saved_word_id: Int?  // null for new words, present for saved words
    let source: String  // "new", "test_practice", "non_test_practice", "not_due_yet"
    let position: Int   // Position in sorted queue (0-indexed)
    let learning_language: String
    let native_language: String
    let question: ReviewQuestion
    let definition: DefinitionData?

    /// Human-readable source type for debug display
    var sourceLabel: String {
        switch source {
        case "new": return "New"
        case "test_practice": return "Test"
        case "non_test_practice": return "Prac"
        case "not_due_yet": return "Extra"
        default: return source
        }
    }
}

/// Batch endpoint response
struct BatchReviewResponse: Codable {
    let questions: [BatchReviewQuestion]
    let total_available: Int
    let has_more: Bool
}

// MARK: - Achievements

/// Achievement tier
enum AchievementTier: String, Codable {
    case beginner
    case intermediate
    case advanced
    case expert
}

/// Individual achievement
struct Achievement: Codable, Identifiable {
    let id = UUID()
    let milestone: Int
    let title: String
    let symbol: String
    let tier: AchievementTier
    let is_award: Bool
    let unlocked: Bool

    private enum CodingKeys: String, CodingKey {
        case milestone, title, symbol, tier, is_award, unlocked
    }
}

/// Achievement progress response
struct AchievementProgressResponse: Codable {
    let user_id: String
    let score: Int  // Score from reviews: failed = 1 point, success = 2 points
    let achievements: [Achievement]
    let next_milestone: Int?
    let next_achievement: AchievementInfo?
    let current_achievement: AchievementInfo?

    private enum CodingKeys: String, CodingKey {
        case user_id, score, achievements, next_milestone, next_achievement, current_achievement
    }
}

/// Achievement info (without unlocked status)
struct AchievementInfo: Codable {
    let milestone: Int
    let title: String
    let symbol: String
    let tier: AchievementTier
    let is_award: Bool

    private enum CodingKeys: String, CodingKey {
        case milestone, title, symbol, tier, is_award
    }
}

/// Practice status response for the Practice tab
struct PracticeStatusResponse: Codable {
    let user_id: String
    let new_words_count: Int           // Scheduled new words for today
    let test_practice_count: Int       // Test practice words from today's schedule
    let non_test_practice_count: Int   // Non-test practice words from today's schedule
    let not_due_yet_count: Int         // Words reviewed before, last review > 24h ago, not due yet
    let score: Int                     // Current score from reviews
    let has_practice: Bool             // Quick check: any practice available

    private enum CodingKeys: String, CodingKey {
        case user_id, new_words_count, test_practice_count, non_test_practice_count, not_due_yet_count, score, has_practice
    }
}
