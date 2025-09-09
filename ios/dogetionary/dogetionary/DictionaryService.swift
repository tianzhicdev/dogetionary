//
//  DictionaryService.swift
//  dogetionary
//
//  Created by biubiu on 9/6/25.
//

import Foundation
import os.log

class DictionaryService: ObservableObject {
    static let shared = DictionaryService()
    private let baseURL = Configuration.effectiveBaseURL
    private let logger = Logger(subsystem: "com.dogetionary.app", category: "DictionaryService")
    
    private init() {}
    
    func saveWord(_ word: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/save") else {
            logger.error("Invalid URL for save endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("Saving word: \(word) for user: \(userID)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = [
            "word": word,
            "user_id": userID,
            "metadata": ["saved_at": Date().timeIntervalSince1970]
        ] as [String : Any]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            logger.error("Failed to encode save request: \(error.localizedDescription)")
            completion(.failure(DictionaryError.decodingError(error)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error saving word: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for save")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            self.logger.info("Save response status code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 201 {
                self.logger.info("Successfully saved word: \(word)")
                completion(.success(true))
            } else {
                self.logger.error("Server error saving word: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
            }
        }.resume()
    }
    
    func getSavedWords(dueOnly: Bool = false, completion: @escaping (Result<[SavedWord], Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        let dueOnlyParam = dueOnly ? "&due_only=true" : ""
        guard let url = URL(string: "\(baseURL)/saved_words?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)\(dueOnlyParam)") else {
            logger.error("Invalid URL for saved words endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("Fetching saved words for user: \(userID), dueOnly: \(dueOnly)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching saved words: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for saved words")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            self.logger.info("Saved words response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error fetching saved words: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received for saved words")
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let savedWordsResponse = try JSONDecoder().decode(SavedWordsResponse.self, from: data)
                self.logger.info("Successfully fetched \(savedWordsResponse.saved_words.count) saved words")
                completion(.success(savedWordsResponse.saved_words))
            } catch {
                self.logger.error("Failed to decode saved words response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func searchWord(_ word: String, completion: @escaping (Result<[Definition], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/word?w=\(word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word)") else {
            logger.error("Invalid URL for word: \(word)")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("Making request to: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            self.logger.info("Response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error with status code: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received")
                completion(.failure(DictionaryError.noData))
                return
            }
            
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                self.logger.info("Raw response: \(responseString)")
            }
            
            do {
                let response = try JSONDecoder().decode(WordDefinitionResponse.self, from: data)
                let definition = Definition(from: response)
                self.logger.info("Successfully decoded word definition for: \(response.word)")
                completion(.success([definition]))
            } catch {
                self.logger.error("Failed to decode response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    // MARK: - Review Methods
    
    func getDueWords(completion: @escaping (Result<[SavedWord], Error>) -> Void) {
        getSavedWords(dueOnly: true, completion: completion)
    }
    
    func getNextDueWords(limit: Int = 10, completion: @escaping (Result<[SavedWord], Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/saved_words/next_due?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)&limit=\(limit)") else {
            logger.error("Invalid URL for next due words endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("Fetching next due words for user: \(userID), limit: \(limit)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching next due words: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for next due words")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            self.logger.info("Next due words response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error fetching next due words: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received for next due words")
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let nextDueWordsResponse = try JSONDecoder().decode(NextDueWordsResponse.self, from: data)
                self.logger.info("Successfully fetched \(nextDueWordsResponse.saved_words.count) next due words")
                completion(.success(nextDueWordsResponse.saved_words))
            } catch {
                self.logger.error("Failed to decode next due words response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    func submitReview(wordID: Int, response: Bool, responseTimeMS: Int? = nil, reviewType: String = "regular", completion: @escaping (Result<ReviewSubmissionResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/reviews/submit") else {
            logger.error("Invalid URL for review submission endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("Submitting review - Word ID: \(wordID), Response: \(response), Type: \(reviewType), User: \(userID)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let reviewRequest = ReviewSubmissionRequest(
            user_id: userID,
            word_id: wordID,
            response: response,
            response_time_ms: responseTimeMS,
            review_type: reviewType
        )
        
        do {
            request.httpBody = try JSONEncoder().encode(reviewRequest)
        } catch {
            logger.error("Failed to encode review request: \(error.localizedDescription)")
            completion(.failure(DictionaryError.decodingError(error)))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error submitting review: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for review submission")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            self.logger.info("Review submission response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error submitting review: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received for review submission")
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let reviewResponse = try JSONDecoder().decode(ReviewSubmissionResponse.self, from: data)
                self.logger.info("Successfully submitted review for word ID: \(wordID)")
                completion(.success(reviewResponse))
            } catch {
                self.logger.error("Failed to decode review submission response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    func getReviewStats(completion: @escaping (Result<ReviewStats, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/reviews/stats?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)") else {
            logger.error("Invalid URL for review stats endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("Fetching review stats for user: \(userID)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching review stats: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for review stats")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            self.logger.info("Review stats response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error fetching review stats: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received for review stats")
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let reviewStats = try JSONDecoder().decode(ReviewStats.self, from: data)
                self.logger.info("Successfully fetched review stats")
                completion(.success(reviewStats))
            } catch {
                self.logger.error("Failed to decode review stats response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    func getWordDetails(wordID: Int, completion: @escaping (Result<WordDetails, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/words/\(wordID)/details?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)") else {
            logger.error("Invalid URL for word details endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("Fetching word details for word ID: \(wordID), user: \(userID)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching word details: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for word details")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            self.logger.info("Word details response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error fetching word details: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received for word details")
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let wordDetails = try JSONDecoder().decode(WordDetails.self, from: data)
                self.logger.info("Successfully fetched word details for: \(wordDetails.word)")
                completion(.success(wordDetails))
            } catch {
                self.logger.error("Failed to decode word details response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
}

enum DictionaryError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case serverError(Int)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .noData:
            return "No data received"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
