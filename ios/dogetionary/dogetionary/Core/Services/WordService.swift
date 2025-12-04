//
//  WordService.swift
//  dogetionary
//
//  Handles word definitions, saving, and vocabulary management
//

import Foundation

class WordService: BaseNetworkService {
    static let shared = WordService()

    private init() {
        super.init(category: "WordService")
    }

    // MARK: - Word Search

    func searchWord(_ word: String, completion: @escaping (Result<[Definition], Error>) -> Void) {
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

        logger.info("Searching word: \(word)")

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

            do {
                let response = try JSONDecoder().decode(WordDefinitionResponse.self, from: data)
                let definition = Definition(from: response)

                // Preload word audio for better UX
                AudioService.shared.fetchAudioForText(definition.word, language: learningLanguage) { _ in }

                self.logger.info("Successfully decoded word definition for: \(response.word)")
                completion(.success([definition]))
            } catch {
                self.logger.error("Failed to decode response: \(error.localizedDescription)")
                completion(.failure(DictionaryError.decodingError(error)))
            }
        }.resume()
    }

    // MARK: - Saved Words Management

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

            guard httpResponse.statusCode == 200 else {
                // If endpoint doesn't exist (404), return empty array instead of error
                if httpResponse.statusCode == 404 {
                    self.logger.info("Saved words endpoint not found, returning empty array")
                    completion(.success([]))
                    return
                }
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

    func isWordSaved(word: String, learningLanguage: String, nativeLanguage: String, completion: @escaping (Result<(isSaved: Bool, savedWordId: Int?), Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        let wordEncoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word

        guard let url = URL(string: "\(baseURL)/v3/is-word-saved?user_id=\(userID)&word=\(wordEncoded)&learning_lang=\(learningLanguage)&native_lang=\(nativeLanguage)") else {
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard let data = data else {
                completion(.failure(DictionaryError.noData))
                return
            }

            do {
                let result = try JSONDecoder().decode(IsWordSavedResponse.self, from: data)
                completion(.success((isSaved: result.is_saved, savedWordId: result.saved_word_id)))
            } catch {
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

    func toggleExcludeFromPractice(word: String, excluded: Bool, learningLanguage: String? = nil, nativeLanguage: String? = nil, completion: @escaping (Result<ToggleExcludeResponse, Error>) -> Void) {
        let userID = UserManager.shared.getUserID()
        guard let url = URL(string: "\(baseURL)/v3/words/toggle-exclude") else {
            logger.error("Invalid URL for toggle-exclude endpoint")
            completion(.failure(DictionaryError.invalidURL))
            return
        }

        logger.info("Toggling exclusion for word: '\(word)' to \(excluded) for user: \(userID)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var requestBody: [String: Any] = [
            "user_id": userID,
            "word": word,
            "excluded": excluded
        ]

        if let learningLang = learningLanguage {
            requestBody["learning_language"] = learningLang
        }
        if let nativeLang = nativeLanguage {
            requestBody["native_language"] = nativeLang
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            logger.error("Failed to encode toggle-exclude request: \(error.localizedDescription)")
            completion(.failure(DictionaryError.decodingError(error)))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error toggling exclusion: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response type for toggle-exclude")
                completion(.failure(DictionaryError.invalidResponse))
                return
            }

            guard let data = data else {
                self.logger.error("No data received for toggle-exclude")
                completion(.failure(DictionaryError.noData))
                return
            }

            if httpResponse.statusCode == 200 {
                do {
                    let response = try JSONDecoder().decode(ToggleExcludeResponse.self, from: data)
                    self.logger.info("Successfully toggled exclusion for word: '\(word)'")
                    completion(.success(response))
                } catch {
                    self.logger.error("Failed to decode toggle-exclude response: \(error.localizedDescription)")
                    completion(.failure(DictionaryError.decodingError(error)))
                }
            } else {
                self.logger.error("Server error toggling exclusion: \(httpResponse.statusCode)")
                completion(.failure(DictionaryError.serverError(httpResponse.statusCode)))
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

        logger.info("Fetching word details for word ID: \(wordID)")

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
