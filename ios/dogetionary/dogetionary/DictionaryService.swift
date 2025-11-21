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
    
    // MARK: - Logging Helper
    
    private func performNetworkRequest<T: Codable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        responseType: T.Type,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let body = body {
            request.httpBody = body
        }
        
        // Log request details
        logger.info("REQUEST: \(method) \(url.absoluteString)")
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            logger.info("REQUEST BODY: \(bodyString)")
        }
        
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
            
            // Log response status and headers
            self.logger.info("RESPONSE STATUS: \(httpResponse.statusCode)")
            self.logger.info("RESPONSE HEADERS: \(httpResponse.allHeaderFields)")
            
            guard let data = data else {
                self.logger.error("No data received")
                completion(.failure(DictionaryError.noData))
                return
            }
            
            // Log raw response data for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                self.logger.info("RAW RESPONSE: \(responseString)")
            } else {
                self.logger.error("Could not convert response data to string")
            }
            
            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                do {
                    let response = try JSONDecoder().decode(responseType, from: data)
                    self.logger.info("Successfully decoded response")
                    completion(.success(response))
                } catch {
                    self.logger.error("Failed to decode response: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        self.logger.error("Detailed decoding error: \(decodingError)")
                    }
                    completion(.failure(DictionaryError.decodingError(error)))
                }
            } else {
                self.logger.error("HTTP error: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
            }
        }.resume()
    }
    
    func saveWord(_ word: String, completion: @escaping (Result<Int, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/save") else {
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
            "learning_language": UserManager.shared.learningLanguage,
            "native_language": UserManager.shared.nativeLanguage,
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
                guard let data = data else {
                    self.logger.error("No data received from save endpoint")
                    completion(.failure(DictionaryError.noData))
                    return
                }

                do {
                    let saveResponse = try JSONDecoder().decode(SaveWordResponse.self, from: data)
                    self.logger.info("Successfully saved word: \(word) with ID: \(saveResponse.word_id)")
                    completion(.success(saveResponse.word_id))
                } catch {
                    self.logger.error("Failed to decode save response: \(error.localizedDescription)")
                    completion(.failure(DictionaryError.decodingError(error)))
                }
            } else {
                self.logger.error("Server error saving word: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
            }
        }.resume()
    }
    
    func getSavedWords(dueOnly: Bool = false, completion: @escaping (Result<[SavedWord], Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        let dueOnlyParam = dueOnly ? "&due_only=true" : ""
        guard let url = URL(string: "\(baseURL)/v3/saved_words?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)\(dueOnlyParam)") else {
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
                // If endpoint doesn't exist (404), return empty array instead of error
                if httpResponse.statusCode == 404 {
                    self.logger.info("Saved words endpoint not found, returning empty array")
                    completion(.success([]))
                    return
                }
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
        let userID = UserManager.shared.getUserID()
        let learningLang = UserManager.shared.learningLanguage
        let nativeLang = UserManager.shared.nativeLanguage
        searchWord(word, learningLanguage: learningLang, nativeLanguage: nativeLang, completion: completion)
    }

    func searchWord(_ word: String, learningLanguage: String, nativeLanguage: String, completion: @escaping (Result<[Definition], Error>) -> Void) {
        let userID = UserManager.shared.getUserID()

        guard let url = URL(string: "\(baseURL)/v3/word?w=\(word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word)&user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)&learning_lang=\(learningLanguage)&native_lang=\(nativeLanguage)") else {
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
                
                // Preload word audio for better UX
                self.fetchAudioForText(definition.word, language: learningLanguage) { audioData in
                    // Audio loading happens in background, UI already has the definition
                }
                
                self.logger.info("Successfully decoded word definition for: \(response.word)")
                completion(.success([definition]))
            } catch {
                self.logger.error("Failed to decode response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func unsaveWord(wordID: Int, completion: @escaping (Result<Bool, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/unsave") else {
            logger.error("Invalid URL for v3/unsave endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Unsaving word ID: \(wordID) for user: \(userID)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = [
            "word_id": wordID,
            "user_id": userID
        ] as [String : Any]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            logger.error("Failed to encode unsave request: \(error.localizedDescription)")
            completion(.failure(DictionaryError.decodingError(error)))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error unsaving word: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for unsave")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            self.logger.info("Unsave response status code: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200 {
                self.logger.info("Successfully unsaved word ID: \(wordID)")
                completion(.success(true))
            } else if httpResponse.statusCode == 404 {
                self.logger.info("Word ID not found in saved words: \(wordID)")
                completion(.success(false))
            } else {
                self.logger.error("Server error unsaving word: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
            }
        }.resume()
    }

    /// Mark a word as known (or learning)
    /// Known words are excluded from reviews and schedules
    func markWordAsKnown(wordID: Int, isKnown: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/words/\(wordID)/mark-known") else {
            logger.error("Invalid URL for mark-known endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Marking word ID: \(wordID) as \(isKnown ? "known" : "learning") for user: \(userID)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "user_id": userID,
            "is_known": isKnown
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            logger.error("Failed to encode mark-known request: \(error.localizedDescription)")
            completion(.failure(DictionaryError.decodingError(error)))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error marking word as known: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for mark-known")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            self.logger.info("Mark-known response status code: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 200 {
                self.logger.info("Successfully marked word ID: \(wordID) as \(isKnown ? "known" : "learning")")
                completion(.success(true))
            } else if httpResponse.statusCode == 404 {
                self.logger.error("Word not found: \(wordID)")
                completion(.failure(DictionaryError.notFound))
            } else {
                self.logger.error("Server error marking word as known: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
            }
        }.resume()
    }


    // MARK: - Audio Methods

    func fetchAudioForText(_ text: String, language: String, completion: @escaping (Data?) -> Void) {
        // URL encode the text to handle special characters and spaces
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/v3/audio/\(encodedText)/\(language)") else {
            logger.error("Invalid URL for text: '\(text)' language: \(language)")
            completion(nil)
            return
        }
        
        logger.info("Fetching/generating audio for text: '\(text)' in \(language)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching audio: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for audio")
                completion(nil)
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error fetching audio: \(httpResponse.statusCode)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                self.logger.error("No audio data received")
                completion(nil)
                return
            }
            
            do {
                let audioResponse = try JSONDecoder().decode(AudioDataResponse.self, from: data)
                let audioData = Data(base64Encoded: audioResponse.audio_data)
                
                if audioResponse.generated == true {
                    self.logger.info("Successfully generated and fetched audio for text: '\(text)'")
                } else {
                    self.logger.info("Successfully fetched cached audio for text: '\(text)'")
                }
                
                completion(audioData)
            } catch {
                self.logger.error("Failed to decode audio response: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - Review Methods
    
    func getDueWords(completion: @escaping (Result<[SavedWord], Error>) -> Void) {
        getSavedWords(dueOnly: true, completion: completion)
    }
    
    func getNextDueWords(limit: Int = 10, completion: @escaping (Result<[SavedWord], Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/saved_words/next_due?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)&limit=\(limit)") else {
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
    
    func submitReview(wordID: Int, response: Bool, questionType: String? = nil, completion: @escaping (Result<ReviewSubmissionResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/reviews/submit") else {
            logger.error("Invalid URL for review submission endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Submitting review - Word ID: \(wordID), Response: \(response), Question Type: \(questionType ?? "recognition"), User: \(userID)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let reviewRequest = EnhancedReviewSubmissionRequest(
            user_id: userID,
            word_id: wordID,
            response: response,
            question_type: questionType
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

            if httpResponse.statusCode == 404 {
                // Word not found (likely already deleted or not in user's list)
                // Treat as success to allow UI to continue
                self.logger.info("Review submission returned 404 - treating as success (word may have been deleted)")
                let mockResponse = ReviewSubmissionResponse(
                    success: true,
                    word_id: wordID,
                    response: reviewRequest.response,
                    review_count: 0,
                    interval_days: 1,
                    next_review_date: ""
                )
                completion(.success(mockResponse))
                return
            }

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
    
    
    func getWordDetails(wordID: Int, completion: @escaping (Result<WordDetails, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/words/\(wordID)/details?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)") else {
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
    
    // MARK: - User Preferences
    
    func getUserPreferences(userID: String, completion: @escaping (Result<UserPreferences, Error>) -> Void) {
        guard let encodedUserID = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/v3/users/\(encodedUserID)/preferences") else {
            logger.error("Invalid URL for user preferences GET endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("Fetching user preferences for: \(userID)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error fetching user preferences: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for user preferences")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            self.logger.info("User preferences GET response status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error fetching user preferences: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received for user preferences")
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let preferences = try JSONDecoder().decode(UserPreferences.self, from: data)
                self.logger.info("Successfully fetched user preferences: learning=\(preferences.learning_language), native=\(preferences.native_language)")
                completion(.success(preferences))
            } catch {
                self.logger.error("Failed to decode user preferences response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    func updateUserPreferences(userID: String, learningLanguage: String, nativeLanguage: String, userName: String, userMotto: String, testPrep: String? = nil, studyDurationDays: Int? = nil, completion: @escaping (Result<UserPreferences, Error>) -> Void) {
        guard let encodedUserID = userID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(baseURL)/v3/users/\(encodedUserID)/preferences") else {
            logger.error("Invalid URL for user preferences POST endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Updating user preferences for: \(userID) - learning: \(learningLanguage), native: \(nativeLanguage), name: \(userName), motto: \(userMotto), testPrep: \(testPrep ?? "nil"), duration: \(studyDurationDays ?? 0)")

        var requestBody: [String: Any] = [
            "learning_language": learningLanguage,
            "native_language": nativeLanguage,
            "user_name": userName,
            "user_motto": userMotto
        ]

        if let testPrep = testPrep {
            requestBody["test_prep"] = testPrep
        }

        if let studyDurationDays = studyDurationDays {
            requestBody["study_duration_days"] = studyDurationDays
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            logger.error("Failed to serialize user preferences request")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error updating user preferences: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for user preferences update")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            self.logger.info("User preferences POST response status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error updating user preferences: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received for user preferences update")
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let preferences = try JSONDecoder().decode(UserPreferences.self, from: data)
                self.logger.info("Successfully updated user preferences")
                completion(.success(preferences))
            } catch {
                self.logger.error("Failed to decode user preferences update response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    func getNextReviewWord(completion: @escaping (Result<[ReviewWord], Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/review_next?user_id=\(userID)") else {
            logger.error("Invalid URL for next review word endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching next review word for user: \(userID)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            // Log request details
            self.logger.info("REQUEST: GET \(url.absoluteString)")

            if let error = error {
                self.logger.error("Network error getting next review word: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type getting next review word")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            // Log response status and headers
            self.logger.info("RESPONSE STATUS: \(httpResponse.statusCode)")
            self.logger.info("RESPONSE HEADERS: \(httpResponse.allHeaderFields)")

            guard httpResponse.statusCode == 200 else {
                self.logger.error("HTTP error getting next review word: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received getting next review word")
                completion(.failure(DictionaryError.noData))
                return
            }

            // Log raw response data for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                self.logger.info("RAW RESPONSE: \(responseString)")
            } else {
                self.logger.error("Could not convert response data to string")
            }

            do {
                let response = try JSONDecoder().decode(ReviewWordsResponse.self, from: data)
                self.logger.info("Successfully decoded next review word response - count: \(response.count), words: \(response.saved_words.count)")

                completion(.success(response.saved_words))
            } catch {
                self.logger.error("Failed to decode next review word response: \(error.localizedDescription)")
                if let decodingError = error as? DecodingError {
                    self.logger.error("Detailed decoding error: \(decodingError)")
                }
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    /// Get next review word with scheduled new words integration
    /// This endpoint prioritizes scheduled new words from today's study schedule
    /// Returns the full response including new_words_remaining_today count
    func getNextReviewWordWithScheduledNewWords(completion: @escaping (Result<ReviewWordsResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/next-review-word-with-scheduled-new-words?user_id=\(userID)") else {
            logger.error("Invalid URL for next review word with scheduled new words endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching next review word with scheduled new words for user: \(userID)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            // Log request details
            self.logger.info("REQUEST: GET \(url.absoluteString)")

            if let error = error {
                self.logger.error("Network error getting next review word: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type getting next review word")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            // Log response status and headers
            self.logger.info("RESPONSE STATUS: \(httpResponse.statusCode)")
            self.logger.info("RESPONSE HEADERS: \(httpResponse.allHeaderFields)")

            guard httpResponse.statusCode == 200 else {
                self.logger.error("HTTP error getting next review word: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received getting next review word")
                completion(.failure(DictionaryError.noData))
                return
            }

            // Log raw response data for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                self.logger.info("RAW RESPONSE: \(responseString)")
            } else {
                self.logger.error("Could not convert response data to string")
            }

            do {
                let response = try JSONDecoder().decode(ReviewWordsResponse.self, from: data)
                self.logger.info("Successfully decoded next review word response - count: \(response.count), words: \(response.saved_words.count), new words remaining: \(response.new_words_remaining_today ?? 0)")

                completion(.success(response))
            } catch {
                self.logger.error("Failed to decode next review word response: \(error.localizedDescription)")
                if let decodingError = error as? DecodingError {
                    self.logger.error("Detailed decoding error: \(decodingError)")
                }
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    /// Get next review word with enhanced question types (multiple choice, fill-in-blank, etc.)
    /// This endpoint provides diverse question types for more engaging review experience
    func getNextReviewWordEnhanced(completion: @escaping (Result<EnhancedReviewResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/review_next_enhanced?user_id=\(userID)") else {
            logger.error("Invalid URL for enhanced review endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching enhanced review word for user: \(userID)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            self.logger.info("REQUEST: GET \(url.absoluteString)")

            if let error = error {
                self.logger.error("Network error getting enhanced review: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type getting enhanced review")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            self.logger.info("RESPONSE STATUS: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                self.logger.error("HTTP error getting enhanced review: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received getting enhanced review")
                completion(.failure(DictionaryError.noData))
                return
            }

            if let responseString = String(data: data, encoding: .utf8) {
                self.logger.info("RAW RESPONSE: \(responseString)")
            }

            do {
                let reviewResponse = try JSONDecoder().decode(EnhancedReviewResponse.self, from: data)
                if let questionType = reviewResponse.question?.question_type {
                    self.logger.info("Successfully decoded enhanced review response - question type: \(questionType)")
                } else {
                    self.logger.info("Successfully decoded enhanced review response - no words available")
                }
                completion(.success(reviewResponse))
            } catch {
                self.logger.error("Failed to decode enhanced review response: \(error.localizedDescription)")
                if let decodingError = error as? DecodingError {
                    self.logger.error("Detailed decoding error: \(decodingError)")
                }
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func getDueCounts(completion: @escaping (Result<DueCountsResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/due_counts?user_id=\(userID)") else {
            logger.error("Invalid URL for due counts endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("Fetching due counts for user: \(userID)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                self.logger.error("Network error getting due counts: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type getting due counts")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("HTTP error getting due counts: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received getting due counts")
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(DueCountsResponse.self, from: data)
                self.logger.info("Successfully fetched due counts - overdue: \(response.overdue_count), total: \(response.total_count)")
                completion(.success(response))
            } catch {
                self.logger.error("Failed to decode due counts response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    func getReviewStatistics(completion: @escaping (Result<ReviewStatsData, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()

        guard let url = URL(string: "\(baseURL)/v3/review_statistics?user_id=\(userID)") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("🔍 Fetching review statistics for user \(userID)")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("❌ Review statistics request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("❌ Review statistics request failed with status: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let stats = try JSONDecoder().decode(ReviewStatsData.self, from: data)
                self.logger.info("✅ Successfully fetched review statistics")
                completion(.success(stats))
            } catch {
                self.logger.error("Failed to decode review statistics: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    func getWeeklyReviewCounts(completion: @escaping (Result<[DailyReviewCount], Error>) -> Void) {
        let userID = UserManager.shared.getUserID()

        guard let url = URL(string: "\(baseURL)/v3/weekly_review_counts?user_id=\(userID)") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("🔍 Fetching weekly review counts for user \(userID)")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("❌ Weekly review counts request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("❌ Weekly review counts request failed with status: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(WeeklyReviewResponse.self, from: data)
                self.logger.info("✅ Successfully fetched weekly review counts")
                completion(.success(response.daily_counts))
            } catch {
                self.logger.error("Failed to decode weekly review counts: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func getProgressFunnelData(completion: @escaping (Result<ProgressFunnelData, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/progress_funnel?user_id=\(userID)") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("🔍 Fetching progress funnel data for user \(userID)")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("❌ Progress funnel request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("❌ Progress funnel request failed with status: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let progressData = try JSONDecoder().decode(ProgressFunnelData.self, from: data)
                self.logger.info("✅ Successfully fetched progress funnel data")
                completion(.success(progressData))
            } catch {
                self.logger.error("Failed to decode progress funnel response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    func getReviewActivity(from startDate: Date, to endDate: Date, completion: @escaping (Result<[String], Error>) -> Void) {
        let formatter = ISO8601DateFormatter()
        let startDateString = formatter.string(from: startDate)
        let endDateString = formatter.string(from: endDate)
        let userID = UserManager.shared.getUserID()
        
        guard let url = URL(string: "\(baseURL)/v3/review_activity?user_id=\(userID)&start_date=\(startDateString)&end_date=\(endDateString)") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("🔍 Fetching review activity from \(startDateString) to \(endDateString) for user \(userID)")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("❌ Review activity request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("❌ Review activity request failed with status: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                completion(.failure(DictionaryError.noData))
                return
            }
            
            do {
                let reviewActivityResponse = try JSONDecoder().decode(ReviewActivityResponse.self, from: data)
                self.logger.info("✅ Successfully fetched \(reviewActivityResponse.review_dates.count) review dates")
                completion(.success(reviewActivityResponse.review_dates))
            } catch {
                self.logger.error("Failed to decode review activity response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    func getLeaderboard(completion: @escaping (Result<[LeaderboardEntry], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/v3/leaderboard") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("🏆 Fetching leaderboard")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("❌ Leaderboard request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(DictionaryError.invalidResponse))
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                self.logger.error("❌ Leaderboard request failed with status: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }
            
            guard let data = data else {
                completion(.failure(DictionaryError.noData))
                return
            }
            
            self.logger.info("✅ Leaderboard response received: \(data.count) bytes")
            
            do {
                let leaderboardResponse = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
                self.logger.info("✅ Leaderboard decoded: \(leaderboardResponse.leaderboard.count) entries")
                completion(.success(leaderboardResponse.leaderboard))
            } catch {
                self.logger.error("Failed to decode leaderboard response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }
    
    func getForgettingCurve(wordId: Int, completion: @escaping (Result<ForgettingCurveResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/words/\(wordId)/forgetting-curve?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)") else {
            logger.error("Invalid URL for forgetting curve endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }
        
        logger.info("Fetching forgetting curve for word ID: \(wordId), user: \(userID)")
        
        performNetworkRequest(
            url: url,
            method: "GET",
            body: nil,
            responseType: ForgettingCurveResponse.self,
            completion: completion
        )
    }
    
    func getIllustration(word: String, language: String, completion: @escaping (Result<IllustrationResponse, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/v3/illustration") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        let requestBody: [String: Any] = [
            "word": word,
            "language": language
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData
        request.timeoutInterval = 60.0  // Longer timeout for potential AI generation

        logger.info("🎨 Getting illustration for word: \(word) (cache-first with generation fallback)")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("❌ Get illustration request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("❌ Get illustration failed with status: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let illustrationResponse = try JSONDecoder().decode(IllustrationResponse.self, from: data)
                if illustrationResponse.cached == true {
                    self.logger.info("✅ Cached illustration retrieved for: \(word)")
                } else {
                    self.logger.info("✅ New illustration generated for: \(word)")
                }
                completion(.success(illustrationResponse))
            } catch {
                self.logger.error("Failed to decode illustration response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    // Backward compatibility: generateIllustration now just calls getIllustration
    func generateIllustration(word: String, language: String, completion: @escaping (Result<IllustrationResponse, Error>) -> Void) {
        getIllustration(word: word, language: language, completion: completion)
    }

    func submitFeedback(feedback: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/feedback") else {
            logger.error("Invalid URL for feedback endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "user_id": userID,
            "feedback": feedback
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            logger.error("Failed to encode feedback request: \(error)")
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.logger.error("Network error submitting feedback: \(error)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self?.logger.error("Invalid response type for feedback submission")
                completion(.failure(DictionaryError.noData))
                return
            }

            if httpResponse.statusCode == 201 {
                self?.logger.info("Successfully submitted feedback")
                completion(.success(true))
            } else {
                self?.logger.error("Failed to submit feedback. Status: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
            }
        }.resume()
    }

    func getReviewProgressStats(completion: @escaping (Result<ReviewProgressStats, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/reviews/progress_stats?user_id=\(userID)") else {
            logger.error("Invalid URL for review progress stats endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                self?.logger.error("Network error fetching review progress stats: \(error)")
                completion(.failure(error))
                return
            }

            guard let data = data else {
                self?.logger.error("No data received for review progress stats")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let stats = try JSONDecoder().decode(ReviewProgressStats.self, from: data)
                self?.logger.info("Successfully decoded review progress stats")
                completion(.success(stats))
            } catch {
                self?.logger.error("Failed to decode review progress stats: \(error)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    // MARK: - Pronunciation Practice

    func practicePronunciation(originalText: String, audioData: Data, metadata: [String: Any], completion: @escaping (Result<PronunciationResult, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/pronunciation/practice") else {
            logger.error("Invalid URL for pronunciation practice endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Submitting pronunciation practice for text: '\(originalText)'")

        let audioBase64 = audioData.base64EncodedString()

        let requestBody: [String: Any] = [
            "user_id": userID,
            "original_text": originalText,
            "audio_data": audioBase64,
            "metadata": metadata
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            logger.error("Failed to encode pronunciation practice request")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData
        request.timeoutInterval = 30.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.logger.error("Network error in pronunciation practice: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self?.logger.error("Invalid response type for pronunciation practice")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            self?.logger.info("Pronunciation practice response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                self?.logger.error("Server error in pronunciation practice: \(httpResponse.statusCode)")

                // Handle speech recognition failures from server
                if httpResponse.statusCode == 500, let data = data,
                   let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = responseDict["error"] as? String {

                    // Return a "failed" result instead of an error for speech recognition issues
                    let result = PronunciationResult(
                        result: false,
                        similarityScore: 0.0,
                        recognizedText: "",
                        feedback: errorMessage
                    )
                    self?.logger.info("Speech recognition failed, returning negative result")
                    completion(.success(result))
                    return
                }

                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self?.logger.error("No data received for pronunciation practice")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let result = PronunciationResult(
                    result: responseDict?["result"] as? Bool ?? false,
                    similarityScore: responseDict?["similarity_score"] as? Double ?? 0.0,
                    recognizedText: responseDict?["recognized_text"] as? String ?? "",
                    feedback: responseDict?["feedback"] as? String ?? ""
                )

                self?.logger.info("Successfully processed pronunciation practice")
                completion(.success(result))
            } catch {
                self?.logger.error("Failed to decode pronunciation practice response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    // MARK: - Test Preparation Methods

    func getTestSettings(userID: String, completion: @escaping (Result<TestSettingsResponse, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/v3/api/test-prep/settings?user_id=\(userID)") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        performNetworkRequest(url: url, responseType: TestSettingsResponse.self, completion: completion)
    }

    func updateTestSettings(userID: String, toeflEnabled: Bool?, ieltsEnabled: Bool?, toeflTargetDays: Int?, ieltsTargetDays: Int?, completion: @escaping (Result<TestSettingsUpdateResponse, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/v3/api/test-prep/settings") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        let requestBody = TestSettingsUpdateRequest(
            user_id: userID,
            toefl_enabled: toeflEnabled,
            ielts_enabled: ieltsEnabled,
            toefl_target_days: toeflTargetDays,
            ielts_target_days: ieltsTargetDays
        )

        guard let body = try? JSONEncoder().encode(requestBody) else {
            logger.error("Failed to encode test settings update request")
            completion(.failure(DictionaryError.decodingError(NSError(domain: "EncodingError", code: 0))))
            return
        }

        performNetworkRequest(
            url: url,
            method: "PUT",
            body: body,
            responseType: TestSettingsUpdateResponse.self,
            completion: completion
        )
    }

    func getTestVocabularyStats(language: String = "en", completion: @escaping (Result<TestVocabularyStatsResponse, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/v3/api/test-prep/stats?language=\(language)") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        performNetworkRequest(url: url, responseType: TestVocabularyStatsResponse.self, completion: completion)
    }

    // MARK: - Schedule Methods

    func createSchedule(testType: String, targetEndDate: String, completion: @escaping (Result<CreateScheduleResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/schedule/create") else {
            logger.error("Invalid URL for create schedule endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Creating schedule - User: \(userID), Test: \(testType), End Date: \(targetEndDate)")

        let requestBody: [String: Any] = [
            "user_id": userID,
            "test_type": testType,
            "target_end_date": targetEndDate
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            logger.error("Failed to encode create schedule request")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Network error creating schedule: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for create schedule")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            self.logger.info("Create schedule response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error creating schedule: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for create schedule")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let scheduleResponse = try JSONDecoder().decode(CreateScheduleResponse.self, from: data)
                self.logger.info("Successfully created schedule with ID: \(scheduleResponse.schedule.schedule_id)")
                completion(.success(scheduleResponse))
            } catch {
                self.logger.error("Failed to decode create schedule response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func refreshSchedule(completion: @escaping (Result<CreateScheduleResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/schedule/refresh?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)") else {
            logger.error("Invalid URL for refresh schedule endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Refreshing schedule for user: \(userID)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Network error refreshing schedule: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response for refresh schedule")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error refreshing schedule: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for refresh schedule")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let scheduleResponse = try JSONDecoder().decode(CreateScheduleResponse.self, from: data)
                self.logger.info("Successfully refreshed schedule with ID: \(scheduleResponse.schedule.schedule_id)")
                completion(.success(scheduleResponse))
            } catch {
                self.logger.error("Failed to decode refresh schedule response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func getTodaySchedule(completion: @escaping (Result<DailyScheduleEntry, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/schedule/today?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)") else {
            logger.error("Invalid URL for today schedule endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching today's schedule for user: \(userID)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Network error fetching today schedule: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for today schedule")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            self.logger.info("Today schedule response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error fetching today schedule: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for today schedule")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let scheduleEntry = try JSONDecoder().decode(DailyScheduleEntry.self, from: data)
                
                self.logger.info("Successfully fetched today's schedule - has_schedule: \(scheduleEntry.has_schedule)")
                if let tt = scheduleEntry.test_type {
                       print("The test type string is: \(tt)") // Prints "The string is: Hello"
                   } else {
                       print("The test type string  is nil.")
                   }
                completion(.success(scheduleEntry))
            } catch {
                self.logger.error("Failed to decode today schedule response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func getScheduleRange(days: Int = 7, onlyNewWords: Bool = true, completion: @escaping (Result<GetScheduleRangeResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        let onlyNewWordsParam = onlyNewWords ? "true" : "false"
        guard let url = URL(string: "\(baseURL)/v3/schedule/range?user_id=\(userID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userID)&days=\(days)&only_new_words=\(onlyNewWordsParam)") else {
            logger.error("Invalid URL for schedule range endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching schedule range for \(days) days (only new words: \(onlyNewWords))")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Network error fetching schedule range: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for schedule range")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for schedule range")
                completion(.failure(DictionaryError.noData))
                return
            }

            if httpResponse.statusCode != 200 {
                self.logger.error("Schedule range request failed with status \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    self.logger.error("Response: \(responseString)")
                }
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            do {
                let decoder = JSONDecoder()
                let scheduleRangeResponse = try decoder.decode(GetScheduleRangeResponse.self, from: data)
                
                self.logger.info("Successfully fetched schedule range with \(scheduleRangeResponse.schedules.count) days")
                completion(.success(scheduleRangeResponse))
            } catch {
                self.logger.error("Failed to decode schedule range response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func reviewNewWord(word: String, response: Bool, completion: @escaping (Result<ReviewNewWordResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        let learningLang = UserManager.shared.learningLanguage
        let nativeLang = UserManager.shared.nativeLanguage

        guard let url = URL(string: "\(baseURL)/v3/review_new_word") else {
            logger.error("Invalid URL for review new word endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Reviewing new word: \(word), response: \(response)")

        let requestBody: [String: Any] = [
            "user_id": userID,
            "word": word,
            "response": response,
            "learning_language": learningLang,
            "native_language": nativeLang
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            logger.error("Failed to encode review new word request")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Network error reviewing new word: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for review new word")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            self.logger.info("Review new word response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error reviewing new word: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for review new word")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let reviewResponse = try JSONDecoder().decode(ReviewNewWordResponse.self, from: data)
                self.logger.info("Successfully reviewed new word: \(word)")
                completion(.success(reviewResponse))
            } catch {
                self.logger.error("Failed to decode review new word response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    func updateTimezone(timezone: String, completion: @escaping (Result<UpdateTimezoneResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/user/timezone") else {
            logger.error("Invalid URL for update timezone endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Updating timezone to: \(timezone)")

        let requestBody: [String: Any] = [
            "user_id": userID,
            "timezone": timezone
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            logger.error("Failed to encode update timezone request")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.logger.error("Network error updating timezone: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for update timezone")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            self.logger.info("Update timezone response status: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200 else {
                self.logger.error("Server error updating timezone: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for update timezone")
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let timezoneResponse = try JSONDecoder().decode(UpdateTimezoneResponse.self, from: data)
                self.logger.info("Successfully updated timezone to: \(timezoneResponse.timezone)")
                completion(.success(timezoneResponse))
            } catch {
                self.logger.error("Failed to decode update timezone response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    // MARK: - Test Progress

    func getTestProgress(completion: @escaping (Result<TestProgressResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/schedule/test-progress?user_id=\(userID)") else {
            logger.error("Invalid URL for test progress endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching test progress for user: \(userID)")
        performNetworkRequest(url: url, responseType: TestProgressResponse.self, completion: completion)
    }

    // MARK: - Streak Days

    /// Get the current streak days for the user
    func getStreakDays(completion: @escaping (Result<StreakDaysResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/get-streak-days?user_id=\(userID)") else {
            logger.error("Invalid URL for streak days endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching streak days for user: \(userID)")
        performNetworkRequest(url: url, responseType: StreakDaysResponse.self, completion: completion)
    }

    func getAchievementProgress(completion: @escaping (Result<AchievementProgressResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/achievements/progress?user_id=\(userID)") else {
            logger.error("Invalid URL for achievements endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Fetching achievement progress for user: \(userID)")
        performNetworkRequest(url: url, responseType: AchievementProgressResponse.self, completion: completion)
    }

}

struct ReviewActivityResponse: Codable {
    let user_id: String
    let review_dates: [String]
    let start_date: String
    let end_date: String
}

struct WeeklyReviewResponse: Codable {
    let daily_counts: [DailyReviewCount]
}

enum DictionaryError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noData
    case notFound
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
        case .notFound:
            return "Word not found"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
