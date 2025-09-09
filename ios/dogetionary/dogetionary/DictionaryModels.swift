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
    let phonetic: String?
    let definitions: [DefinitionEntry]
    let _cache_info: CacheInfo?
    let audio: AudioData?
    
    private enum CodingKeys: String, CodingKey {
        case word, phonetic, definitions, _cache_info, audio
    }
}

struct DefinitionEntry: Codable {
    let type: String
    let definition: String
    let example: String
}

struct CacheInfo: Codable {
    let cached: Bool
    let access_count: Int
}

struct AudioData: Codable {
    let data: String // Base64 encoded audio data
    let content_type: String
    let generated_at: String?
}

// Legacy models for backward compatibility with UI
struct Definition: Identifiable, Codable {
    let id = UUID()
    let word: String
    let phonetic: String?
    let meanings: [Meaning]
    let audioData: Data? // Decoded audio data ready for playback
    
    init(from response: WordDefinitionResponse) {
        self.word = response.word
        self.phonetic = response.phonetic
        
        // Group definitions by type (part of speech)
        let groupedDefinitions = Dictionary(grouping: response.definitions) { $0.type }
        self.meanings = groupedDefinitions.map { (partOfSpeech, definitions) in
            let definitionDetails = definitions.map { def in
                DefinitionDetail(
                    definition: def.definition,
                    example: def.example,
                    synonyms: nil,
                    antonyms: nil
                )
            }
            return Meaning(partOfSpeech: partOfSpeech, definitions: definitionDetails)
        }
        
        // Decode audio data if available
        if let audioInfo = response.audio {
            self.audioData = Data(base64Encoded: audioInfo.data)
        } else {
            self.audioData = nil
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case word, phonetic, meanings, audioData
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
    let metadata: [String: Any]?
    let created_at: String
    let review_count: Int
    let ease_factor: Double
    let interval_days: Int
    let next_review_date: String?
    let last_reviewed_at: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, word, created_at, review_count, ease_factor, interval_days, next_review_date, last_reviewed_at
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        created_at = try container.decode(String.self, forKey: .created_at)
        review_count = try container.decodeIfPresent(Int.self, forKey: .review_count) ?? 0
        ease_factor = try container.decodeIfPresent(Double.self, forKey: .ease_factor) ?? 2.5
        interval_days = try container.decodeIfPresent(Int.self, forKey: .interval_days) ?? 1
        next_review_date = try container.decodeIfPresent(String.self, forKey: .next_review_date)
        last_reviewed_at = try container.decodeIfPresent(String.self, forKey: .last_reviewed_at)
        metadata = nil // We'll skip decoding metadata for now
    }
    
    // Convenience initializer for testing
    init(id: Int, word: String, metadata: [String: Any]?, created_at: String, review_count: Int, ease_factor: Double, interval_days: Int, next_review_date: String?, last_reviewed_at: String?) {
        self.id = id
        self.word = word
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
    let response_time_ms: Int?
    let review_type: String?
}

struct ReviewSubmissionResponse: Codable {
    let success: Bool
    let word_id: Int
    let response: Bool
    let review_type: String?
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

struct ReviewStats: Codable {
    let user_id: String
    let total_words: Int
    let due_today: Int
    let reviews_today: Int
    let success_rate_7_days: Double
    let streak_days: Int
}

// Word Detail Models
struct WordDetails: Codable {
    let id: Int
    let word: String
    let metadata: [String: Any]?
    let created_at: String
    let review_count: Int
    let ease_factor: Double
    let interval_days: Int
    let next_review_date: String?
    let last_reviewed_at: String?
    let review_history: [ReviewHistoryEntry]
    
    private enum CodingKeys: String, CodingKey {
        case id, word, created_at, review_count, ease_factor, interval_days, next_review_date, last_reviewed_at, review_history
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
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