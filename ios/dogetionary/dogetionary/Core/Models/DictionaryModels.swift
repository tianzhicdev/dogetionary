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

    // V4: Vocabulary learning enhancements
    let collocations: [String]?
    let synonyms: [String]?
    let antonyms: [String]?
    let comment: String?  // Optional usage notes (formality, frequency, connotation, confusions, tips)
    let source: String?  // Optional etymology or word origin
    let word_family: [WordFamilyEntry]?
    let cognates: String?
    let famous_quote: FamousQuote?

    private enum CodingKeys: String, CodingKey {
        case phonetic, word, translations, definitions, valid_word_score, suggestion
        case collocations, synonyms, antonyms, comment, source, word_family, cognates, famous_quote
    }
}

// V4: Word family entry for related word forms
struct WordFamilyEntry: Codable, Identifiable {
    let id = UUID()
    let word: String
    let part_of_speech: String

    private enum CodingKeys: String, CodingKey {
        case word, part_of_speech
    }
}

// V4: Famous quote with attribution
struct FamousQuote: Codable, Identifiable {
    let id = UUID()
    let quote: String
    let source: String

    private enum CodingKeys: String, CodingKey {
        case quote, source
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

    // V4: Vocabulary learning enhancements
    let collocations: [String]
    let synonyms: [String]
    let antonyms: [String]
    let comment: String?  // Optional usage notes (formality, frequency, connotation, confusions, tips)
    let source: String?  // Optional etymology
    let wordFamily: [WordFamilyEntry]
    let cognates: String?
    let famousQuote: FamousQuote?

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
                    antonyms: def.cultural_notes.map { [$0] } // Use antonyms field for cultural notes
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

        // Store V4 vocabulary learning data with safe defaults for backward compatibility
        self.collocations = response.definition_data.collocations ?? []
        self.synonyms = response.definition_data.synonyms ?? []
        self.antonyms = response.definition_data.antonyms ?? []
        self.comment = response.definition_data.comment
        self.source = response.definition_data.source
        self.wordFamily = response.definition_data.word_family ?? []
        self.cognates = response.definition_data.cognates
        self.famousQuote = response.definition_data.famous_quote
    }

    // Custom initializer for updating with audio data
    init(id: UUID = UUID(), word: String, phonetic: String?, learning_language: String, native_language: String, translations: [String] = [], meanings: [Meaning], audioData: Data?, hasWordAudio: Bool = false, exampleAudioAvailability: [String: Bool] = [:], validWordScore: Double = 1.0, suggestion: String? = nil, collocations: [String] = [], synonyms: [String] = [], antonyms: [String] = [], comment: String? = nil, source: String? = nil, wordFamily: [WordFamilyEntry] = [], cognates: String? = nil, famousQuote: FamousQuote? = nil) {
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
        self.collocations = collocations
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.comment = comment
        self.source = source
        self.wordFamily = wordFamily
        self.cognates = cognates
        self.famousQuote = famousQuote
    }

    var isValid: Bool {
        return validWordScore >= AppConstants.Validation.wordValidityThreshold
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

/// Response for efficient single-word saved check
struct IsWordSavedResponse: Codable {
    let is_saved: Bool
    let saved_word_id: Int?
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
    let is_demo: Bool?
    var is_known: Bool  // Whether user has marked this word as known

    private enum CodingKeys: String, CodingKey {
        case id, word, learning_language, native_language, created_at, review_count, correct_reviews, incorrect_reviews, word_progress_level, interval_days, next_review_date, last_reviewed_at, is_toefl, is_ielts, is_demo, is_known
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
        is_demo = try container.decodeIfPresent(Bool.self, forKey: .is_demo)
        is_known = try container.decodeIfPresent(Bool.self, forKey: .is_known) ?? false
        metadata = nil // We'll skip decoding metadata for now
    }

    // Convenience initializer for testing
    init(id: Int, word: String, learning_language: String, native_language: String, metadata: [String: Any]?, created_at: String, review_count: Int, correct_reviews: Int, incorrect_reviews: Int, word_progress_level: Int, interval_days: Int, next_review_date: String?, last_reviewed_at: String?, is_toefl: Bool? = nil, is_ielts: Bool? = nil, is_demo: Bool? = nil, is_known: Bool = false) {
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
        self.is_demo = is_demo
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
    let word: String?
    let word_id: Int
    let response: Bool
    let review_count: Int?  // Optional - removed from backend
    let interval_days: Int?  // Optional - removed from backend
    let next_review_date: String?  // Optional - removed from backend
    let new_score: Int?
    let new_badges: [NewBadge]?  // Array to support multiple badges (e.g., score milestone + test completion)
    let practice_status: EmbeddedPracticeStatus?  // Practice status embedded in response to avoid extra API calls

    private enum CodingKeys: String, CodingKey {
        case success, word, word_id, response, review_count, interval_days, next_review_date, new_score, new_badges, practice_status
    }
}

// Practice status embedded in review submission response
struct EmbeddedPracticeStatus: Codable {
    let user_id: String
    let due_word_count: Int
    let new_word_count_past_24h: Int
    let total_word_count: Int
    let score: Int
    let has_practice: Bool
    let reviews_past_24h: Int
    let streak_days: Int
    let bundle_progress: BundleProgress?

    private enum CodingKeys: String, CodingKey {
        case user_id, due_word_count, new_word_count_past_24h, total_word_count, score, has_practice, reviews_past_24h, streak_days, bundle_progress
    }
}

// Badge earned from review (ultra-minimal structure)
struct NewBadge: Codable {
    let badge_id: String      // "score_100" or "DEMO" or "TOEFL_BEGINNER"
    let title: String         // "First Steps" or "Demo Master"
    let description: String   // "100 points reached" or "Demo vocabulary completed!"
}

// Toggle exclude from practice response
struct ToggleExcludeResponse: Codable {
    let success: Bool
    let word_id: String?
    let word: String
    let is_excluded: Bool
    let previous_status: Bool
    let message: String

    private enum CodingKeys: String, CodingKey {
        case success, word_id, word, is_excluded, previous_status, message
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
    let test_prep: String?
    let study_duration_days: Int?
    let daily_time_commitment_minutes: Int?
    let updated: Bool?

    private enum CodingKeys: String, CodingKey {
        case user_id, learning_language, native_language, user_name, user_motto, test_prep, study_duration_days, daily_time_commitment_minutes, updated
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
    let score: Int?  // New field: 2 pts for correct, 1 pt for wrong

    private enum CodingKeys: String, CodingKey {
        case rank, user_id, user_name, user_motto, total_reviews, score
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

struct BatchForgettingCurveResponse: Codable {
    let curves: [ForgettingCurveResponse]
    let not_found: [Int]

    private enum CodingKeys: String, CodingKey {
        case curves, not_found
    }
}

// MARK: - Test Preparation Models

/// Test type enum with all available test levels
enum TestType: String, Codable, CaseIterable {
    case toeflBeginner = "TOEFL_BEGINNER"
    case toeflIntermediate = "TOEFL_INTERMEDIATE"
    case toeflAdvanced = "TOEFL_ADVANCED"
    case ieltsBeginner = "IELTS_BEGINNER"
    case ieltsIntermediate = "IELTS_INTERMEDIATE"
    case ieltsAdvanced = "IELTS_ADVANCED"
    case demo = "DEMO"
    case businessEnglish = "BUSINESS_ENGLISH"
    case everydayEnglish = "EVERYDAY_ENGLISH"

    /// Display name for UI
    var displayName: String {
        switch self {
        case .toeflBeginner: return "TOEFL Beginner"
        case .toeflIntermediate: return "TOEFL Intermediate"
        case .toeflAdvanced: return "TOEFL Advanced"
        case .ieltsBeginner: return "IELTS Beginner"
        case .ieltsIntermediate: return "IELTS Intermediate"
        case .ieltsAdvanced: return "IELTS Advanced"
        case .demo: return "Demo Bundle"
        case .businessEnglish: return "Business English"
        case .everydayEnglish: return "Everyday English"
        }
    }

    /// Base test name (TOEFL, IELTS, or DEMO)
    var baseTest: String {
        switch self {
        case .toeflBeginner, .toeflIntermediate, .toeflAdvanced:
            return "TOEFL"
        case .ieltsBeginner, .ieltsIntermediate, .ieltsAdvanced:
            return "IELTS"
        case .demo:
            return "DEMO"
        case .businessEnglish:
            return "BUSINESS_ENGLISH"
        case .everydayEnglish:
            return "EVERYDAY_ENGLISH"
        }
    }

    /// Level name (Beginner, Intermediate, Advanced, or nil for DEMO)
    var level: String? {
        switch self {
        case .toeflBeginner, .ieltsBeginner:
            return "Beginner"
        case .toeflIntermediate, .ieltsIntermediate:
            return "Intermediate"
        case .toeflAdvanced, .ieltsAdvanced:
            return "Advanced"
        case .demo, .businessEnglish, .everydayEnglish:
            return nil
        }
    }
}

struct TestSettings: Codable {
    // V3 API: active test type
    let active_test: String?  // "TOEFL_BEGINNER", "IELTS_ADVANCED", etc., or null
    let target_days: Int?

    // Legacy fields for backward compatibility
    let toefl_enabled: Bool?
    let ielts_enabled: Bool?
    let demo_enabled: Bool?
    let toefl_target_days: Int?
    let ielts_target_days: Int?
    let demo_target_days: Int?

    let last_test_words_added: String?
    let learning_language: String
    let native_language: String

    private enum CodingKeys: String, CodingKey {
        case active_test, target_days
        case toefl_enabled, ielts_enabled, demo_enabled
        case toefl_target_days, ielts_target_days, demo_target_days
        case last_test_words_added, learning_language, native_language
    }

    /// Get active test type from either new or legacy format
    var activeTestType: TestType? {
        if let activeTest = active_test {
            return TestType(rawValue: activeTest)
        }
        // Fallback to legacy format (map to advanced level)
        if toefl_enabled == true {
            return .toeflAdvanced
        }
        if ielts_enabled == true {
            return .ieltsAdvanced
        }
        if demo_enabled == true {
            return .demo
        }
        return nil
    }

    /// Get target days from either new or legacy format
    var effectiveTargetDays: Int {
        if let days = target_days {
            return days
        }
        // Fallback to legacy format
        if toefl_enabled == true, let days = toefl_target_days {
            return days
        }
        if ielts_enabled == true, let days = ielts_target_days {
            return days
        }
        if demo_enabled == true, let days = demo_target_days {
            return days
        }
        return 30  // Default
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
    // V3 API: single progress for active test
    let progress: TestProgress?

    // Legacy: individual progress for each test
    let toefl: TestProgress?
    let ielts: TestProgress?
    let demo: TestProgress?

    private enum CodingKeys: String, CodingKey {
        case progress
        case toefl, ielts, demo
    }

    /// Get progress for a specific test type
    func progress(for testType: TestType?) -> TestProgress? {
        // Try V3 API first
        if let progress = progress {
            return progress
        }
        // Fallback to legacy format
        guard let testType = testType else { return nil }
        switch testType {
        case .toeflBeginner, .toeflIntermediate, .toeflAdvanced:
            return toefl
        case .ieltsBeginner, .ieltsIntermediate, .ieltsAdvanced:
            return ielts
        case .demo:
            return demo
        case .businessEnglish, .everydayEnglish:
            // New bundle types - no legacy format
            return nil
        }
    }
}

struct TestSettingsUpdateRequest: Codable {
    let user_id: String

    // V3 API format (preferred)
    let test_type: String?  // "TOEFL_BEGINNER", null, etc.
    let target_days: Int?

    // Legacy API format for backward compatibility
    let toefl_enabled: Bool?
    let ielts_enabled: Bool?
    let demo_enabled: Bool?
    let toefl_target_days: Int?
    let ielts_target_days: Int?
    let demo_target_days: Int?

    private enum CodingKeys: String, CodingKey {
        case user_id
        case test_type, target_days
        case toefl_enabled, ielts_enabled, demo_enabled
        case toefl_target_days, ielts_target_days, demo_target_days
    }

    /// Create request using new V3 API format
    init(userID: String, testType: TestType?, targetDays: Int?) {
        self.user_id = userID
        self.test_type = testType?.rawValue
        self.target_days = targetDays
        // Legacy fields set to nil
        self.toefl_enabled = nil
        self.ielts_enabled = nil
        self.demo_enabled = nil
        self.toefl_target_days = nil
        self.ielts_target_days = nil
        self.demo_target_days = nil
    }

    /// Create request using legacy API format (for backward compatibility)
    init(userID: String, toeflEnabled: Bool?, ieltsEnabled: Bool?, demoEnabled: Bool?, toeflTargetDays: Int?, ieltsTargetDays: Int?, demoTargetDays: Int?) {
        self.user_id = userID
        self.test_type = nil
        self.target_days = nil
        self.toefl_enabled = toeflEnabled
        self.ielts_enabled = ieltsEnabled
        self.demo_enabled = demoEnabled
        self.toefl_target_days = toeflTargetDays
        self.ielts_target_days = ieltsTargetDays
        self.demo_target_days = demoTargetDays
    }

    /// Custom encoding to ensure test_type field is always included (even when nil)
    /// This is required for the backend to distinguish between V3 and legacy API formats
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(user_id, forKey: .user_id)

        // V3 API fields - always encode test_type if it's not nil OR if target_days is set
        // This ensures the backend recognizes it as V3 API format
        if test_type != nil || target_days != nil {
            try container.encode(test_type, forKey: .test_type)  // Explicitly encode nil as null
            try container.encodeIfPresent(target_days, forKey: .target_days)
        }

        // Legacy API fields - only encode if they're not nil
        try container.encodeIfPresent(toefl_enabled, forKey: .toefl_enabled)
        try container.encodeIfPresent(ielts_enabled, forKey: .ielts_enabled)
        try container.encodeIfPresent(demo_enabled, forKey: .demo_enabled)
        try container.encodeIfPresent(toefl_target_days, forKey: .toefl_target_days)
        try container.encodeIfPresent(ielts_target_days, forKey: .ielts_target_days)
        try container.encodeIfPresent(demo_target_days, forKey: .demo_target_days)
    }
}

struct TestSettingsUpdateResponse: Codable {
    let success: Bool
    let settings: TestSettings

    private enum CodingKeys: String, CodingKey {
        case success, settings
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

/// Word in a practice session
struct SchedulePracticeWord: Codable, Identifiable {
    let word: String
    let word_id: Int?  // Can be null for new words not yet saved
    let review_number: Int

    var id: String {
        if let wordId = word_id {
            return "\(wordId)"
        } else {
            return word  // Use word itself as ID for unsaved words
        }
    }

    private enum CodingKeys: String, CodingKey {
        case word, word_id, review_number
    }
}

/// Today's schedule entry with new words and practice words
struct DailyScheduleEntry: Codable {
    let date: String
    let user_has_schedule: Bool?  // Whether user has created any schedule (determines tab visibility)
    let has_schedule: Bool  // Whether today has tasks scheduled
    let test_type: String?  // TOEFL, IELTS, or BOTH
    let user_name: String?  // User's name for personalization
    let new_words: [String]?  // Remaining new words (not yet reviewed today)
    let new_words_completed: [String]?  // New words already reviewed today
    let test_practice_words: [SchedulePracticeWord]?  // Remaining test practice words
    let test_practice_words_completed: [SchedulePracticeWord]?  // Test practice words already reviewed today
    let non_test_practice_words: [SchedulePracticeWord]?  // Remaining non-test practice words
    let non_test_practice_words_completed: [SchedulePracticeWord]?  // Non-test practice words already reviewed today
    let summary: ScheduleSummary?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case date, user_has_schedule, has_schedule, test_type, user_name, new_words, new_words_completed,
             test_practice_words, test_practice_words_completed, non_test_practice_words,
             non_test_practice_words_completed, summary, message
    }
}

/// Summary of today's schedule
struct ScheduleSummary: Codable {
    let total_new: Int
    let total_new_remaining: Int?
    let total_new_completed: Int?
    let total_test_practice: Int
    let total_test_practice_remaining: Int?
    let total_test_practice_completed: Int?
    let total_non_test_practice: Int
    let total_non_test_practice_remaining: Int?
    let total_non_test_practice_completed: Int?
    let total_words: Int
    let total_remaining: Int?
    let total_completed: Int?

    private enum CodingKeys: String, CodingKey {
        case total_new, total_new_remaining, total_new_completed,
             total_test_practice, total_test_practice_remaining, total_test_practice_completed,
             total_non_test_practice, total_non_test_practice_remaining, total_non_test_practice_completed,
             total_words, total_remaining, total_completed
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
    let text_native: String?  // Native language translation (optional)

    init(id: String, text: String, text_native: String? = nil) {
        self.id = id
        self.text = text
        self.text_native = text_native
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, text_native
    }
}

/// Video metadata for video questions
struct VideoMetadata: Codable {
    let movie_title: String?
    let movie_year: Int?
    let title: String?  // Fallback if movie_title is not available

    private enum CodingKeys: String, CodingKey {
        case movie_title, movie_year, title
    }
}

/// Enhanced review question data
struct ReviewQuestion: Codable {
    let question_type: String  // "recognition", "mc_definition", "mc_word", "fill_blank", "pronounce_sentence", "video_mc"
    let word: String
    let question_text: String
    let options: [QuestionOption]?
    let correct_answer: String?
    let sentence: String?  // For fill_blank and pronounce_sentence types
    let sentence_translation: String?  // For fill_blank and pronounce_sentence types
    let show_definition: Bool?  // For recognition type
    let audio_url: String?  // For pronounce_sentence type (base64 encoded audio data)
    let evaluation_threshold: Double?  // For pronounce_sentence type (minimum score to pass, default 0.7)

    // Video question fields
    let video_id: Int?  // For video_mc type - ID of the video to display
    let show_word_before_video: Bool?  // For video_mc type - whether to show word before playing video
    let audio_transcript: String?  // For video_mc type - Whisper-generated transcript from video audio
    let video_metadata: VideoMetadata?  // For video_mc type - Movie title and year

    private enum CodingKeys: String, CodingKey {
        case question_type, word, question_text, options, correct_answer, sentence, sentence_translation, show_definition, audio_url, evaluation_threshold, video_id, show_word_before_video, audio_transcript, video_metadata
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
    let definition: WordDefinitionResponse?  // Full definition format (same as search API)

    /// Human-readable source type for debug display
    var sourceLabel: String {
        switch source {
        // New source values (v3 API)
        case "DUE": return "Due"
        case "BUNDLE": return "Bundle"
        case "EVERYDAY": return "Everyday"
        case "RANDOM": return "Random"
        // Legacy source values (backward compatibility)
        case "new": return "New"
        case "test_practice": return "Test"
        case "non_test_practice": return "Prac"
        case "not_due_yet": return "Extra"
        case "due": return "Due"
        case "new_bundle": return "Bundle"
        case "everyday_english": return "Everyday"
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

/// Test vocabulary progress for a single test
struct TestVocabularyProgress: Codable {
    let saved_test_words: Int
    let total_test_words: Int

    // Computed property to check if badge is earned
    var isEarned: Bool {
        return saved_test_words >= total_test_words && total_test_words > 0
    }
}

/// Test vocabulary awards response - dictionary of test name to progress
typealias TestVocabularyAwardsResponse = [String: TestVocabularyProgress]

/// Bundle progress information (overall completion of active bundle)
struct BundleProgress: Codable {
    let saved_words: Int      // Words user has saved from this bundle
    let total_words: Int      // Total words in this bundle
    let percentage: Int       // Completion percentage (0-100)
}

/// Practice status response for the Practice tab
struct PracticeStatusResponse: Codable {
    let user_id: String
    let due_word_count: Int            // Words that are due for review (next_review <= NOW)
    let new_word_count_past_24h: Int   // Words saved in the last 24 hours
    let total_word_count: Int          // Total saved words
    let score: Int                     // Current score from reviews
    let has_practice: Bool             // Quick check: any practice available
    let reviews_past_24h: Int          // Number of reviews (questions answered) in past 24 hours
    let bundle_progress: BundleProgress?  // Overall bundle completion (nil if no active bundle)

    private enum CodingKeys: String, CodingKey {
        case user_id, due_word_count, new_word_count_past_24h, total_word_count, score, has_practice, reviews_past_24h, bundle_progress
    }
}

// MARK: - App Version Check

/// App version check status
enum AppVersionStatus: String, Codable {
    case ok = "ok"
    case upgradeRequired = "upgrade_required"
    case upgradeRecommended = "upgrade_recommended"
}

/// App version check response
struct AppVersionResponse: Codable {
    let status: AppVersionStatus
    let min_version: String?
    let latest_version: String?
    let upgrade_url: String?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case status, min_version, latest_version, upgrade_url, message
    }
}

// MARK: - Vocabulary Count Models

/// Study plan suggestion with days and words per day
struct StudyPlan: Codable {
    let days: Int
    let words_per_day: Int

    private enum CodingKeys: String, CodingKey {
        case days, words_per_day
    }
}

/// Vocabulary count info for a single test type
struct VocabularyCountInfo: Codable {
    let total_words: Int
    let study_plans: [StudyPlan]

    private enum CodingKeys: String, CodingKey {
        case total_words, study_plans
    }
}

/// Response from /v3/api/test-vocabulary-count endpoint
struct VocabularyCountResponse: Codable {
    // Backward compatible top-level fields (for single test query)
    let total_words: Int?
    let study_plans: [StudyPlan]?

    // New format (supports multiple tests)
    let counts: [String: VocabularyCountInfo]

    private enum CodingKeys: String, CodingKey {
        case total_words, study_plans, counts
    }

    /// Get count for a specific test type
    func count(for testType: TestType) -> VocabularyCountInfo? {
        return counts[testType.rawValue]
    }

    /// Get all counts as dictionary with TestType keys
    func allCounts() -> [TestType: VocabularyCountInfo] {
        var result: [TestType: VocabularyCountInfo] = [:]
        for (key, value) in counts {
            if let testType = TestType(rawValue: key) {
                result[testType] = value
            }
        }
        return result
    }
}

// MARK: - Pronunciation Models

/// Response from /v3/review/pronounce endpoint
struct PronunciationEvaluationResult: Codable {
    let success: Bool
    let passed: Bool
    let similarity_score: Double
    let recognized_text: String
    let feedback: String
    let evaluation_threshold: Double
    let review_id: Int
    let next_interval_days: Int

    private enum CodingKeys: String, CodingKey {
        case success, passed, similarity_score, recognized_text, feedback,
             evaluation_threshold, review_id, next_interval_days
    }
}
